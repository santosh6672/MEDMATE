import os
import base64
import asyncio
import logging
from groq import Groq

logger = logging.getLogger(__name__)

_client = None

def _get_client() -> Groq:
    global _client
    if _client is None:
        api_key = os.environ.get("GROQ_API_KEY")
        if not api_key:
            raise RuntimeError("GROQ_API_KEY environment variable not set")
        _client = Groq(api_key=api_key)
    return _client


def _image_to_base64(image_bytes: bytes) -> str:
    return base64.b64encode(image_bytes).decode("utf-8")


_VISION_PROMPT = """You are reading a handwritten or printed medical prescription image.
Extract all text exactly as written, line by line.
Fix only obvious character errors (0 vs O, 1 vs l, 5 vs S).
Pay special attention to:
  - Medicine names (may be handwritten brand names)
  - Dosages (numbers + units like mg, ml)
  - Frequency abbreviations (OD, BD, TDS, QID, HS, SOS)
  - Doctor name and patient name if visible
Do NOT add any information not visible in the image.
Do NOT translate or interpret — output raw prescription text only."""

# Groq image size limit ~20MB encoded, safe limit for base64 input
_MAX_IMAGE_BYTES = 15 * 1024 * 1024  # 15MB


def _call_groq_vision(image_bytes: bytes) -> str:
    """Synchronous Groq call — run via executor to avoid blocking event loop."""
    base64_image = _image_to_base64(image_bytes)
    response = _get_client().chat.completions.create(
        model="meta-llama/llama-4-scout-17b-16e-instruct",
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{base64_image}",
                        },
                    },
                    {
                        "type": "text",
                        "text": _VISION_PROMPT,
                    },
                ],
            }
        ],
        temperature=0.1,
        max_tokens=1024,
    )
    return response.choices[0].message.content.strip()


async def groq_vision_read(image_bytes: bytes) -> str:
    # input validation
    if not image_bytes:
        logger.warning("groq_vision_read: empty image bytes received")
        return ""

    if len(image_bytes) > _MAX_IMAGE_BYTES:
        logger.warning(
            f"groq_vision_read: image too large ({len(image_bytes)} bytes), skipping"
        )
        return ""

    for attempt in range(3):
        try:
            # run sync SDK in thread pool — does not block event loop
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(None, _call_groq_vision, image_bytes)

            logger.info(f"Groq Vision extracted {len(result.split())} words")
            return result

        except Exception as e:
            logger.warning(f"Groq Vision attempt {attempt + 1} failed: {type(e).__name__}: {e}")
            if attempt < 2:
                await asyncio.sleep(2 ** attempt)  # 1s, 2s backoff

    logger.error("Groq Vision failed after 3 attempts")
    return ""
