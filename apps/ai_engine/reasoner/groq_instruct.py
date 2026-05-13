import os
import json
import re
import asyncio
import logging
from groq import Groq

logger = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────

_MODEL         = "llama-3.3-70b-versatile"
_MAX_OCR_CHARS = 6000   # cap OCR input to avoid token overflow
_NULL_TOKENS   = {"", "null", "none", "n/a", "na", "not available"}

# ── Client ────────────────────────────────────────────────────────────────────

_client = None

def _get_client() -> Groq:
    global _client
    if _client is None:
        api_key = os.environ.get("GROQ_API_KEY")
        if not api_key:
            raise RuntimeError("GROQ_API_KEY not set")
        _client = Groq(api_key=api_key)
    return _client

# ── Prompt ────────────────────────────────────────────────────────────────────

ABBREV_HINTS = """
Indian shorthand:
  OD=Once daily   BD=Twice daily   TDS=Three times daily   QID=Four times daily
  HS=At bedtime   SOS=As needed    AC=Before meals         PC=After meals
  T.=Tablet       Cap.=Capsule     Syr.=Syrup              Inj.=Injection

Indian brand -> generic:
  Dolo 650 / Crocin        -> Paracetamol
  Pan / Pan-D              -> Pantoprazole
  Azee / Zithromax         -> Azithromycin
  Combiflam                -> Ibuprofen + Paracetamol
  Glycomet / Bigomet       -> Metformin
  Stamlo / Amlip           -> Amlodipine
  Metrogyl                 -> Metronidazole
  Augmentin                -> Amoxicillin + Clavulanate
  Allegra                  -> Fexofenadine
  Montair / Telekast       -> Montelukast
  Ecosprin                 -> Aspirin
  Sorbiline                -> Sorbitol
  Vertin                   -> Betahistine
  Rantac / Zinetac         -> Ranitidine
  Digene                   -> Antacid (Aluminium + Magnesium)

Dose validation ranges (flag if outside):
  Paracetamol  : 325mg-1000mg per dose, max 4g/day
  Ibuprofen    : 200mg-800mg per dose
  Amoxicillin  : 250mg-500mg per dose
  Metformin    : 500mg-1000mg per dose
  Pantoprazole : 40mg OD
  Azithromycin : 250mg-500mg OD
  Amlodipine   : 2.5mg-10mg OD
"""

_SYSTEM = (
    "You are an expert clinical pharmacist specialising in Indian prescriptions.\n"
    "Output ONLY valid JSON. No markdown. No explanation. No preamble.\n"
    "CRITICAL: Do NOT infer, guess, or hallucinate any medicine, dosage, or "
    "frequency not explicitly present in the text.\n"
    "If a field is unclear or missing write exactly 'Not specified' — never guess.\n"
    + ABBREV_HINTS
)

_SCHEMA = """{
  "patient_name": "string or Not specified",
  "doctor": "string or Not specified",
  "diagnosis": "string or Not specified",
  "medicines": [
    {
      "name": "brand name as written",
      "generic_name": "INN generic name",
      "dosage": "dose per administration e.g. 500mg",
      "frequency": "once daily / twice daily / three times daily / etc",
      "duration": "e.g. 5 days or Not specified",
      "instructions": "e.g. after meals / before meals / Not specified",
      "type": "tablet / capsule / syrup / injection / Not specified",
      "dose_flag": "OK / LOW / HIGH / VERIFY",
      "dose_flag_reason": "reason string or Not specified"
    }
  ],
  "confidence": "high / medium / low"
}"""

# ── Helpers ───────────────────────────────────────────────────────────────────

def _safe_str(value) -> str:
    if value is None:
        return "Not specified"
    value = str(value).strip()
    if value.lower() in _NULL_TOKENS:
        return "Not specified"
    return value


def _sanitise(result: dict) -> dict:
    """Returns a NEW sanitised dict — does not mutate the input."""
    clean = {
        "patient_name": _safe_str(result.get("patient_name")),
        "doctor"      : _safe_str(result.get("doctor")),
        "diagnosis"   : _safe_str(result.get("diagnosis")),
        "confidence"  : _safe_str(result.get("confidence")),
        "medicines"   : [
            {
                "name"            : _safe_str(med.get("name")),
                "generic_name"    : _safe_str(med.get("generic_name")),
                "dosage"          : _safe_str(med.get("dosage")),
                "frequency"       : _safe_str(med.get("frequency")),
                "duration"        : _safe_str(med.get("duration")),
                "instructions"    : _safe_str(med.get("instructions")),
                "type"            : _safe_str(med.get("type")),
                "dose_flag"       : _safe_str(med.get("dose_flag")),
                "dose_flag_reason": _safe_str(med.get("dose_flag_reason")),
            }
            for med in result.get("medicines", [])
        ],
    }
    return clean


def _strip_fences(raw: str) -> str:
    """Removes markdown code fences the model sometimes adds."""
    raw = re.sub(r"^```(?:json)?", "", raw, flags=re.MULTILINE).strip()
    raw = re.sub(r"```$",          "", raw, flags=re.MULTILINE).strip()
    return raw


def _call_groq_instruct(prompt: str) -> str:
    """Synchronous Groq call — must be run via executor."""
    response = _get_client().chat.completions.create(
        model=_MODEL,
        messages=[
            {"role": "system", "content": _SYSTEM},
            {"role": "user",   "content": prompt},
        ],
        temperature=0.1,
        max_tokens=2048,
    )
    return response.choices[0].message.content.strip()


# ── Main function ─────────────────────────────────────────────────────────────

async def groq_extract_medicines(ocr_text: str) -> dict:
    if not ocr_text.strip():
        logger.warning("groq_extract_medicines: empty OCR text received")
        return {"medicines": [], "confidence": "low", "error": "Empty OCR text"}

    # cap OCR input to avoid token overflow
    if len(ocr_text) > _MAX_OCR_CHARS:
        logger.warning(f"OCR text truncated from {len(ocr_text)} to {_MAX_OCR_CHARS} chars")
        ocr_text = ocr_text[:_MAX_OCR_CHARS]

    prompt = (
        f"Extract all medicines from this prescription text.\n\n"
        f"Prescription:\n{ocr_text}\n\n"
        f"Return ONLY this JSON structure:\n{_SCHEMA}"
    )

    loop = asyncio.get_event_loop()

    for attempt in range(3):
        try:
            # run sync SDK in thread pool — does not block event loop
            raw = await loop.run_in_executor(None, _call_groq_instruct, prompt)
            raw = _strip_fences(raw)
            result = json.loads(raw)
            logger.info(f"Extracted {len(result.get('medicines', []))} medicines")
            return _sanitise(result)

        except json.JSONDecodeError as e:
            logger.warning(f"JSON parse failed (attempt {attempt + 1}): {e}")
            if attempt < 2:
                await asyncio.sleep(2 ** attempt)
            else:
                return {
                    "medicines" : [],
                    "confidence": "low",
                    "error"     : "Model returned invalid JSON after 3 attempts",
                }

        except Exception as e:
            logger.warning(f"Groq instruct attempt {attempt + 1} failed: {type(e).__name__}: {e}")
            if attempt < 2:
                await asyncio.sleep(2 ** attempt)
            else:
                return {
                    "medicines" : [],
                    "confidence": "low",
                    "error"     : str(e),
                }

    return {"medicines": [], "confidence": "low"}