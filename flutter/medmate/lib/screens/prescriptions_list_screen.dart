import 'dart:convert';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'medicines_screen.dart';

class PrescriptionsListScreen extends StatefulWidget {
  const PrescriptionsListScreen({super.key});

  @override
  State<PrescriptionsListScreen> createState() =>
      _PrescriptionsListScreenState();
}

class _PrescriptionsListScreenState
    extends State<PrescriptionsListScreen> {
  List<Map<String, dynamic>> _prescriptions = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadPrescriptions();
  }

  Future<void> _loadPrescriptions() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response =
          await ApiService.getWithAuth('$kBaseUrl/api/prescriptions/');

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is List) {
          _prescriptions = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else {
          _prescriptions = [];
        }

        setState(() => _isLoading = false);
      } else {
        _setError('Failed to load prescriptions.');
      }
    } catch (_) {
      _setError('Cannot connect to server.');
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'processed':
        return kAccent;
      case 'processing':
        return kPrimary;
      case 'pending':
        return const Color(0xFFFF6F00);
      case 'processed_empty':
        return kTextGrey;
      case 'failed':
        return kRed;
      default:
        return kTextGrey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'processed':
        return 'Done';
      case 'processing':
        return 'Processing...';
      case 'pending':
        return 'Queued';
      case 'processed_empty':
        return 'No data';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'processed':
        return Icons.check_circle_outline;
      case 'processing':
        return Icons.hourglass_top_outlined;
      case 'pending':
        return Icons.schedule_outlined;
      case 'processed_empty':
        return Icons.inbox_outlined;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.help_outline;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      const months = [
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text(
          'My Prescriptions',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadPrescriptions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: kPrimary),
            )
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_outlined,
                            size: 48, color: kTextGrey),
                        const SizedBox(height: 12),
                        ErrorBanner(message: _errorMessage),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _loadPrescriptions,
                          icon: const Icon(Icons.refresh, color: kPrimary),
                          label: const Text(
                            'Retry',
                            style: TextStyle(color: kPrimary),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: kPrimary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _prescriptions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: kPrimary.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.description_outlined,
                              size: 40,
                              color: kPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No prescriptions yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: kTextDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Scan your first prescription to begin',
                            style: TextStyle(
                              color: kTextGrey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: kPrimary,
                      onRefresh: _loadPrescriptions,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _prescriptions.length,
                        itemBuilder: (context, index) {
                          final p = _prescriptions[index];

                          final int id = p['id'] as int? ?? 0;
                          final List meds =
                              p['medicines'] as List? ?? [];
                          final String status =
                              p['status'] as String? ?? 'pending';
                          final String date =
                              _formatDate(p['created_at'] as String?);

                          final bool canOpen = meds.isNotEmpty;
                          final color = _statusColor(status);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: kWhite,
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: canOpen
                                  ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => MedicinesScreen(
                                            medicines: meds,
                                          ),
                                        ),
                                      )
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        _statusIcon(status),
                                        color: color,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                'Prescription #$id',
                                                style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  fontSize: 15,
                                                  color: kTextDark,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: color
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20),
                                                ),
                                                child: Text(
                                                  _statusLabel(status),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: color,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            meds.isEmpty
                                                ? (status == 'failed'
                                                    ? 'Processing failed'
                                                    : 'AI is processing...')
                                                : '${meds.length} medicine${meds.length == 1 ? '' : 's'} found',
                                            style: const TextStyle(
                                              color: kTextGrey,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (date.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              date,
                                              style: const TextStyle(
                                                color: kTextGrey,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (canOpen)
                                      const Icon(
                                        Icons.chevron_right,
                                        color: kTextGrey,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}