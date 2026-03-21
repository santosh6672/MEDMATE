"""
tasks.py
─────────
Celery task: fetch prescription → run AI pipeline → save medicines to DB.

Fixes vs original:
  - autoretry_for narrowed to transient errors only (OSError, RuntimeError,
    AIExtractionError). Permanent errors (FileNotFoundError,
    Prescription.DoesNotExist) set status="failed" and do NOT retry.
  - select_for_update(status="pending") prevents duplicate task processing.
  - _s() helper removed — now imported as safe_str from utils.sanitise.
  - _s() was being redefined on every loop iteration; that is gone entirely.
  - "raise e" replaced with bare "raise" to preserve full traceback.
  - logging instead of print().
  - processed_empty status documented; added status guard to skip non-pending.
"""

import logging
import os
import time

from celery import shared_task
from django.apps import apps
from django.db import transaction

from apps.ai_engine.medicine_reasoner.qwen_instruct import AIExtractionError
from apps.ai_engine.utils.sanitise import safe_str

logger = logging.getLogger(__name__)

# Statuses that represent a terminal state — do not re-process
_TERMINAL_STATUSES = {"processing", "processed", "processed_empty", "failed"}


@shared_task(
    bind=True,
    # Only retry on errors that are genuinely transient.
    # FileNotFoundError and ObjectDoesNotExist are permanent — no point retrying.
    autoretry_for=(OSError, RuntimeError, AIExtractionError),
    retry_backoff=5,
    retry_kwargs={"max_retries": 3},
)
def process_prescription_ai(self, prescription_id: int):
    """
    AI processing task for a single prescription.

    Steps:
        1. Fetch prescription with a pessimistic lock (prevents duplicate runs).
        2. Verify the image file exists on disk.
        3. Run the AI pipeline (preprocess → OCR → correct → extract).
        4. Atomically replace medicine rows with the new extraction result.
        5. Set final status: 'processed' (medicines found) or
           'processed_empty' (blank / illegible prescription).

    On unrecoverable failure, status is set to 'failed'.
    """
    logger.info(
        "TASK START  prescription_id=%d  task_id=%s",
        prescription_id,
        self.request.id,
    )

    from apps.ai_engine.pipeline import get_pipeline

    Prescription = apps.get_model("prescriptions", "Prescription")
    Medicine     = apps.get_model("prescriptions", "Medicine")

    prescription = None
    t_start      = time.time()

    try:
        # ── Fetch with pessimistic lock ────────────────────────────────────
        # select_for_update() prevents a duplicate Celery message from running
        # the pipeline twice on the same row.
        # If status is already non-pending (e.g. a duplicate task), this
        # raises DoesNotExist and exits cleanly without retrying.
        with transaction.atomic():
            prescription = (
                Prescription.objects
                .select_for_update()
                .get(id=prescription_id, status="pending")
            )
            prescription.status = "processing"
            prescription.save(update_fields=["status"])

        logger.info("Prescription %d locked, status → processing", prescription_id)

        # ── Verify image exists ────────────────────────────────────────────
        image_path = prescription.image.path
        logger.info("Image path: %s", image_path)
        if not os.path.exists(image_path):
            # Permanent failure — mark failed immediately, do not retry
            raise FileNotFoundError(f"Image file not found: {image_path}")

        # ── Run AI pipeline ────────────────────────────────────────────────
        logger.info("Acquiring AI pipeline …")
        t = time.time()
        pipeline = get_pipeline()
        logger.info("Pipeline ready (%.1fs wait)", time.time() - t)

        t = time.time()
        logger.info("Running AI pipeline …")
        result    = pipeline.process(image_path)
        logger.info("Pipeline finished in %.1fs", time.time() - t)

        medicines = result.get("medicines", [])
        logger.info("%d medicine(s) detected", len(medicines))

        # ── Persist medicines atomically ───────────────────────────────────
        with transaction.atomic():
            # Delete any previous medicines (idempotent re-run support)
            Medicine.objects.filter(prescription=prescription).delete()

            for med in medicines:
                # safe_str is the shared sentinel from utils/sanitise.py.
                # qwen_instruct already sanitised these, but this is the
                # final DB-write guard.
                name      = safe_str(med.get("name"))
                dosage    = safe_str(med.get("dosage"))
                frequency = safe_str(med.get("frequency"))

                Medicine.objects.create(
                    prescription=prescription,
                    name=name,
                    dosage=dosage,
                    frequency=frequency,
                )
                logger.debug("Saved medicine: %s | %s | %s", name, dosage, frequency)

        # ── Update final status ────────────────────────────────────────────
        # 'processed_empty' means the pipeline ran successfully but the image
        # contained no readable prescription data (blank page, wrong document,
        # illegible handwriting). This is a valid terminal state — not a failure.
        prescription.status = "processed" if medicines else "processed_empty"
        prescription.save(update_fields=["status"])

        elapsed = time.time() - t_start
        logger.info(
            "TASK COMPLETE  prescription_id=%d  medicines=%d  elapsed=%.1fs",
            prescription_id,
            len(medicines),
            elapsed,
        )
        return {
            "status":          "success",
            "medicines_saved": len(medicines),
            "elapsed_seconds": round(elapsed, 1),
        }

    except Prescription.DoesNotExist:
        # Either the row doesn't exist or it's already in a non-pending state.
        # Both are permanent — log and exit without retrying.
        logger.warning(
            "Prescription %d not found or already processed — skipping.",
            prescription_id,
        )
        return {"status": "skipped", "reason": "not_found_or_already_processed"}

    except FileNotFoundError:
        # Permanent failure — no point retrying; file will not appear.
        logger.error("Image file missing for prescription %d", prescription_id)
        if prescription:
            prescription.status = "failed"
            prescription.save(update_fields=["status"])
        return {"status": "failed", "reason": "image_not_found"}

    except Exception:
        # Transient failure — let Celery's autoretry_for handle the retry.
        # Bare `raise` preserves the original traceback (unlike `raise e`).
        logger.exception("TASK FAILED for prescription %d", prescription_id)
        if prescription:
            prescription.status = "failed"
            prescription.save(update_fields=["status"])
        raise