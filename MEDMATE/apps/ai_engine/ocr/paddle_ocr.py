"""
ocr/paddle_ocr.py
"""

import logging
import threading
import time

import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

CONFIDENCE_THRESHOLD = 0.6

_ocr      = None
_ocr_lock = threading.Lock()


def _get_ocr():
    global _ocr
    with _ocr_lock:
        if _ocr is None:
            from paddleocr import PaddleOCR
            logger.info("[load] PaddleOCR initialising")
            t    = time.time()
            _ocr = PaddleOCR(
                use_angle_cls=True,
                lang="en",
                use_gpu=False,
                show_log=False,
            )
            logger.info("[load] PaddleOCR ready — %.1fs", time.time() - t)
    return _ocr


def warmup() -> None:
    _get_ocr()


def extract_text(image: Image.Image) -> str:
    ocr = _get_ocr()
    t1  = time.time()

    try:
        result = ocr.ocr(np.array(image), cls=True)
    except Exception:
        logger.exception("PaddleOCR inference failed")
        return ""

    lines = []
    if result and result[0]:
        for line in result[0]:
            if not (line and len(line) >= 2):
                continue
            text, confidence = line[1]
            if confidence >= CONFIDENCE_THRESHOLD:
                lines.append(text.strip())
            else:
                logger.debug(
                    "Dropped low-confidence token (%.2f): %s",
                    confidence, text[:40],
                )

    extracted = "\n".join(lines)
    logger.info(
        "PaddleOCR done — %.1fs  lines=%d  chars=%d",
        time.time() - t1, len(lines), len(extracted),
    )
    return extracted