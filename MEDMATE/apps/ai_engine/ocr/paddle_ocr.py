"""
ocr/paddle_ocr.py
──────────────────
PaddleOCR-VL-1.5 — full-image text extraction (no CRAFT boxes).

Reads the full preprocessed prescription image in one pass.
Model is cached in _cache after first load — no reload between tasks.

VRAM: ~1727 MiB (FP16)

Fixes vs original:
  - _cache protected by _lock → safe under thread-based Celery concurrency
  - Removed pre-generate empty_cache() — hurts perf (forces CUDA realloc)
  - Removed unnecessary image.copy() — resize returns a new object anyway
  - Removed gc.collect() — no tight loop here; CPython GC handles it
  - logging instead of print()
  - OCR_MAX_SIZE extracted as a named constant
"""

import logging
import threading
import time
import warnings

import torch
import transformers
from PIL import Image
from transformers import AutoModelForImageTextToText, AutoProcessor

warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)
transformers.logging.set_verbosity_error()

logger = logging.getLogger(__name__)

MODEL_ID    = "PaddlePaddle/PaddleOCR-VL-1.5"
DEVICE      = "cuda" if torch.cuda.is_available() else "cpu"
OCR_MAX_SIZE = 448   # px — faster on RTX 3050; sufficient for character extraction

_cache: dict         = {}
_lock:  threading.Lock = threading.Lock()


def _vram() -> float:
    if not torch.cuda.is_available():
        return 0.0
    return torch.cuda.memory_allocated() / 1024 ** 2


def _get_model():
    """Load model once; subsequent calls return the cached instance."""
    with _lock:
        if "paddle" not in _cache:
            logger.info("[load] PaddleOCR-VL FP16 …")
            t = time.time()
            _cache["paddle"] = {
                "model": AutoModelForImageTextToText.from_pretrained(
                    MODEL_ID, dtype=torch.float16, device_map="auto"
                ).eval(),
                "processor": AutoProcessor.from_pretrained(MODEL_ID),
            }
            logger.info(
                "[load] Paddle ready — %.1fs  VRAM %.0f MiB",
                time.time() - t,
                _vram(),
            )
        else:
            logger.debug("[cache] Paddle ready — VRAM %.0f MiB", _vram())
    return _cache["paddle"]["model"], _cache["paddle"]["processor"]


def warmup() -> None:
    """Pre-load model into VRAM at worker startup."""
    _get_model()


def extract_text(image: Image.Image) -> str:
    """
    Run PaddleOCR-VL on a full prescription image.

    Args:
        image: RGB PIL image (from image_preprocessor.preprocess).

    Returns:
        Raw OCR text string. Empty string if generation produces nothing.

    Raises:
        RuntimeError: If the model fails to generate output.
    """
    model, processor = _get_model()

    # Downscale only if needed — resize() always returns a new object
    w, h = image.size
    if max(w, h) > OCR_MAX_SIZE:
        r   = OCR_MAX_SIZE / max(w, h)
        img = image.resize((int(w * r), int(h * r)), Image.LANCZOS)
    else:
        img = image

    messages = [{"role": "user", "content": [
        {"type": "image", "image": img},
        {"type": "text",  "text": "OCR:"},
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

    logger.info("PaddleOCR done — %.1fs  %d chars", time.time() - t1, len(text))

    # Release GPU tensors immediately; let Python GC handle the rest
    del inputs, out_ids
    torch.cuda.empty_cache()

    return text