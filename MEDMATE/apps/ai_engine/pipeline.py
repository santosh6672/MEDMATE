"""
pipeline.py
────────────
Thin orchestrator. All logic lives in the four modules below.

Flow:
  image_path
    → utils/image_preprocessor.py         preprocess()
    → ocr/paddle_ocr.py                   extract_text()
    → vision_reasoner/qwen2.py            correct_ocr()
    → medicine_reasoner/qwen_instruct.py  MedicineReasoner.reason()
    → dict  { medicines: [...], patient_name, date, … }

Both local GPU models (Paddle + Qwen) are cached inside their own modules
after first load — no reload between Celery tasks on the same worker.

Fixes vs original:
  - _pipeline_event.set() moved INSIDE _pipeline_lock to guarantee
    visibility of _pipeline_instance before any waiting thread resumes.
  - _loading_started flag added so start_pipeline_preload() can never
    spawn two background threads even under a race between callers.
  - process() propagates exceptions instead of swallowing them;
    tasks.py decides how to handle failures.
  - Removed gc.collect() — no tight inner loop here.
  - logging instead of print()
"""

import logging
import threading
import time

import torch

from apps.ai_engine.utils.image_preprocessor import preprocess
from apps.ai_engine.ocr.paddle_ocr import (
    extract_text as paddle_extract,
    warmup       as paddle_warmup,
)
from apps.ai_engine.vision_reasoner.qwen2 import (
    correct_ocr as qwen_correct,
    warmup      as qwen_warmup,
)
from apps.ai_engine.medicine_reasoner.qwen_instruct import MedicineReasoner

logger = logging.getLogger(__name__)


class MedMatePipeline:
    """
    Orchestrates the full prescription → structured-JSON pipeline.
    Same .process(image_path) → dict interface consumed by tasks.py.
    """

    def __init__(self) -> None:
        self.reasoner = MedicineReasoner()

    def process(self, image_path: str) -> dict:
        """
        Run the full pipeline for one prescription image.

        Args:
            image_path: Absolute filesystem path to the uploaded image.

        Returns:
            dict with 'medicines' list and patient metadata.

        Raises:
            Any exception from the sub-modules — callers (tasks.py) handle
            failures and set the prescription status accordingly.
        """
        t_total = time.time()

        # ── 1. Preprocess ──────────────────────────────────────────────────
        logger.info("Step 1/4 — preprocessing image …")
        image = preprocess(image_path)

        # ── 2. PaddleOCR-VL ───────────────────────────────────────────────
        logger.info("Step 2/4 — PaddleOCR-VL extraction …")
        paddle_text = paddle_extract(image)

        # ── 3. Qwen2-VL correction ─────────────────────────────────────────
        logger.info("Step 3/4 — Qwen2-VL OCR correction …")
        corrected_text = qwen_correct(image, paddle_text)

        # Release PIL image — no longer needed downstream
        del image

        # ── 4. LLM medicine extraction ─────────────────────────────────────
        logger.info("Step 4/4 — LLM medicine extraction …")
        result = self.reasoner.reason(corrected_text)

        logger.info("Pipeline complete in %.1fs", time.time() - t_total)
        return result


# ── Background preload singleton ──────────────────────────────────────────────

_pipeline_instance: MedMatePipeline | None = None
_pipeline_lock                              = threading.Lock()
_pipeline_event                             = threading.Event()
_loading_started: bool                      = False   # guarded by _pipeline_lock


def _load_in_background() -> None:
    global _pipeline_instance
    t = time.time()
    logger.info("[Background] Loading AI pipeline …")
    try:
        instance = MedMatePipeline()

        # Load Paddle first, check VRAM, then load Qwen
        logger.info("[Background] Warming up PaddleOCR …")
        paddle_warmup()

        free_vram = (
            torch.cuda.get_device_properties(0).total_memory
            - torch.cuda.memory_allocated(0)
        ) / 1024 ** 2
        logger.info("[Background] VRAM free after Paddle: %.0f MiB", free_vram)

        if free_vram < 1400:
            logger.warning(
                "[Background] Only %.0f MiB free — Qwen2-VL may fail. "
                "Close other GPU applications and restart the worker.",
                free_vram,
            )

        logger.info("[Background] Warming up Qwen2-VL …")
        qwen_warmup()

        # Assign instance and fire event INSIDE the lock
        with _pipeline_lock:
            _pipeline_instance = instance
            _pipeline_event.set()

        logger.info("[Background] Pipeline ready in %.1fs", time.time() - t)

    except Exception:
        logger.exception("[Background] Pipeline load failed")
        with _pipeline_lock:
            _pipeline_event.set()   # unblock get_pipeline() so it can raise


def start_pipeline_preload() -> None:
    """
    Start the background model-loading thread exactly once.
    Safe to call from multiple Celery worker processes or threads.
    """
    global _loading_started
    with _pipeline_lock:
        if _loading_started:
            return
        _loading_started = True
    threading.Thread(target=_load_in_background, daemon=True).start()


def get_pipeline() -> MedMatePipeline:
    """
    Return the loaded pipeline, blocking until it is ready.

    Raises:
        RuntimeError: If background loading failed.
    """
    # Fast path — already loaded (read is safe: _pipeline_instance is set once)
    if _pipeline_instance is not None:
        return _pipeline_instance

    start_pipeline_preload()
    logger.info("Waiting for pipeline to finish loading …")
    _pipeline_event.wait()

    if _pipeline_instance is None:
        raise RuntimeError(
            "AI pipeline failed to load. Check Celery worker logs for details."
        )
    return _pipeline_instance