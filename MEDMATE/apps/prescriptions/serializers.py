from rest_framework import serializers
from .models import Prescription, Medicine


class MedicineSerializer(serializers.ModelSerializer):

    class Meta:
        model = Medicine
        fields = ["id", "name", "dosage", "frequency"]


class PrescriptionSerializer(serializers.ModelSerializer):

    medicines = MedicineSerializer(many=True, read_only=True)

    class Meta:
        model = Prescription
        fields = [
            "id",
            "image",
            "status",
            "created_at",
            "medicines"
        ]
        read_only_fields = ["status", "created_at"]