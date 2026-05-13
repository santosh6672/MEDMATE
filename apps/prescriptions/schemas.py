from pydantic import BaseModel, ConfigDict
from datetime import datetime


# ── Medicine ──────────────────────────────────────────────────────────────────

class MedicineOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id               : int
    name             : str
    generic_name     : str
    dosage           : str
    frequency        : str
    duration         : str
    instructions     : str
    medicine_type    : str                              # matches renamed column
    dose_flag        : str
    dose_flag_reason : str


# ── Prescription (full detail) ────────────────────────────────────────────────

class PrescriptionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id           : int
    status       : str
    patient_name : str
    doctor       : str
    diagnosis    : str
    confidence   : str
    created_at   : datetime
    medicines    : list[MedicineOut] = []
    # image_key intentionally excluded — internal S3 key not exposed to clients


# ── Prescription (list view — lightweight) ────────────────────────────────────

class PrescriptionListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id           : int
    status       : str
    patient_name : str
    doctor       : str
    diagnosis    : str
    confidence   : str
    created_at   : datetime


# ── Upload response ───────────────────────────────────────────────────────────

class UploadResponse(BaseModel):
    id     : int
    status : str
    result : dict