"""
prescriptions/serializers.py
"""

import logging

from rest_framework import serializers

from .models import Medicine, Prescription

logger = logging.getLogger(__name__)

MAX_IMAGE_MB    = 10
MAX_IMAGE_BYTES = MAX_IMAGE_MB * 1024 * 1024
ALLOWED_MIMES   = frozenset({"image/jpeg", "image/png", "image/webp"})


class MedicineSerializer(serializers.ModelSerializer):
    class Meta:
        model  = Medicine
        fields = [
            "id",
            "name",
            "generic_name",
            "dosage",
            "frequency",
            "duration",
            "instructions",
            "type",
            "dose_flag",
            "dose_flag_reason",
        ]


class PrescriptionSerializer(serializers.ModelSerializer):
    medicines = MedicineSerializer(many=True, read_only=True)

    class Meta:
        model  = Prescription
        fields = [
            "id",
            "image",
            "status",
            "doctor",
            "diagnosis",
            "created_at",
            "medicines",
        ]
        read_only_fields = ["status", "doctor", "diagnosis", "created_at"]

    def validate_image(self, value):
        if value.size > MAX_IMAGE_BYTES:
            raise serializers.ValidationError(
                f"Image exceeds the {MAX_IMAGE_MB} MB limit "
                f"({value.size / 1024 / 1024:.1f} MB received)."
            )

        try:
            import magic
            header = value.read(2048)
            value.seek(0)
            mime = magic.from_buffer(header, mime=True)
            if mime not in ALLOWED_MIMES:
                raise serializers.ValidationError(
                    f"Unsupported file type '{mime}'. "
                    f"Allowed: {', '.join(sorted(ALLOWED_MIMES))}."
                )
        except ImportError:
            logger.warning(
                "python-magic not installed — MIME validation skipped. "
                "Install with: pip install python-magic"
            )

        return value