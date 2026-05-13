from sqlalchemy import (
    Column, BigInteger, String, ForeignKey,
    DateTime, Text, Index
)
from sqlalchemy.orm import relationship, declarative_base
from datetime import datetime, timezone

Base = declarative_base()


def _utcnow():
    """Timezone-aware UTC now — replaces deprecated datetime.utcnow."""
    return datetime.now(timezone.utc)


class Prescription(Base):
    __tablename__ = "prescriptions"

    id           = Column(BigInteger, primary_key=True, autoincrement=True)
    user_id      = Column(String, nullable=False, index=True)   # indexed for list queries
    image_key    = Column(String, nullable=False)               # S3 object key
    status       = Column(String, default="pending")            # pending/processing/processed/processed_empty/failed/uncertain
    patient_name = Column(String, default="Not specified")
    doctor       = Column(String, default="Not specified")
    diagnosis    = Column(String, default="Not specified")
    confidence   = Column(String, default="Not specified")      # high/medium/low
    created_at   = Column(DateTime(timezone=True), default=_utcnow)
    updated_at   = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow)

    medicines = relationship(
        "Medicine",
        back_populates="prescription",
        cascade="all, delete",
        lazy="select",
    )

    def __repr__(self) -> str:
        return f"<Prescription id={self.id} user={self.user_id} status={self.status}>"


class Medicine(Base):
    __tablename__ = "medicines"

    id               = Column(BigInteger, primary_key=True, autoincrement=True)
    prescription_id  = Column(
        BigInteger,
        ForeignKey("prescriptions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,                                             # indexed for joins
    )
    name             = Column(String, default="Not specified")
    generic_name     = Column(String, default="Not specified")
    dosage           = Column(String, default="Not specified")
    frequency        = Column(String, default="Not specified")
    duration         = Column(String, default="Not specified")
    instructions     = Column(String, default="Not specified")
    medicine_type    = Column(String, default="Not specified")  # renamed from 'type'
    dose_flag        = Column(String, default="VERIFY")         # OK/LOW/HIGH/VERIFY
    dose_flag_reason = Column(Text,   default="Not specified")

    prescription = relationship("Prescription", back_populates="medicines")

    def __repr__(self) -> str:
        return f"<Medicine id={self.id} name={self.name} flag={self.dose_flag}>"