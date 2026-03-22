from django.db import models
from django.contrib.auth.models import User


class Prescription(models.Model):

    STATUS_CHOICES = [
        ("pending",         "Pending"),
        ("processing",      "Processing"),
        ("processed",       "Processed"),
        ("processed_empty", "Processed Empty"),
        ("failed",          "Failed"),
    ]

    user       = models.ForeignKey(User, on_delete=models.CASCADE, related_name="prescriptions")
    image      = models.ImageField(upload_to="prescriptions/")
    status     = models.CharField(max_length=20, choices=STATUS_CHOICES, default="pending")

    # Basic info — often missing, that's fine
    doctor     = models.CharField(max_length=255, default="Not specified")
    diagnosis  = models.CharField(max_length=255, default="Not specified")

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Prescription {self.id} — {self.user.username} [{self.status}]"


class Medicine(models.Model):

    prescription     = models.ForeignKey(Prescription, on_delete=models.CASCADE, related_name="medicines")

    # Core fields — always present
    name             = models.CharField(max_length=255, default="Not specified")
    generic_name     = models.CharField(max_length=255, default="Not specified")
    dosage           = models.CharField(max_length=100, default="Not specified")
    frequency        = models.CharField(max_length=100, default="Not specified")

    # Secondary fields — often present
    duration         = models.CharField(max_length=100, default="Not specified")
    instructions     = models.CharField(max_length=255, default="Not specified")
    type             = models.CharField(max_length=100, default="Not specified")

    # Clinical flags from LLM
    dose_flag        = models.CharField(max_length=20,  default="Not specified")
    dose_flag_reason = models.CharField(max_length=255, default="Not specified")

    created_at       = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} — {self.dosage} — {self.frequency}"