"""
prescriptions/views.py
"""

import logging

from django.db import transaction
from rest_framework import generics, permissions, status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response

from .models import Prescription
from .serializers import PrescriptionSerializer
from .tasks import process_prescription_ai

logger = logging.getLogger(__name__)


class UploadPrescriptionView(generics.CreateAPIView):
    """
    POST /prescriptions/upload/
    """
    serializer_class   = PrescriptionSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes     = (MultiPartParser, FormParser)

    def perform_create(self, serializer):
        prescription = serializer.save(user=self.request.user)
        logger.info(
            "Prescription %d created — user=%d  queuing AI task after commit",
            prescription.id,
            self.request.user.id,
        )
        transaction.on_commit(
            lambda: process_prescription_ai.delay(prescription.id)
        )

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class ListPrescriptionsView(generics.ListAPIView):
    """
    GET /prescriptions/
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
    """
    serializer_class   = PrescriptionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return (
            Prescription.objects
            .filter(user=self.request.user)
            .prefetch_related("medicines")
        )