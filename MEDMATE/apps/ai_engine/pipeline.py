"""
pipeline.py
───────────
Fix: CRAFT + Qwen2-VL "parallel" was not actually parallel (54s)

Root cause:
    CRAFT and Qwen2-VL both use PyTorch on cuda:0.
    CUDA only executes ONE PyTorch kernel at a time per device.
    ThreadPoolExecutor created threads but they queued on the GPU:
        Thread 1 (CRAFT):    waiting for GPU  → 27s
        Thread 2 (Qwen2-VL): waiting for GPU  → 27s
        Total wall time:                        54s  (same as sequential)

Correct execution order for single GPU:
    ┌─────────────────────────────────────────────────────┐
    │ Step 1: Preprocess        (CPU)          ~0.4s      │
    │ Step 2: CRAFT             (PyTorch GPU)  ~5s        │
    │ Step 3: ┌─ PaddleOCR ─── (Paddle GPU)   ~6s ─┐    │
    │         └─ Qwen2-VL ──── (PyTorch GPU)  ~12s ─┤    │
    │                                          max=12s    │
    │ Step 4: LLM reasoning     (API)          ~2s        │
    │                                                     │
    │ Total inference: ~5 + 12 + 2 = ~19s                 │
    └─────────────────────────────────────────────────────┘

Why PaddleOCR + Qwen2-VL CAN overlap:
    PaddleOCR uses the Paddle inference engine (libpaddle_inference.so)
    with its own CUDA context, separate from PyTorch's CUDA context.
    These two CUDA contexts can execute simultaneously on the same GPU
    because the GPU hardware can multiplex compute from different contexts.

    CRAFT + Qwen2-VL CANNOT overlap because both use the same
    PyTorch CUDA context — they share the same execution queue.
"""

import os
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

from .craft.detect_boxes import CraftDetector
from .ocr.paddle_ocr import PaddleRecognizer
from .vision_reasoner.qwen2 import QwenReasoner
from .medicine_reasoner.qwen_instruct import MedicineReasoner
from apps.ai_engine.utils.image_preprocessor import preprocess, save_temp


class MedMatePipeline:

    def __init__(self):
        print("\n🚀 Loading AI Models...")
        self.craft             = CraftDetector(cuda=True)
        self.paddle            = PaddleRecognizer()
        self.qwen_vision       = QwenReasoner()
        self.medicine_reasoner = MedicineReasoner()
        print("✅ All models loaded\n")

    def process(self, image_path: str) -> dict:
        """
        Full prescription processing pipeline.

        Execution order:
          1. Preprocess (CPU)
          2. CRAFT (PyTorch GPU) — must finish before PaddleOCR needs boxes
          3. PARALLEL:
               PaddleOCR (Paddle CUDA context) on CRAFT boxes
             + Qwen2-VL  (PyTorch CUDA context) on full image
             ← different CUDA contexts → genuine GPU overlap
          4. LLM reasoning (API, no GPU)
        """
        t_total   = time.time()
        temp_path = None

        try:
            # ── 1. Preprocess (CPU) ────────────────────────────────────────
            t = time.time()
            print("🖼️  Preprocessing image...")
            preprocessed = preprocess(image_path)
            temp_path    = save_temp(preprocessed)
            print(f"   ✅ Preprocessing done ({time.time()-t:.1f}s)")

            # ── 2. CRAFT (PyTorch GPU) — sequential, must finish first ─────
            t = time.time()
            print("🔍 CRAFT detecting boxes...")
            boxes = self._run_craft(temp_path)
            print(f"   ✅ CRAFT: {len(boxes)} boxes ({time.time()-t:.1f}s)")

            # ── 3. PaddleOCR + Qwen2-VL in PARALLEL ───────────────────────
            # PaddleOCR: Paddle CUDA context (needs boxes from step 2)
            # Qwen2-VL:  PyTorch CUDA context (needs full image from step 1)
            # Different CUDA contexts → genuine GPU parallelism
            t = time.time()
            print("🔀 Running PaddleOCR + Qwen2-VL in parallel...")

            paddle_text = ""
            qwen_text   = ""

            with ThreadPoolExecutor(max_workers=2) as ex:
                fut_paddle = ex.submit(self._run_paddle, temp_path, boxes)
                fut_qwen   = ex.submit(self._run_qwen,   temp_path)

                for fut in as_completed([fut_paddle, fut_qwen]):
                    if fut is fut_paddle:
                        paddle_text = fut.result()
                    else:
                        qwen_text = fut.result()

            print(
                f"   ✅ PaddleOCR: {len(paddle_text)} chars | "
                f"Qwen2-VL: {len(qwen_text)} chars "
                f"({time.time()-t:.1f}s)"
            )

            # ── 4. LLM cross-validation reasoning (API) ───────────────────
            t = time.time()
            print("🧠 Running LLM reasoning...")
            result = self._run_reasoner(paddle_text, qwen_text)
            print(f"   ✅ Reasoning done ({time.time()-t:.1f}s)")

            elapsed = time.time() - t_total
            print(f"\n🎉 Pipeline complete in {elapsed:.1f}s total")
            return result

        except Exception as e:
            print(f"❌ Pipeline error: {e}")
            return {"medicines": []}

        finally:
            if temp_path and os.path.exists(temp_path):
                os.remove(temp_path)

    # ── Per-step runners ───────────────────────────────────────────────────

    def _run_craft(self, image_path: str) -> list:
        try:
            return self.craft.detect(image_path)
        except Exception as e:
            print(f"⚠️  CRAFT failed: {e}")
            return []

    def _run_paddle(self, image_path: str, boxes: list) -> str:
        try:
            text, _ = self.paddle.recognize(image_path, boxes)
            return text
        except Exception as e:
            print(f"⚠️  PaddleOCR failed: {e}")
            return ""

    def _run_qwen(self, image_path: str) -> str:
        try:
            return self.qwen_vision.extract_text(image_path)
        except Exception as e:
            print(f"⚠️  Qwen2-VL failed: {e}")
            return ""

    def _run_reasoner(self, paddle_text: str, qwen_text: str) -> dict:
        try:
            return self.medicine_reasoner.reason(paddle_text, qwen_text)
        except Exception as e:
            print(f"⚠️  Reasoning failed: {e}")
            return {"medicines": []}


# ── Background preload singleton ───────────────────────────────────────────────

_pipeline_instance: MedMatePipeline | None = None
_pipeline_lock  = threading.Lock()
_pipeline_event = threading.Event()


def _load_in_background():
    global _pipeline_instance
    try:
        t = time.time()
        print("🔄 [Background] Loading AI pipeline...")
        instance = MedMatePipeline()
        with _pipeline_lock:
            _pipeline_instance = instance
        _pipeline_event.set()
        print(f"✅ [Background] Pipeline ready in {time.time()-t:.1f}s")
    except Exception as e:
        print(f"❌ [Background] Pipeline load failed: {e}")
        _pipeline_event.set()


def start_pipeline_preload():
    with _pipeline_lock:
        if _pipeline_instance is not None or _pipeline_event.is_set():
            return
    t = threading.Thread(target=_load_in_background, daemon=True)
    t.start()


def get_pipeline() -> MedMatePipeline:
    if _pipeline_instance is not None:
        return _pipeline_instance

    start_pipeline_preload()

    print("⏳ Waiting for pipeline to finish loading...")
    _pipeline_event.wait()

    if _pipeline_instance is None:
        raise RuntimeError("Pipeline failed to load. Check logs.")

    return _pipeline_instance