import os
import uuid
import asyncio
import logging
import boto3
from fastapi import APIRouter, UploadFile, File, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker, selectinload
from sqlalchemy import select

from apps.auth.dependencies import get_current_user, AuthUser
from apps.prescriptions.models import Prescription, Medicine
from apps.prescriptions.schemas import PrescriptionOut, PrescriptionListItem, UploadResponse
from apps.ai_engine.pipeline import process

logger = logging.getLogger(__name__)

# ── Database ──────────────────────────────────────────────────────────────────

def _get_db_url() -> str:
    url = os.environ.get("SUPABASE_DB_URL")
    if not url:
        raise RuntimeError("SUPABASE_DB_URL environment variable not set")
    return url

engine = create_async_engine(
    _get_db_url(),
    echo=False,
    pool_size=5,
    max_overflow=10,
    pool_timeout=30,
    pool_recycle=1800,
)

AsyncSessionLocal = sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

# ── S3 (persistent client) ────────────────────────────────────────────────────

_s3_client = None

def _get_s3():
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client(
            "s3",
            region_name=os.environ.get("AWS_REGION", "ap-south-2"),
        )
    return _s3_client


def _upload_to_s3(key: str, image_bytes: bytes) -> None:
    """Synchronous S3 upload — must be called via executor."""
    _get_s3().put_object(
        Bucket=os.environ["S3_BUCKET"],
        Key=key,
        Body=image_bytes,
        ContentType="image/jpeg",
    )


# ── Router ────────────────────────────────────────────────────────────────────

router = APIRouter(prefix="/api/prescriptions", tags=["prescriptions"])

# ── Helpers ───────────────────────────────────────────────────────────────────

def _update_prescription(prescription: Prescription, result: dict) -> None:
    """Updates prescription fields from pipeline result — no duplication."""
    prescription.patient_name = result.get("patient_name", "Not specified")
    prescription.doctor       = result.get("doctor",       "Not specified")
    prescription.diagnosis    = result.get("diagnosis",    "Not specified")
    prescription.confidence   = result.get("confidence",   "low")


def _build_medicine(prescription_id: int, med: dict) -> Medicine:
    return Medicine(
        prescription_id  = prescription_id,
        name             = med.get("name",             "Not specified"),
        generic_name     = med.get("generic_name",     "Not specified"),
        dosage           = med.get("dosage",           "Not specified"),
        frequency        = med.get("frequency",        "Not specified"),
        duration         = med.get("duration",         "Not specified"),
        instructions     = med.get("instructions",     "Not specified"),
        medicine_type    = med.get("type",             "Not specified"),
        dose_flag        = med.get("dose_flag",        "VERIFY"),
        dose_flag_reason = med.get("dose_flag_reason", "Not specified"),
    )


# ── POST /api/prescriptions/ ──────────────────────────────────────────────────

@router.post("/", response_model=UploadResponse)
async def upload_prescription(
    image: UploadFile = File(...),
    user: AuthUser = Depends(get_current_user),
):
    # 1 — read + validate
    image_bytes = await image.read()

    if len(image_bytes) > 20 * 1024 * 1024:
        raise HTTPException(400, "Image too large — maximum 20MB")

    content_type = image.content_type or ""
    if not content_type.startswith("image/"):
        raise HTTPException(400, "Only image files accepted")

    # 2 — upload to S3 (run sync boto3 in thread pool)
    key = f"prescriptions/{user.id}/{uuid.uuid4()}.jpg"
    try:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, _upload_to_s3, key, image_bytes)
        logger.info(f"S3 upload success: {key}")
    except Exception as e:
        logger.error(f"S3 upload failed: {type(e).__name__}: {e}")
        raise HTTPException(500, "Image storage failed — please try again")

    # 3 — create DB record + run pipeline + save results
    async with AsyncSessionLocal() as db:

        # create initial record
        prescription = Prescription(
            user_id   = user.id,
            image_key = key,
            status    = "processing",
        )
        db.add(prescription)
        await db.commit()
        await db.refresh(prescription)

        # run AI pipeline
        try:
            result = await process(image_bytes)
        except Exception as e:
            logger.error(f"Pipeline failed: {type(e).__name__}: {e}")
            prescription.status = "failed"
            await db.commit()
            raise HTTPException(500, "AI processing failed — please try again")

        # save results based on pipeline status
        status = result.get("status")

        if status == "uncertain":
            prescription.status = "uncertain"

        elif status == "processed_empty":
            prescription.status = "processed_empty"
            _update_prescription(prescription, result)

        else:
            prescription.status = "processed"
            _update_prescription(prescription, result)
            for med in result.get("medicines", []):
                db.add(_build_medicine(prescription.id, med))

        await db.commit()
        await db.refresh(prescription)

        logger.info(f"Prescription {prescription.id} saved — status: {prescription.status}")

        return UploadResponse(
            id     = prescription.id,
            status = prescription.status,
            result = result,
        )


# ── GET /api/prescriptions/ ──────────────────────────────────────────────────

@router.get("/", response_model=list[PrescriptionListItem])
async def list_prescriptions(
    user : AuthUser = Depends(get_current_user),
    limit: int      = Query(default=20, ge=1, le=100),
    offset: int     = Query(default=0,  ge=0),
):
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Prescription)
            .where(Prescription.user_id == user.id)
            .order_by(Prescription.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        return result.scalars().all()


# ── GET /api/prescriptions/{id} ──────────────────────────────────────────────

@router.get("/{prescription_id}", response_model=PrescriptionOut)
async def get_prescription(
    prescription_id: int,
    user: AuthUser = Depends(get_current_user),
):
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Prescription)
            .where(
                Prescription.id      == prescription_id,
                Prescription.user_id == user.id,
            )
            .options(selectinload(Prescription.medicines))  # eager load — no N+1
        )
        prescription = result.scalar_one_or_none()

        if not prescription:
            raise HTTPException(404, "Prescription not found")

        return prescription


# ── DELETE /api/prescriptions/{id} ───────────────────────────────────────────

@router.delete("/{prescription_id}")
async def delete_prescription(
    prescription_id: int,
    user: AuthUser = Depends(get_current_user),
):
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Prescription).where(
                Prescription.id      == prescription_id,
                Prescription.user_id == user.id,
            )
        )
        prescription = result.scalar_one_or_none()

        if not prescription:
            raise HTTPException(404, "Prescription not found")

        await db.delete(prescription)
        await db.commit()

        logger.info(f"Prescription {prescription_id} deleted by {user.email}")
        return {"message": "Prescription deleted successfully"}