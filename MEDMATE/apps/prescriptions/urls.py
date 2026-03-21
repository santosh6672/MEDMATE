"""
prescriptions/urls.py
"""

from django.urls import path

from .views import (
    ListPrescriptionsView,
    PrescriptionDetailView,
    UploadPrescriptionView,
)

urlpatterns = [
    path("upload/", UploadPrescriptionView.as_view(),   name="upload_prescription"),
    path("",        ListPrescriptionsView.as_view(),    name="list_prescriptions"),
    path("<int:pk>/", PrescriptionDetailView.as_view(), name="prescription_detail"),
]