"""
vision_reasoner/qwen2.py
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
CORRECTION_MAX_SIZE = 560
MAX_NEW_TOKENS      = 300

_cache: dict           = {}
_lock:  threading.Lock = threading.Lock()


def _build_quant_config() -> BitsAndBytesConfig | None:
    if DEVICE == "cpu":
        logger.warning("No CUDA detected — Qwen2-VL will run on CPU in float32 (slow)")
        return None
    return BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_compute_dtype=torch.float16,
        bnb_4bit_use_double_quant=True,
        bnb_4bit_quant_type="nf4",
    )


def _vram() -> float:
    if not torch.cuda.is_available():
        return 0.0
    return torch.cuda.memory_allocated() / 1024 ** 2


def _get_model():
    with _lock:
        if "qwen" not in _cache:
            logger.info("[load] Qwen2-VL-2B — device=%s", DEVICE)
            t     = time.time()
            quant = _build_quant_config()

            kwargs: dict = {
                "pretrained_model_name_or_path": MODEL_ID,
            }
            if quant:
                kwargs["quantization_config"] = quant
                kwargs["device_map"]          = {"": 0}
            else:
                kwargs["torch_dtype"] = torch.float32
                kwargs["device_map"]  = "cpu"

            _cache["qwen"] = {
                "model":     AutoModelForImageTextToText.from_pretrained(**kwargs).eval(),
                "processor": AutoProcessor.from_pretrained(MODEL_ID),
            }
            logger.info(
                "[load] Qwen ready — %.1fs  VRAM=%.0f MiB",
                time.time() - t, _vram(),
            )
        else:
            logger.debug("[cache] Qwen ready — VRAM=%.0f MiB", _vram())

    return _cache["qwen"]["model"], _cache["qwen"]["processor"]


def warmup() -> None:
    _get_model()


_CORRECTION_PROMPT = (
    "Fix ONLY character-level OCR errors in the prescription text below.\n"
    "Use the image to verify what is actually written.\n\n"
    "PADDLE OCR TEXT:\n"
    "{paddle_text}\n\n"
    "STRICT RULES:\n"
    "1. Copy each line, correcting only misread characters\n"
    "2. Fix examples: '20g mg'→'200mg', '6s kg'→'65 kg', '#bD'→'BID', 'sml'→'mL'\n"
    "3. Do NOT add any new lines, fields, or information\n"
    "4. Do NOT add medical descriptions or notes\n"
    "5. Do NOT translate — keep original language\n"
    "6. Do NOT split one medicine into multiple lines\n"
    "7. Output corrected text only. Nothing else."
)


def correct_ocr(image: Image.Image, paddle_text: str) -> str:
    if not paddle_text.strip():
        return ""

    model, processor = _get_model()

    w, h = image.size
    if max(w, h) > CORRECTION_MAX_SIZE:
        r   = CORRECTION_MAX_SIZE / max(w, h)
        img = image.resize((int(w * r), int(h * r)), Image.LANCZOS)
    else:
        img = image

    messages = [{"role": "user", "content": [
        {"type": "image", "image": img},
        {"type": "text",  "text": _CORRECTION_PROMPT.format(paddle_text=paddle_text)},
    ]}]

    inputs = processor.apply_chat_template(
        messages,
        add_generation_prompt=True,
        tokenize=True,
        return_dict=True,
        return_tensors="pt",
    ).to(DEVICE)

    t1 = time.time()
    try:
        with torch.inference_mode():
            out_ids = model.generate(
                **inputs,
                max_new_tokens=MAX_NEW_TOKENS,
                do_sample=False,
                temperature=None,
                top_p=None,
                repetition_penalty=1.05,
                no_repeat_ngram_size=2,
            )
    except torch.cuda.OutOfMemoryError:
        logger.error("VRAM OOM during Qwen correction — clearing cache and re-raising")
        torch.cuda.empty_cache()
        raise

    input_len = inputs["input_ids"].shape[-1]
    text = processor.decode(
        out_ids[0][input_len:-1],
        skip_special_tokens=True,
    ).strip()

    logger.info(
        "Qwen correction done — %.1fs  in=%d  out=%d chars",
        time.time() - t1, len(paddle_text), len(text),
    )

    del inputs, out_ids

    return text if text else paddle_text