from rest_framework import generics, permissions
from rest_framework.response import Response

from .models import Prescription
from .serializers import PrescriptionSerializer

from .tasks import process_prescription_ai
from rest_framework.parsers import MultiPartParser, FormParser

class UploadPrescriptionView(generics.CreateAPIView):

    serializer_class = PrescriptionSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = (MultiPartParser, FormParser)

    def perform_create(self, serializer):

        prescription = serializer.save(user=self.request.user)

        # trigger AI pipeline
        process_prescription_ai.delay(prescription.id)


class ListPrescriptionsView(generics.ListAPIView):

    serializer_class = PrescriptionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Prescription.objects.filter(user=self.request.user).order_by("-created_at")


class PrescriptionDetailView(generics.RetrieveAPIView):

    serializer_class = PrescriptionSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Prescription.objects.filter(user=self.request.user)