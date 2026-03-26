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

class _UploadScreenState extends State<UploadScreen>
    with SingleTickerProviderStateMixin {
  File? _selectedImage;
  int? _prescriptionId;
  bool _isUploading = false;
  bool _isProcessing = false;
  bool _cancelled = false;
  String _errorMessage = '';
  int _pollAttempt = 0;

  static const int _pollIntervalSeconds = 20;
  static const int _maxPollAttempts = 15;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── Image picking ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedImage = File(picked.path);
        _errorMessage = '';
      });
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: kWhite,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Add Prescription Image',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kTextDark,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _SourceTile(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.camera);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SourceTile(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                  ),
                ],
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
      _isUploading = true;
      _errorMessage = '';
      _cancelled = false;
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
        ..files.add(
          await http.MultipartFile.fromPath('image', _selectedImage!.path),
        );

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));

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
          _isUploading = false;
          _isProcessing = true;
          _pollAttempt = 0;
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
      if (_cancelled || !mounted) return;

      await Future.delayed(
        const Duration(seconds: _pollIntervalSeconds),
      );

      if (_cancelled || !mounted) return;

      setState(() => _pollAttempt = attempt);

      try {
        final response = await ApiService.getWithAuth(
          '$kBaseUrl/api/prescriptions/$_prescriptionId/',
        );

        if (!mounted || _cancelled) return;

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final status = data['status'] as String? ?? '';
          final meds = data['medicines'] as List? ?? [];

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
              'the prescription format is unsupported.',
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

    if (!mounted || _cancelled) return;
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
      _isUploading = false;
      if (clearProcessing) _isProcessing = false;
    });
  }

  void _cancelProcessing() {
    setState(() {
      _cancelled = true;
      _isProcessing = false;
      _errorMessage = '';
    });
  }

  void _reset() {
    setState(() {
      _selectedImage = null;
      _prescriptionId = null;
      _errorMessage = '';
      _isUploading = false;
      _isProcessing = false;
      _cancelled = false;
      _pollAttempt = 0;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text(
          'Scan Prescription',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),

            // Instructions card
            if (!_isProcessing && _selectedImage == null)
              _InstructionsCard(),

            if (_selectedImage != null || _isProcessing)
              const SizedBox(height: 4),

            // Image preview box
            _ImagePreviewBox(
              image: _selectedImage,
              isBlocked: _isProcessing || _isUploading,
              onTap: _showImageSourceSheet,
            ),
            const SizedBox(height: 16),

            if (!_isProcessing) ...[
              // Camera / Gallery buttons
              _PickerButtons(
                disabled: _isUploading,
                onCamera: () => _pickImage(ImageSource.camera),
                onGallery: () => _pickImage(ImageSource.gallery),
              ),
              const SizedBox(height: 12),

              // Analyse button
              _AnalyseButton(
                enabled: _selectedImage != null && !_isUploading,
                isUploading: _isUploading,
                onPressed: _uploadPrescription,
              ),

              // Error banner
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                ErrorBanner(message: _errorMessage),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kPrimary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh_rounded, color: kPrimary),
                  label: const Text(
                    'Try Again',
                    style: TextStyle(color: kPrimary),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 24),

            // Processing card
            if (_isProcessing)
              _ProcessingCard(
                attempt: _pollAttempt,
                maxAttempts: _maxPollAttempts,
                onCancel: _cancelProcessing,
                pulseController: _pulseController,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _InstructionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPrimary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.lightbulb_outline_rounded,
                color: kPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Take a clear photo of your prescription. Ensure text is fully visible and well-lit.',
              style: TextStyle(
                fontSize: 13,
                color: kTextDark,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: kPrimary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kPrimary.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: kPrimary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewBox extends StatelessWidget {
  final File? image;
  final bool isBlocked;
  final VoidCallback onTap;

  const _ImagePreviewBox({
    required this.image,
    required this.isBlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isBlocked ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 240,
        decoration: BoxDecoration(
          color: kWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: image != null ? kPrimary : Colors.grey.shade300,
            width: image != null ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: image != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(image!, fit: BoxFit.cover),
                  if (!isBlocked)
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_rounded,
                                color: kWhite, size: 13),
                            SizedBox(width: 4),
                            Text(
                              'Change',
                              style: TextStyle(
                                color: kWhite,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kPrimary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 40,
                      color: kPrimary.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tap to add prescription photo',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kTextDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Camera or gallery',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PickerButtons extends StatelessWidget {
  final bool disabled;
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
              side: BorderSide(
                  color: disabled ? Colors.grey.shade300 : kPrimary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: disabled ? null : onCamera,
            icon: Icon(Icons.camera_alt_outlined,
                color: disabled ? Colors.grey : kPrimary, size: 18),
            label: Text(
              'Camera',
              style: TextStyle(
                color: disabled ? Colors.grey : kPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: disabled ? Colors.grey.shade300 : kPrimary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: disabled ? null : onGallery,
            icon: Icon(Icons.photo_library_outlined,
                color: disabled ? Colors.grey : kPrimary, size: 18),
            label: Text(
              'Gallery',
              style: TextStyle(
                color: disabled ? Colors.grey : kPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalyseButton extends StatelessWidget {
  final bool enabled;
  final bool isUploading;
  final VoidCallback onPressed;

  const _AnalyseButton({
    required this.enabled,
    required this.isUploading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: enabled ? kPrimary : Colors.grey.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        onPressed: enabled ? onPressed : null,
        icon: isUploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: kWhite,
                  strokeWidth: 2,
                ),
              )
            : Icon(Icons.document_scanner_rounded,
                color: enabled ? kWhite : Colors.grey.shade500),
        label: Text(
          isUploading ? 'Uploading...' : 'Analyse Prescription',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: enabled ? kWhite : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }
}

class _ProcessingCard extends StatelessWidget {
  final int attempt;
  final int maxAttempts;
  final VoidCallback onCancel;
  final AnimationController pulseController;

  const _ProcessingCard({
    required this.attempt,
    required this.maxAttempts,
    required this.onCancel,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    final progress = attempt / maxAttempts;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kPrimary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing icon
          AnimatedBuilder(
            animation: pulseController,
            builder: (_, child) {
              return Transform.scale(
                scale: 1.0 + pulseController.value * 0.08,
                child: child,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: kPrimary,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'AI is reading your prescription',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            attempt == 0
                ? 'Sending to our AI engine...'
                : 'Checking for results... (${attempt}/$maxAttempts)',
            style: const TextStyle(fontSize: 13, color: kTextGrey),
          ),
          const SizedBox(height: 18),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: attempt == 0 ? null : progress,
              backgroundColor: Colors.grey.shade200,
              color: kPrimary,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Usually takes 20–30 seconds',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),

          // Cancel button
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: kTextGrey,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}