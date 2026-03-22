"""
pipeline.py
"""

import logging
import threading
import time

logger = logging.getLogger(__name__)

_LOAD_TIMEOUT = 600  # seconds


class MedMatePipeline:

    def __init__(self) -> None:
        from apps.ai_engine.medicine_reasoner.qwen_instruct import MedicineReasoner
        self.reasoner = MedicineReasoner()

    def process(self, image_path: str) -> dict:
        from apps.ai_engine.utils.image_preprocessor import preprocess
        from apps.ai_engine.ocr.paddle_ocr import extract_text as paddle_extract
        from apps.ai_engine.vision_reasoner.qwen2 import correct_ocr as qwen_correct

        t_total = time.time()

        logger.info("Step 1/4 — preprocessing image")
        image = preprocess(image_path)

        logger.info("Step 2/4 — PaddleOCR extraction")
        paddle_text = paddle_extract(image)

        logger.info("Step 3/4 — Qwen2-VL OCR correction")
        corrected_text = qwen_correct(image, paddle_text)
        del image

        logger.info("Step 4/4 — LLM medicine extraction")
        result = self.reasoner.reason(corrected_text)

        logger.info("Pipeline complete — %.1fs", time.time() - t_total)
        return result


# ── Singleton ─────────────────────────────────────────────────────────────────

_pipeline_instance: MedMatePipeline | None = None
_pipeline_error:    Exception | None       = None
_pipeline_lock      = threading.Lock()
_pipeline_event     = threading.Event()
_loading_started    = False


def _load_in_background() -> None:
    global _pipeline_instance, _pipeline_error
    t = time.time()
    logger.info("Pipeline background load started")
    try:
        from apps.ai_engine.ocr.paddle_ocr import warmup as paddle_warmup
        from apps.ai_engine.vision_reasoner.qwen2 import warmup as qwen_warmup

        instance = MedMatePipeline()

        logger.info("Loading PaddleOCR")
        paddle_warmup()
        logger.info("PaddleOCR ready")

        logger.info("Loading Qwen2-VL")
        qwen_warmup()
        logger.info("Qwen2-VL ready")

        with _pipeline_lock:
            _pipeline_instance = instance

        logger.info("Pipeline ready — %.1fs", time.time() - t)

    except Exception as exc:
        logger.exception("Pipeline background load failed")
        with _pipeline_lock:
            _pipeline_error = exc

    finally:
        _pipeline_event.set()


def start_pipeline_preload() -> None:
    global _loading_started
    with _pipeline_lock:
        if _loading_started:
            return
        _loading_started = True
    threading.Thread(target=_load_in_background, daemon=True).start()


def get_pipeline() -> MedMatePipeline:
    if _pipeline_instance is not None:
        return _pipeline_instance

    start_pipeline_preload()
    logger.info("Waiting for pipeline to load (timeout=%ds)", _LOAD_TIMEOUT)

    completed = _pipeline_event.wait(timeout=_LOAD_TIMEOUT)

    with _pipeline_lock:
        if not completed:
            raise RuntimeError(
                f"Pipeline load timed out after {_LOAD_TIMEOUT}s"
            )
        if _pipeline_error is not None:
            raise RuntimeError(
                "Pipeline failed to load"
            ) from _pipeline_error
        if _pipeline_instance is None:
            raise RuntimeError("Pipeline load completed but instance is None")

    return _pipeline_instance