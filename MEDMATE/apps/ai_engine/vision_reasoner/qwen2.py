"""
vision_reasoner/qwen2.py
─────────────────────────
Qwen2-VL-2B-OCR — visual OCR correction.

Role: receives PaddleOCR's raw text + the original image,
      fixes character-level errors by cross-referencing both.

This is NOT independent OCR — Qwen corrects Paddle's output,
it does not replace it. This separation means:
  - Paddle handles character-level reading (its strength)
  - Qwen handles visual cross-referencing (its strength)
  - LLM receives one clean corrected text, not two conflicting outputs

Model is cached in _cache after first load — no reload between tasks.

VRAM: ~1478 MiB (INT4)

Fixes vs original:
  - _cache protected by _lock → safe under thread-based Celery concurrency
  - Removed pre-generate empty_cache() — hurts perf (forces CUDA realloc)
  - Removed unnecessary image.copy() — resize() always returns a new object
  - Removed gc.collect() — CPython GC handles cleanup without help here
  - logging instead of print()
  - CORRECTION_MAX_SIZE extracted as a named constant
"""

import logging
import threading
import time
import warnings

import torch
import transformers
from PIL import Image
from transformers import (
    AutoModelForImageTextToText,
    AutoProcessor,
    BitsAndBytesConfig,
)

warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)
transformers.logging.set_verbosity_error()

logger = logging.getLogger(__name__)

MODEL_ID            = "JackChew/Qwen2-VL-2B-OCR"
DEVICE              = "cuda" if torch.cuda.is_available() else "cpu"
CORRECTION_MAX_SIZE = 560   # px — sufficient detail for character correction

QUANT = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_compute_dtype=torch.float16,
    bnb_4bit_use_double_quant=True,
    bnb_4bit_quant_type="nf4",
)

_cache: dict          = {}
_lock:  threading.Lock = threading.Lock()


def _vram() -> float:
    if not torch.cuda.is_available():
        return 0.0
    return torch.cuda.memory_allocated() / 1024 ** 2


def _get_model():
    """Load model once; subsequent calls return the cached instance."""
    with _lock:
        if "qwen" not in _cache:
            logger.info("[load] Qwen2-VL-2B INT4 …")
            t = time.time()
            _cache["qwen"] = {
                "model": AutoModelForImageTextToText.from_pretrained(
                    MODEL_ID,
                    quantization_config=QUANT,
                    device_map={"": 0},   # Force EVERYTHING on GPU (prevents bitsandbytes errors)
                ).eval(),
                "processor": AutoProcessor.from_pretrained(MODEL_ID),
            }
            logger.info(
                "[load] Qwen ready — %.1fs  VRAM %.0f MiB",
                time.time() - t,
                _vram(),
            )
        else:
            logger.debug("[cache] Qwen ready — VRAM %.0f MiB", _vram())
    return _cache["qwen"]["model"], _cache["qwen"]["processor"]


def warmup() -> None:
    """Pre-load model into VRAM at worker startup."""
    _get_model()


_CORRECTION_PROMPT_TEMPLATE = (
    "Fix ONLY character-level OCR errors in the prescription text below.\n"
    "Use the image to verify what is actually written.\n\n"
    "PADDLE OCR TEXT:\n"
    "{paddle_text}\n\n"
    "STRICT RULES:\n"
    "1. Copy each line, correcting only misread characters\n"
    "2. Fix examples: '20g mg'→'200mg', '6s kg'→'65 kg', "
    "'#bD'→'BID', 'sml'→'mL'\n"
    "3. Do NOT add any new lines, fields, or information\n"
    "4. Do NOT add medical descriptions or notes\n"
    "5. Do NOT translate — keep original language\n"
    "6. Do NOT split one medicine into multiple lines\n"
    "7. Output corrected text only. Nothing else."
)


def correct_ocr(image: Image.Image, paddle_text: str) -> str:
    """
    Fix character-level OCR errors in paddle_text using the image as reference.

    Args:
        image:       RGB PIL image (same one passed to PaddleOCR).
        paddle_text: Raw text from PaddleOCR-VL.

    Returns:
        Corrected text string. Falls back to paddle_text if Qwen returns empty.
    """
    if not paddle_text.strip():
        return ""

    model, processor = _get_model()

    # Downscale only if needed — resize() always returns a new object
    w, h = image.size
    if max(w, h) > CORRECTION_MAX_SIZE:
        r   = CORRECTION_MAX_SIZE / max(w, h)
        img = image.resize((int(w * r), int(h * r)), Image.LANCZOS)
    else:
        img = image

    prompt   = _CORRECTION_PROMPT_TEMPLATE.format(paddle_text=paddle_text)
    messages = [{"role": "user", "content": [
        {"type": "image", "image": img},
        {"type": "text",  "text": prompt},
    ]}]
    inputs = processor.apply_chat_template(
        messages,
        add_generation_prompt=True,
        tokenize=True,
        return_dict=True,
        return_tensors="pt",
    ).to(DEVICE)

    t1 = time.time()
    with torch.inference_mode():
        out_ids = model.generate(
            **inputs,
            max_new_tokens=400,
            do_sample=False,
            temperature=None,
            top_p=None,
            repetition_penalty=1.3,
            no_repeat_ngram_size=4,
        )

    text = processor.decode(
        out_ids[0][inputs["input_ids"].shape[-1]: -1],
        skip_special_tokens=True,
    ).strip()

    logger.info("Qwen correction done — %.1fs  %d chars", time.time() - t1, len(text))

    # Release GPU tensors; let Python GC handle the rest
    del inputs, out_ids
    torch.cuda.empty_cache()

    return text if text else paddle_text