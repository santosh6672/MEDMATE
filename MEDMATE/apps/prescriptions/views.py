"""
prescriptions/views.py

Fixes vs original:
  - process_prescription_ai.delay() is now called inside transaction.on_commit()
    so Celery never receives the task ID before the row is committed to the DB.
    Without this, a fast broker can dispatch the task before the DB write is
    visible, causing tasks.py to raise Prescription.DoesNotExist.
"""

import logging

from django.db import transaction
from rest_framework import generics, permissions
from rest_framework.parsers import FormParser, MultiPartParser

from .models import Prescription
from .serializers import PrescriptionSerializer
from .tasks import process_prescription_ai

logger = logging.getLogger(__name__)


class UploadPrescriptionView(generics.CreateAPIView):
    """
    POST /prescriptions/upload/

    Accepts a multipart image upload, creates a Prescription row,
    and queues the AI pipeline task after the DB transaction commits.
    """
    serializer_class   = PrescriptionSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes     = (MultiPartParser, FormParser)

    def perform_create(self, serializer):
        prescription = serializer.save(user=self.request.user)
        logger.info(
            "Prescription %d created by user %d — queuing AI task",
            prescription.id,
            self.request.user.id,
        )
        # Dispatch AFTER the transaction commits so the Celery worker is
        # guaranteed to find the row when it calls Prescription.objects.get().
        transaction.on_commit(
            lambda: process_prescription_ai.delay(prescription.id)
        )


class ListPrescriptionsView(generics.ListAPIView):
    """
    GET /prescriptions/

    Returns all prescriptions belonging to the authenticated user,
    newest first.
    """
    serializer_class   = PrescriptionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return (
            Prescription.objects
            .filter(user=self.request.user)
            .prefetch_related("medicines")
            .order_by("-created_at")
        )


class PrescriptionDetailView(generics.RetrieveAPIView):
    """
    GET /prescriptions/<pk>/

    Returns a single prescription with its medicines.
    """
    serializer_class   = PrescriptionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return (
            Prescription.objects
            .filter(user=self.request.user)
            .prefetch_related("medicines")
        )