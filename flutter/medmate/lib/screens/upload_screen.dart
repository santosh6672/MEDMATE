import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../constants.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'medicines_screen.dart';

// URL 1: POST /api/prescriptions/upload/
//   Body: multipart/form-data { "image": <file> }
//   Reply: { "id": 1, ... }
//
// URL 2: GET /api/prescriptions/<pk>/
//   Polled every 20s until medicines list is populated

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? selectedImage;
  int? prescriptionId;
  bool isUploading = false;
  bool isProcessing = false;
  String errorMessage = "";

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => selectedImage = File(picked.path));
  }

  Future<void> uploadPrescription() async {
    if (selectedImage == null) return;
    setState(() { isUploading = true; errorMessage = ""; });

    try {
      String? token = await ApiService.getAccessToken();

      var request = http.MultipartRequest("POST",
          Uri.parse("$kBaseUrl/api/prescriptions/upload/"));
      request.headers["Authorization"] = "Bearer $token";
      // Field name "image" must match Django serializer
      request.files.add(await http.MultipartFile.fromPath("image", selectedImage!.path));

      var response = await request.send();

      if (response.statusCode == 201) {
        var body = await response.stream.bytesToString();
        var data = jsonDecode(body);
        prescriptionId = data["id"];
        setState(() { isUploading = false; isProcessing = true; });
        pollForResults();

      } else if (response.statusCode == 401) {
        bool refreshed = await ApiService.refreshToken();
        if (refreshed) {
          setState(() => isUploading = false);
          await uploadPrescription();
        } else {
          setState(() { errorMessage = "Session expired. Please login again."; isUploading = false; });
        }

      } else {
        setState(() { errorMessage = "Upload failed. Please try again."; isUploading = false; });
      }
    } catch (_) {
      setState(() { errorMessage = "Cannot connect to server."; isUploading = false; });
    }
  }

  // Poll every 20s — Celery AI task runs in background on Django
  Future<void> pollForResults() async {
    while (true) {
      await Future.delayed(const Duration(seconds: 20));
      try {
        final response = await ApiService.getWithAuth(
            "$kBaseUrl/api/prescriptions/$prescriptionId/");

        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          if (data["medicines"] != null && data["medicines"].length > 0) {
            setState(() => isProcessing = false);
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => MedicinesScreen(medicines: data["medicines"])));
            break;
          }
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Prescription"),
          backgroundColor: kPrimary, foregroundColor: kWhite),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),

            // Image preview box
            GestureDetector(
              onTap: isProcessing ? null : pickImage,
              child: Container(
                width: double.infinity, height: 240,
                decoration: BoxDecoration(
                  color: kWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selectedImage != null ? kPrimary : Colors.grey.shade300,
                    width: selectedImage != null ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: selectedImage != null
                    ? Image.file(selectedImage!, fit: BoxFit.cover)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 60, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text("Tap to select prescription image",
                              style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 16),

            if (!isProcessing) ...[
              SizedBox(
                width: double.infinity, height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kPrimary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: pickImage,
                  icon: const Icon(Icons.photo_library, color: kPrimary),
                  label: const Text("Choose from Gallery", style: TextStyle(color: kPrimary, fontSize: 15)),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: selectedImage != null ? kPrimary : Colors.grey,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: selectedImage == null ? null : uploadPrescription,
                  icon: isUploading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: kWhite, strokeWidth: 2))
                      : const Icon(Icons.cloud_upload, color: kWhite),
                  label: Text(isUploading ? "Uploading..." : "Analyze Prescription",
                      style: const TextStyle(fontSize: 16, color: kWhite)),
                ),
              ),

              if (errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                ErrorBanner(message: errorMessage),
              ],
            ],

            const SizedBox(height: 24),

            if (isProcessing)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: kWhite, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kPrimary.withOpacity(0.3))),
                child: const Column(
                  children: [
                    CircularProgressIndicator(color: kPrimary),
                    SizedBox(height: 16),
                    Text("AI is reading your prescription...",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kTextDark)),
                    SizedBox(height: 4),
                    Text("Checking for results every 20 seconds",
                        style: TextStyle(fontSize: 13, color: kTextGrey)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}