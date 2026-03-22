import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../constants.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'medicines_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File?   _selectedImage;
  int?    _prescriptionId;
  bool    _isUploading  = false;
  bool    _isProcessing = false;
  String  _errorMessage = '';

  static const int    _pollIntervalSeconds = 20;
  static const int    _maxPollAttempts     = 15;

  // ── Image picking ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source:       source,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedImage = File(picked.path);
        _errorMessage  = '';
      });
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select image source',
                style: TextStyle(
                  fontSize:   16,
                  fontWeight: FontWeight.bold,
                  color:      kTextDark,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: kPrimary),
                title:   const Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: kPrimary),
                title:   const Text('Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Upload ─────────────────────────────────────────────────────────────────

  Future<void> _uploadPrescription() async {
    if (_selectedImage == null || _isUploading) return;

    setState(() {
      _isUploading  = true;
      _errorMessage = '';
    });

    try {
      final token = await ApiService.getAccessToken();
      if (token == null || token.isEmpty) {
        _setError('Session expired. Please login again.');
        return;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$kBaseUrl/api/prescriptions/upload/'),
      )
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['ngrok-skip-browser-warning'] = 'true'
        ..files.add(
          await http.MultipartFile.fromPath('image', _selectedImage!.path),
        );

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );

      if (!mounted) return;

      if (streamed.statusCode == 201) {
        final body = await streamed.stream.bytesToString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        _prescriptionId = data['id'] as int?;

        if (_prescriptionId == null) {
          _setError('Unexpected server response. Please try again.');
          return;
        }

        setState(() {
          _isUploading  = false;
          _isProcessing = true;
        });
        _pollForResults();

      } else if (streamed.statusCode == 401) {
        final refreshed = await ApiService.refreshToken();
        if (refreshed) {
          setState(() => _isUploading = false);
          await _uploadPrescription();
        } else {
          _setError('Session expired. Please login again.');
        }

      } else {
        _setError('Upload failed (${streamed.statusCode}). Please try again.');
      }
    } on SocketException {
      _setError('Cannot connect to server. Check your internet connection.');
    } catch (_) {
      _setError('An unexpected error occurred. Please try again.');
    }
  }

  // ── Poll ───────────────────────────────────────────────────────────────────

  Future<void> _pollForResults() async {
    for (int attempt = 1; attempt <= _maxPollAttempts; attempt++) {
      await Future.delayed(
        const Duration(seconds: _pollIntervalSeconds),
      );

      if (!mounted) return;

      try {
        final response = await ApiService.getWithAuth(
          '$kBaseUrl/api/prescriptions/$_prescriptionId/',
        );

        if (!mounted) return;

        if (response.statusCode == 200) {
          final data   = jsonDecode(response.body) as Map<String, dynamic>;
          final status = data['status'] as String? ?? '';
          final meds   = data['medicines'] as List? ?? [];

          if (status == 'processed' && meds.isNotEmpty) {
            setState(() => _isProcessing = false);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MedicinesScreen(medicines: meds),
              ),
            );
            return;
          }

          if (status == 'processed_empty') {
            _setError(
              'No medicines detected. The image may be illegible or '
              'the prescription format is unsupported. Please try again.',
              clearProcessing: true,
            );
            return;
          }

          if (status == 'failed') {
            _setError(
              'Processing failed. Please try uploading again.',
              clearProcessing: true,
            );
            return;
          }
        }
      } catch (_) {
        // Network hiccup — continue polling silently.
      }
    }

    if (!mounted) return;
    _setError(
      'Processing is taking longer than expected. '
      "Check 'My Prescriptions' in a few minutes.",
      clearProcessing: true,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setError(String message, {bool clearProcessing = false}) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isUploading  = false;
      if (clearProcessing) _isProcessing = false;
    });
  }

  void _reset() {
    setState(() {
      _selectedImage  = null;
      _prescriptionId = null;
      _errorMessage   = '';
      _isUploading    = false;
      _isProcessing   = false;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:           const Text('Scan Prescription'),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
        elevation:       0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            _ImagePreviewBox(
              image:      _selectedImage,
              isBlocked:  _isProcessing || _isUploading,
              onTap:      _showImageSourceSheet,
            ),
            const SizedBox(height: 16),
            if (!_isProcessing) ...[
              _PickerButtons(
                disabled: _isUploading,
                onCamera:  () => _pickImage(ImageSource.camera),
                onGallery: () => _pickImage(ImageSource.gallery),
              ),
              const SizedBox(height: 12),
              _AnalyseButton(
                enabled:     _selectedImage != null && !_isUploading,
                isUploading: _isUploading,
                onPressed:   _uploadPrescription,
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                ErrorBanner(message: _errorMessage),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side:  const BorderSide(color: kPrimary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _reset,
                  child: const Text(
                    'Try Again',
                    style: TextStyle(color: kPrimary),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            if (_isProcessing) const _ProcessingCard(),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _ImagePreviewBox extends StatelessWidget {
  final File?        image;
  final bool         isBlocked;
  final VoidCallback onTap;

  const _ImagePreviewBox({
    required this.image,
    required this.isBlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:    isBlocked ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width:  double.infinity,
        height: 240,
        decoration: BoxDecoration(
          color:        kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: image != null ? kPrimary : Colors.grey.shade300,
            width: image != null ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: image != null
            ? Image.file(image!, fit: BoxFit.cover)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size:  60,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tap to take photo or choose from gallery',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color:    Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PickerButtons extends StatelessWidget {
  final bool         disabled;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const _PickerButtons({
    required this.disabled,
    required this.onCamera,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side:    const BorderSide(color: kPrimary),
              shape:   RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: disabled ? null : onCamera,
            icon:      const Icon(Icons.camera_alt_outlined, color: kPrimary),
            label: const Text(
              'Camera',
              style: TextStyle(color: kPrimary, fontSize: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side:    const BorderSide(color: kPrimary),
              shape:   RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: disabled ? null : onGallery,
            icon:      const Icon(Icons.photo_library_outlined, color: kPrimary),
            label: const Text(
              'Gallery',
              style: TextStyle(color: kPrimary, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalyseButton extends StatelessWidget {
  final bool         enabled;
  final bool         isUploading;
  final VoidCallback onPressed;

  const _AnalyseButton({
    required this.enabled,
    required this.isUploading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: enabled ? kPrimary : Colors.grey,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        icon: isUploading
            ? const SizedBox(
                width:  18,
                height: 18,
                child:  CircularProgressIndicator(
                  color:       kWhite,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.cloud_upload, color: kWhite),
        label: Text(
          isUploading ? 'Uploading...' : 'Analyse Prescription',
          style: const TextStyle(fontSize: 16, color: kWhite),
        ),
      ),
    );
  }
}

class _ProcessingCard extends StatelessWidget {
  const _ProcessingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color:        kWhite,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: kPrimary.withOpacity(0.3)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: kPrimary),
          SizedBox(height: 16),
          Text(
            'AI is reading your prescription...',
            style: TextStyle(
              fontSize:   15,
              fontWeight: FontWeight.w600,
              color:      kTextDark,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'This usually takes 20\u201330 seconds',
            style: TextStyle(fontSize: 13, color: kTextGrey),
          ),
          SizedBox(height: 4),
          Text(
            'Checking for results every 20 seconds',
            style: TextStyle(fontSize: 12, color: kTextGrey),
          ),
        ],
      ),
    );
  }
}