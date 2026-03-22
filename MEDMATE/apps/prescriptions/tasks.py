"""
tasks.py
"""

import logging
import os
import time
from pathlib import Path

from celery import shared_task
from django.apps import apps
from django.conf import settings
from django.db import OperationalError, transaction

from apps.ai_engine.medicine_reasoner.qwen_instruct import AIExtractionError
from apps.ai_engine.utils.sanitise import safe_str

logger = logging.getLogger(__name__)


@shared_task(
    bind=True,
    autoretry_for=(RuntimeError, AIExtractionError),
    retry_backoff=5,
    retry_backoff_max=120,
    retry_jitter=True,
    retry_kwargs={"max_retries": 3},
)
def process_prescription_ai(self, prescription_id: int):
    logger.info(
        "TASK START  prescription_id=%d  task_id=%s  attempt=%d",
        prescription_id,
        self.request.id,
        self.request.retries + 1,
    )

    from apps.ai_engine.pipeline import get_pipeline

    Prescription = apps.get_model("prescriptions", "Prescription")
    Medicine     = apps.get_model("prescriptions", "Medicine")

    prescription = None
    t_start      = time.time()

    try:
        # ── Pessimistic lock — skip if already claimed by another worker ───
        try:
            with transaction.atomic():
                prescription = (
                    Prescription.objects
                    .select_for_update(nowait=True)
                    .get(id=prescription_id, status="pending")
                )
                prescription.status = "processing"
                prescription.save(update_fields=["status"])
        except OperationalError:
            logger.warning(
                "Prescription %d locked by another worker — skipping",
                prescription_id,
            )
            return {"status": "skipped", "reason": "locked"}

        logger.info("Prescription %d locked — status → processing", prescription_id)

        # ── Path validation ────────────────────────────────────────────────
        image_path = prescription.image.path
        media_root = Path(settings.MEDIA_ROOT).resolve()
        resolved   = Path(image_path).resolve()

        if not str(resolved).startswith(str(media_root)):
            raise ValueError(f"Path traversal detected: {image_path}")

        if not resolved.exists():
            raise FileNotFoundError(f"Image not found: {image_path}")

        logger.info("Image verified: %s", image_path)

        # ── AI pipeline ────────────────────────────────────────────────────
        t        = time.time()
        pipeline = get_pipeline()
        logger.info("Pipeline acquired — %.1fs wait", time.time() - t)

        t      = time.time()
        result = pipeline.process(image_path)
        logger.info("Pipeline finished — %.1fs", time.time() - t)

        medicines = [m for m in result.get("medicines", []) if isinstance(m, dict)]
        logger.info("%d medicine(s) detected", len(medicines))

        # ── Atomic bulk persist ────────────────────────────────────────────
        with transaction.atomic():
            Medicine.objects.filter(prescription=prescription).delete()
            Medicine.objects.bulk_create([
                Medicine(
                    prescription     = prescription,
                    name             = safe_str(med.get("name")),
                    generic_name     = safe_str(med.get("generic_name")),
                    dosage           = safe_str(med.get("dosage")),
                    frequency        = safe_str(med.get("frequency")),
                    duration         = safe_str(med.get("duration")),
                    instructions     = safe_str(med.get("instructions")),
                    type             = safe_str(med.get("type")),
                    dose_flag        = safe_str(med.get("dose_flag")),
                    dose_flag_reason = safe_str(med.get("dose_flag_reason")),
                )
                for med in medicines
            ], batch_size=100)

        # ── Final status ───────────────────────────────────────────────────
        prescription.doctor    = safe_str(result.get("doctor"))
        prescription.diagnosis = safe_str(result.get("diagnosis"))
        prescription.status    = "processed" if medicines else "processed_empty"
        prescription.save(update_fields=["status", "doctor", "diagnosis"])

        elapsed = time.time() - t_start
        logger.info(
            "TASK COMPLETE  prescription_id=%d  medicines=%d  elapsed=%.1fs",
            prescription_id, len(medicines), elapsed,
        )
        return {
            "status":          "success",
            "medicines_saved": len(medicines),
            "elapsed_seconds": round(elapsed, 1),
        }

    except Prescription.DoesNotExist:
        logger.warning(
            "Prescription %d not found or not pending — skipping",
            prescription_id,
        )
        return {"status": "skipped", "reason": "not_found_or_already_processed"}

    except (FileNotFoundError, ValueError) as exc:
        logger.error("Permanent failure for prescription %d: %s", prescription_id, exc)
        if prescription is not None:
            prescription.status = "failed"
            prescription.save(update_fields=["status"])
        return {"status": "failed", "reason": str(exc)}

    except Exception:
        logger.exception("TASK FAILED  prescription_id=%d", prescription_id)
        if prescription is not None:
            try:
                prescription.status = "failed"
                prescription.save(update_fields=["status"])
            except Exception:
                logger.exception(
                    "Could not update status to failed for prescription %d",
                    prescription_id,
                )
        raise