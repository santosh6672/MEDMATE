"""
medicine_reasoner/qwen_instruct.py
────────────────────────────────────
Qwen2.5-7B-Instruct via featherless-ai on HF Router.

Role: receives corrected prescription text → returns structured JSON
      with medicines, patient info, clinical flags, and interactions.

Uses chat.completions.create with:
  - system role: clinical pharmacist persona + Indian drug knowledge
  - user role: corrected prescription text + JSON schema
  - temperature=0.0: deterministic JSON output
  - 'Not specified' sentinel: null never reaches the database

Fixes vs original:
  - LLM_MODEL read from Django settings (falls back to default constant)
  - _client singleton protected by _client_lock — thread-safe
  - _safe() replaced by shared safe_str() from utils.sanitise
  - Retry wait loop raises AIExtractionError instead of silently returning {}
    so tasks.py can distinguish a real failure from a blank prescription
  - logging instead of print()
  - Top-level metadata fields (patient_name, date, etc.) also sanitised
"""

import json
import logging
import re
import threading
import time

from openai import OpenAI

from apps.ai_engine.utils.sanitise import safe_str

logger = logging.getLogger(__name__)

# ── Model config — override in settings.py as LLM_MODEL ──────────────────────
_DEFAULT_MODEL = "Qwen/Qwen2.5-7B-Instruct:featherless-ai"


def _get_llm_model() -> str:
    try:
        from django.conf import settings
        return getattr(settings, "LLM_MODEL", _DEFAULT_MODEL)
    except Exception:
        return _DEFAULT_MODEL


# ── Prompt components ─────────────────────────────────────────────────────────
ABBREV_HINTS = """
Indian shorthand:
  OD=Once daily  BD=Twice daily  TDS=Three times daily  QID=Four times daily
  HS=At bedtime  SOS=As needed   AC=Before meals        PC=After meals
  T.=Tablet      Cap.=Capsule    Syr.=Syrup             w/f=With food

Indian brand → generic:
  Dolo 650 / Crocin / Calpol  → Paracetamol
  Pan / Pan-D / Pantocid      → Pantoprazole (Pan-D also has Domperidone)
  Azee / Zithromax            → Azithromycin
  Combiflam                   → Ibuprofen + Paracetamol
  Taxim-O / Zifi              → Cefixime
  Cifran / Ciplox             → Ciprofloxacin
  Montair                     → Montelukast
  Shelcal / Calcirol          → Calcium + Vitamin D3
  Glycomet / Bigomet          → Metformin
  Atocor / Storvas            → Atorvastatin
  Stamlo / Amlip              → Amlodipine
  Telma / Telmikind           → Telmisartan
  Diclo / Voveran             → Diclofenac
  Deriphyllin                 → Theophylline + Etofylline
  Omnacortil                  → Prednisolone
  Metrogyl                    → Metronidazole
  Sp / Spas                   → Dicyclomine
"""

_SYSTEM = (
    "You are an expert clinical pharmacist specialising in Indian prescriptions.\n"
    "Output ONLY valid JSON. No markdown. No explanation. "
    "No text before or after the JSON.\n\n"
    f"{ABBREV_HINTS}\n\n"
    "Date field = prescription date only, never patient DOB.\n"
    "Azithromycin day1/day2 dosing = ONE medicine entry, duration 5 days.\n"
    "Never use null — use 'Not specified' for missing fields.\n\n"
    "Clinical dose validation:\n"
    "  Paracetamol  : 500-1000mg/dose, max 4000mg/day\n"
    "  Azithromycin : 500mg day1 then 250mg days2-5\n"
    "  Amoxicillin  : 250-500mg TDS\n"
    "  Ibuprofen    : 200-400mg TDS, max 1200mg/day\n"
    "  Diclofenac   : 50mg BD/TDS, max 150mg/day\n"
    "  Metformin    : 500-1000mg BD/TDS with meals\n"
    "  Pantoprazole : 40mg OD before breakfast\n"
    "  Cetirizine   : 10mg OD at night\n"
    "  Amlodipine   : 5-10mg OD\n"
    "  Atorvastatin : 10-80mg OD at night"
)

_JSON_SCHEMA = """{
  "patient_name": "full name or Not specified",
  "date": "prescription date or Not specified",
  "doctor": "doctor name or Not specified",
  "diagnosis": "diagnosis or Not specified",
  "allergies": "allergies or Not specified",
  "medicines": [
    {
      "name": "name as written",
      "generic_name": "full INN name",
      "dosage": "dose per administration or Not specified",
      "frequency": "once daily / twice daily / etc or Not specified",
      "duration": "X days or Not specified",
      "instructions": "after meals / etc or Not specified",
      "type": "tablet/capsule/syrup/injection/topical/supplement",
      "dose_flag": "OK/LOW/HIGH/VERIFY",
      "dose_flag_reason": "reason if not OK or Not specified"
    }
  ],
  "drug_interactions": [],
  "clinical_notes": "observations or Not specified",
  "confidence": "high/medium/low"
}"""

# ── OpenAI client singleton (thread-safe) ─────────────────────────────────────
_client: OpenAI | None = None
_client_lock = threading.Lock()


def _get_client() -> OpenAI:
    global _client
    with _client_lock:
        if _client is None:
            import os
            token = os.environ.get("HF_TOKEN", "")
            if not token:
                raise RuntimeError(
                    "HF_TOKEN environment variable is not set. "
                    "Add it to your .env or Django settings."
                )
            _client = OpenAI(
                base_url="https://router.huggingface.co/v1",
                api_key=token,
            )
            logger.info("MedicineReasoner HF client ready")
    return _client


# ── Custom exception so callers can distinguish failure from empty result ──────

class AIExtractionError(Exception):
    """Raised when the LLM fails after all retries."""


# ── Public API ────────────────────────────────────────────────────────────────

class MedicineReasoner:

    def reason(self, corrected_text: str) -> dict:
        """
        Extract structured medicine data from corrected prescription text.

        Args:
            corrected_text: Output of vision_reasoner.qwen2.correct_ocr()

        Returns:
            dict with 'medicines' list and patient metadata.
            All string fields use 'Not specified' sentinel — never null.

        Raises:
            AIExtractionError: If all LLM retry attempts fail.
        """
        if not corrected_text.strip():
            logger.warning("Empty corrected_text — skipping LLM call")
            return {"medicines": []}

        model  = _get_llm_model()
        client = _get_client()

        user_prompt = (
            "Extract all medicines from this prescription text.\n"
            "Only extract medicines explicitly present. Never invent medicines.\n\n"
            f"Prescription:\n{corrected_text}\n\n"
            f"Return ONLY this JSON — 'Not specified' for missing, never null:\n{_JSON_SCHEMA}"
        )

        raw         = ""
        last_error  = None

        for attempt in range(1, 4):
            try:
                t1         = time.time()
                completion = client.chat.completions.create(
                    model=model,
                    messages=[
                        {"role": "system", "content": _SYSTEM},
                        {"role": "user",   "content": user_prompt},
                    ],
                    max_tokens=800,
                    temperature=0.0,
                )
                raw = completion.choices[0].message.content.strip()
                logger.info("LLM done — %.1fs (attempt %d)", time.time() - t1, attempt)
                last_error = None
                break

            except Exception as exc:
                last_error = exc
                err_str    = str(exc)
                logger.warning("LLM attempt %d failed: %s", attempt, err_str[:150])

                if attempt < 3:
                    # Respect rate-limit Retry-After header if present in error message
                    m    = re.search(r"(\d+)\s*s", err_str)
                    wait = int(m.group(1)) + 5 if m else 20 * attempt
                    logger.info("Waiting %ds before retry …", wait)
                    time.sleep(wait)

        if last_error is not None:
            raise AIExtractionError(
                f"LLM extraction failed after 3 attempts: {last_error}"
            ) from last_error

        return self._parse_and_sanitise(raw)

    # ── Private helpers ───────────────────────────────────────────────────────

    @staticmethod
    def _parse_and_sanitise(raw: str) -> dict:
        """
        Strip markdown fences, parse JSON, normalise all fields.
        Returns dict with guaranteed non-null values.
        """
        # Strip markdown code fences
        raw = re.sub(r"^```(?:json)?", "", raw, flags=re.MULTILINE).strip()
        raw = re.sub(r"```$",          "", raw, flags=re.MULTILINE).strip()

        # Extract the outermost JSON object in case there is surrounding text
        m = re.search(r"\{.*\}", raw, re.DOTALL)
        if m:
            raw = m.group()

        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            logger.error("JSON parse failed. Raw (first 300 chars): %s", raw[:300])
            return {"medicines": []}

        # Lowercase all top-level keys
        parsed = {k.lower(): v for k, v in parsed.items()}

        # Normalise confidence
        conf = str(parsed.get("confidence") or "").lower().strip()
        parsed["confidence"] = conf if conf in ("high", "medium", "low") else "medium"

        # Ensure list fields are always present
        for key in ("medicines", "drug_interactions"):
            if not isinstance(parsed.get(key), list):
                parsed[key] = []

        # Sanitise top-level string metadata
        for field in ("patient_name", "date", "doctor", "diagnosis",
                      "allergies", "clinical_notes"):
            parsed[field] = safe_str(parsed.get(field))

        # Sanitise every medicine field — null must never reach the DB
        parsed["medicines"] = [
            {
                "name":             safe_str(med.get("name")),
                "generic_name":     safe_str(med.get("generic_name")),
                "dosage":           safe_str(med.get("dosage")),
                "frequency":        safe_str(med.get("frequency")),
                "duration":         safe_str(med.get("duration")),
                "instructions":     safe_str(med.get("instructions")),
                "type":             safe_str(med.get("type")),
                "dose_flag":        safe_str(med.get("dose_flag")),
                "dose_flag_reason": safe_str(med.get("dose_flag_reason")),
            }
            for med in parsed["medicines"]
            if isinstance(med, dict)   # skip any malformed entries
        ]

        meds = parsed["medicines"]
        logger.info(
            "%d medicine(s) extracted  confidence=%s",
            len(meds), parsed["confidence"],
        )
        for med in meds:
            flag = med["dose_flag"]
            logger.debug(
                "  • %s (%s) %s %s%s",
                med["name"], med["generic_name"],
                med["dosage"], med["frequency"],
                f"  [{flag}]" if flag not in ("OK", "Not specified") else "",
            )

        return parsed