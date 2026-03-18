"""
qwen_instruct.py
─────────────────
Fix: NOT NULL constraint failed: prescriptions_medicine.frequency

Root cause:
    LLM returns {"frequency": null} when frequency isn't visible.
    json.loads() converts null → Python None.
    med.get("frequency", "") returns None (not "") when key exists but is None.
    Django Medicine.frequency has null=False → IntegrityError.

Fixes applied:
    1. System prompt: "Never return null. Use Not specified instead."
    2. Prompt: explicit instruction with example showing "Not specified"
    3. _sanitise_medicine(): converts None/null/empty → "Not specified"
       This runs on EVERY medicine after parsing — null can never reach DB.
"""

import os
import json
import re
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()


_SYSTEM_PROMPT = (
    "You are an expert medical prescription parser specialising in handwritten prescriptions. "
    "You have deep knowledge of medicine names, dosages, and prescription abbreviations used by doctors. "
    "Extract structured medicine information from OCR outputs of a handwritten prescription. "
    "Cross-reference both OCR sources to reconstruct the most accurate prescription possible. "
    "CRITICAL: Never use null for any field. If information is missing, use the string 'Not specified'. "
    "Always return valid JSON only. No explanations. No markdown."
)


class MedicineReasoner:

    def __init__(self, model_name: str = "Qwen/Qwen2.5-7B-Instruct"):
        self.model_name = model_name

        hf_token = os.getenv("HF_TOKEN")
        if not hf_token:
            raise ValueError("HF_TOKEN not found in environment variables")

        self.client = OpenAI(
            base_url="https://router.huggingface.co/v1",
            api_key=hf_token,
        )
        print(f"✅ MedicineReasoner ready (model: {model_name})")

    # ── Null safety — runs on EVERY medicine before leaving this class ─────

    @staticmethod
    def _sanitise(med: dict) -> dict:
        """
        Guarantee all required fields exist and contain non-null strings.

        Handles: None, "null", "None", "n/a", "-", "", whitespace-only
        → all become "Not specified"

        This is the last line of defence before medicines reach the DB.
        """
        def clean(val) -> str:
            if val is None:
                return "Not specified"
            s = str(val).strip()
            if s.lower() in ("null", "none", "n/a", "na", "-", ""):
                return "Not specified"
            return s

        return {
            "medicine":  clean(med.get("medicine")),
            "dosage":    clean(med.get("dosage")),
            "frequency": clean(med.get("frequency")),
        }

    # ── JSON extraction ────────────────────────────────────────────────────

    def _extract_json(self, text: str) -> dict:
        if not text:
            return {"medicines": []}

        text = re.sub(r"```json|```", "", text).strip()

        # Strategy 1: JSON array regex
        match = re.search(r"\[\s*\{.*?\}\s*\]", text, re.DOTALL)
        if match:
            try:
                medicines = json.loads(match.group())
                if isinstance(medicines, list) and medicines:
                    medicines = [self._sanitise(m) for m in medicines]
                    print(f"✅ JSON parsed: {len(medicines)} medicines (strategy 1)")
                    return {"medicines": medicines}
            except json.JSONDecodeError:
                pass

        # Strategy 2: full response parse
        try:
            data = json.loads(text)
            if isinstance(data, list):
                medicines = [self._sanitise(m) for m in data]
                print(f"✅ JSON parsed: {len(medicines)} medicines (strategy 2)")
                return {"medicines": medicines}
            if isinstance(data, dict) and "medicines" in data:
                data["medicines"] = [self._sanitise(m) for m in data["medicines"]]
                return data
        except json.JSONDecodeError:
            pass

        # Strategy 3: partial object recovery (truncated response)
        partial = re.findall(
            r'\{\s*"medicine"\s*:\s*"[^"]+"\s*,\s*"dosage"\s*:\s*"[^"]*"\s*,'
            r'\s*"frequency"\s*:\s*(?:"[^"]*"|null)\s*\}',
            text
        )
        if partial:
            try:
                medicines = [self._sanitise(json.loads(m)) for m in partial]
                print(f"⚠️  Partial recovery: {len(medicines)} medicines (strategy 3)")
                return {"medicines": medicines}
            except json.JSONDecodeError:
                pass

        print(f"⚠️  JSON parse failed. Snippet: {text[:200]}")
        return {"medicines": []}

    # ── Prompt builder ─────────────────────────────────────────────────────

    def _build_prompt(self, paddle_text: str, qwen_text: str) -> str:
        has_paddle = bool(paddle_text.strip())
        has_qwen   = bool(qwen_text.strip())

        # JSON format example — uses "Not specified" not null
        json_format = (
            '[\n'
            '  {"medicine": "Paracetamol", "dosage": "500mg", "frequency": "Twice daily"},\n'
            '  {"medicine": "Amoxicillin", "dosage": "250mg", "frequency": "Not specified"}\n'
            ']'
        )

        if has_paddle and not has_qwen:
            return (
                f"OCR text from a handwritten prescription:\n\n{paddle_text.strip()}\n\n"
                f"Extract all medicines. Use \"Not specified\" (never null) for missing fields.\n"
                f"Return ONLY JSON:\n{json_format}"
            )

        if has_qwen and not has_paddle:
            return (
                f"OCR text from a handwritten prescription:\n\n{qwen_text.strip()}\n\n"
                f"Extract all medicines. Use \"Not specified\" (never null) for missing fields.\n"
                f"Return ONLY JSON:\n{json_format}"
            )

        return f"""Two OCR engines processed the same cluttered handwritten prescription.

=== SOURCE A: PaddleOCR (reliable for numbers, dosages, structured text) ===
{paddle_text.strip()}

=== SOURCE B: Qwen2-VL Vision OCR (reliable for medicine names, handwriting context) ===
{qwen_text.strip()}

Cross-validation rules:
1. For medicine NAMES: trust Source B more. Verify against Source A.
   Merge fragments (e.g. "Arnox" + "Amox" → "Amoxicillin").
2. For DOSAGES and NUMBERS: trust Source A more (e.g. "500mg", "1-0-1").
3. Include medicines found in ONLY ONE source.
4. Merge duplicate entries with different spellings into one.
5. Use medical knowledge to correct OCR spelling errors.
6. Do NOT invent medicines absent from both sources.
7. Use "Not specified" for missing fields. NEVER use null.

Return ONLY valid JSON. No explanation. No markdown.

{json_format}"""

    # ── Public API ─────────────────────────────────────────────────────────

    def reason(self, paddle_text: str, qwen_text: str) -> dict:
        if not paddle_text.strip() and not qwen_text.strip():
            print("⚠️  Both OCR inputs empty — skipping LLM call")
            return {"medicines": []}

        try:
            completion = self.client.chat.completions.create(
                model=self.model_name,
                messages=[
                    {"role": "system", "content": _SYSTEM_PROMPT},
                    {"role": "user",   "content": self._build_prompt(paddle_text, qwen_text)},
                ],
                temperature=0.1,
                max_tokens=1024,
            )

            if not completion.choices:
                print("⚠️  No response from LLM")
                return {"medicines": []}

            response_text = completion.choices[0].message.content.strip()
            print(f"📝 LLM raw response:\n{response_text}\n")

            return self._extract_json(response_text)

        except Exception as e:
            print(f"❌ LLM API error: {e}")
            return {"medicines": []}