import io
import asyncio
import logging
from PIL import Image, ImageOps

from apps.ai_engine.ocr.groq_vision import groq_vision_read
from apps.ai_engine.reasoner.groq_instruct import groq_extract_medicines

logger = logging.getLogger(__name__)

# ── Image preprocessing ───────────────────────────────────────────────────────

def _resize_image_sync(image_bytes: bytes, max_px: int = 2000) -> bytes:
    """
    CPU-bound — called via executor, never directly in async context.
    - EXIF auto-rotate (fixes upside-down Android photos)
    - Resize to max 2000px longest side
    - Convert to RGB JPEG
    """
    img = Image.open(io.BytesIO(image_bytes))
    img = ImageOps.exif_transpose(img)
    img.thumbnail((max_px, max_px))
    if img.mode != "RGB":
        img = img.convert("RGB")
    out = io.BytesIO()
    img.save(out, format="JPEG", quality=85)
    return out.getvalue()


async def _preprocess(image_bytes: bytes) -> bytes:
    """Runs CPU-bound Pillow resize in thread pool."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _resize_image_sync, image_bytes)


# ── Pipeline ──────────────────────────────────────────────────────────────────

async def process(image_bytes: bytes) -> dict:
    """
    Full pipeline:
      Step 1 — preprocess image (EXIF rotate + resize) [thread pool]
      Step 2 — extract text via Groq Vision / Llama 4 Scout [thread pool]
      Step 3 — extract medicines via Groq LLM / Llama 3.3 70B [thread pool]
    """

    # Step 1 — preprocess (CPU-bound, run in executor)
    logger.info("Pipeline Step 1/3 — preprocessing image")
    try:
        image = await _preprocess(image_bytes)
    except Exception as e:
        logger.error(f"Image preprocessing failed: {type(e).__name__}: {e}")
        return {
            "status" : "uncertain",
            "message": "Could not read image — please retake photo",
        }

    # Step 2 — Groq Vision OCR
    logger.info("Pipeline Step 2/3 — running Groq Vision OCR")
    ocr_text = await groq_vision_read(image)

    if not ocr_text.strip():
        logger.warning("Vision returned empty — image too unclear")
        return {
            "status" : "uncertain",
            "message": "Image too unclear — please retake photo in better lighting",
        }

    logger.info(f"Vision text preview: {ocr_text[:200]}")

    # Step 3 — extract medicines
    logger.info("Pipeline Step 3/3 — extracting medicines via Groq LLM")
    result = await groq_extract_medicines(ocr_text)

    # attach pipeline status
    if not result.get("medicines"):
        result["status"]  = "processed_empty"
        result["message"] = "No medicines found — prescription may be unclear"
    else:
        result["status"] = "processed"

    return result