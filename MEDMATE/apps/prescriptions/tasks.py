"""
tasks.py
─────────
Added final null safety before DB save.

Even though qwen_instruct.py now sanitises medicines, tasks.py adds
a second layer of defence — converts any None values to "Not specified"
before calling Medicine.objects.create().

This means the null crash can never happen regardless of which layer
sanitises first.
"""

import os
import time
from celery import shared_task
from django.apps import apps
from django.db import transaction


@shared_task(
    bind=True,
    autoretry_for=(Exception,),
    retry_backoff=5,
    retry_kwargs={"max_retries": 3},
)
def process_prescription_ai(self, prescription_id: int):

    print("\n" + "=" * 50)
    print("🚀 CELERY TASK STARTED")
    print(f"   Prescription ID : {prescription_id}")
    print(f"   Task ID         : {self.request.id}")
    print("=" * 50 + "\n")

    from apps.ai_engine.pipeline import get_pipeline

    Prescription = apps.get_model("prescriptions", "Prescription")
    Medicine     = apps.get_model("prescriptions", "Medicine")

    prescription = None
    t_start      = time.time()

    try:
        prescription = Prescription.objects.get(id=prescription_id)
        prescription.status = "processing"
        prescription.save(update_fields=["status"])
        print("✅ Prescription fetched, status → processing")

        image_path = prescription.image.path
        print(f"📂 Image: {image_path}")

        if not os.path.exists(image_path):
            raise FileNotFoundError(f"Image not found: {image_path}")

        t = time.time()
        print("\n⏳ Getting AI pipeline...")
        pipeline = get_pipeline()
        print(f"   ✅ Pipeline ready ({time.time()-t:.1f}s wait)")

        t = time.time()
        print("\n🔍 Running AI pipeline...")
        result = pipeline.process(image_path)
        print(f"   ✅ Pipeline done ({time.time()-t:.1f}s)")
        print(f"   📊 Result: {result}")

        medicines = result.get("medicines", [])
        print(f"\n💊 Medicines detected: {len(medicines)}")

        with transaction.atomic():
            Medicine.objects.filter(prescription=prescription).delete()

            for med in medicines:
                # Final null safety — guarantees no IntegrityError
                name      = med.get("medicine")  or "Not specified"
                dosage    = med.get("dosage")    or "Not specified"
                frequency = med.get("frequency") or "Not specified"

                # Convert None explicitly (or.get() with None default doesn't help)
                if name      is None: name      = "Not specified"
                if dosage    is None: dosage    = "Not specified"
                if frequency is None: frequency = "Not specified"

                Medicine.objects.create(
                    prescription=prescription,
                    name=name,
                    dosage=dosage,
                    frequency=frequency,
                )
                print(f"   💾 Saved: {name} | {dosage} | {frequency}")

        prescription.status = "processed" if medicines else "processed_empty"
        prescription.save(update_fields=["status"])

        elapsed = time.time() - t_start
        print(f"\n🎉 TASK COMPLETE in {elapsed:.1f}s | medicines saved: {len(medicines)}")

        return {
            "status":          "success",
            "medicines_saved": len(medicines),
            "elapsed_seconds": round(elapsed, 1),
        }

    except Exception as e:
        print(f"\n❌ TASK FAILED: {e}")
        if prescription:
            prescription.status = "failed"
            prescription.save(update_fields=["status"])
        raise e