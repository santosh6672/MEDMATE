import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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

  // ── Image Picker ─────────────────────────────

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

  // ── Upload (FIXED) ───────────────────────────

  Future<void> _uploadPrescription() async {
    if (_selectedImage == null || _isUploading) return;

    setState(() {
      _isUploading = true;
      _errorMessage = '';
      _cancelled = false;
    });

    try {
      final response = await ApiService.uploadPrescription(_selectedImage!);

      if (!mounted) return;

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);

        _prescriptionId = data['id'];

        if (_prescriptionId == null) {
          _setError('Invalid response from server.');
          return;
        }

        setState(() {
          _isUploading = false;
          _isProcessing = true;
          _pollAttempt = 0;
        });

        _pollForResults();
      } else if (response.statusCode == 401) {
        _setError('Session expired. Please login again.');
      } else {
        _setError('Upload failed (${response.statusCode}).');
      }
    } on SocketException {
      _setError('No internet connection.');
    } catch (e) {
      _setError('Something went wrong.');
    }
  }

  // ── Polling (UNCHANGED - CORRECT) ───────────

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
          final data = jsonDecode(response.body);

          final status = data['status'] ?? '';
          final meds = data['medicines'] ?? [];

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
            _setError('No medicines detected.', clearProcessing: true);
            return;
          }

          if (status == 'failed') {
            _setError('Processing failed.', clearProcessing: true);
            return;
          }
        }
      } catch (_) {}
    }

    _setError(
      'Processing taking longer. Check history later.',
      clearProcessing: true,
    );
  }

  // ── Helpers ────────────────────────────────

  void _setError(String msg, {bool clearProcessing = false}) {
    if (!mounted) return;

    setState(() {
      _errorMessage = msg;
      _isUploading = false;
      if (clearProcessing) _isProcessing = false;
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

  // ── UI ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Scan Prescription'),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: () => _pickImage(ImageSource.gallery),
              child: Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: kPrimary),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _selectedImage == null
                    ? const Center(child: Text('Tap to select image'))
                    : Image.file(_selectedImage!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed:
                  (_selectedImage != null && !_isUploading)
                      ? _uploadPrescription
                      : null,
              child: _isUploading
                  ? const CircularProgressIndicator()
                  : const Text('Upload & Analyse'),
            ),

            const SizedBox(height: 20),

            if (_isProcessing)
              Text('Processing... Attempt $_pollAttempt'),

            if (_errorMessage.isNotEmpty)
              Text(_errorMessage, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
