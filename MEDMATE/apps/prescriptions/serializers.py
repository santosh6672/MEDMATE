"""
prescriptions/serializers.py

Fixes vs original:
  - validate_image() added: enforces file size limit and MIME-type whitelist
    using python-magic (install: pip install python-magic).
    Falls back gracefully if python-magic is not installed (logs a warning).
  - MedicineSerializer exposes the full set of AI-extracted fields so the
    front-end receives dose flags, generic names, etc.
"""

import logging

from rest_framework import serializers

from .models import Prescription, Medicine

logger = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────
MAX_IMAGE_SIZE_MB  = 10
MAX_IMAGE_BYTES    = MAX_IMAGE_SIZE_MB * 1024 * 1024
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}


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
            "created_at",
            "medicines",
        ]
        read_only_fields = ["status", "created_at"]

    def validate_image(self, value):
        """
        Enforce file size and MIME-type limits.

        Requires python-magic:  pip install python-magic
        On Windows:             pip install python-magic-bin
        """
        # ── Size check ────────────────────────────────────────────────────
        if value.size > MAX_IMAGE_BYTES:
            raise serializers.ValidationError(
                f"Image too large. Maximum allowed size is {MAX_IMAGE_SIZE_MB} MB "
                f"(received {value.size / 1024 / 1024:.1f} MB)."
            )

        # ── MIME-type check ───────────────────────────────────────────────
        try:
            import magic

            header = value.read(2048)
            value.seek(0)
            mime = magic.from_buffer(header, mime=True)

            if mime not in ALLOWED_MIME_TYPES:
                raise serializers.ValidationError(
                    f"Unsupported file type '{mime}'. "
                    f"Allowed types: {', '.join(sorted(ALLOWED_MIME_TYPES))}."
                )

        except ImportError:
            # python-magic not installed — log a warning but don't block upload.
            # Install the package in production for full security.
            logger.warning(
                "python-magic not installed — MIME-type validation skipped. "
                "Run: pip install python-magic"
            )

        return value