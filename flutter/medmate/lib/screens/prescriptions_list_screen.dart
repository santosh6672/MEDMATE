import 'dart:convert';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/api_service.dart';
import '../utils/date_utils.dart'; // shared formatDate utility
import '../widgets/common_widgets.dart';
import 'medicines_screen.dart';

class PrescriptionsListScreen extends StatefulWidget {
  const PrescriptionsListScreen({super.key});

  @override
  State<PrescriptionsListScreen> createState() =>
      _PrescriptionsListScreenState();
}

class _PrescriptionsListScreenState extends State<PrescriptionsListScreen> {
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
        _prescriptions = decoded is List
            ? decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : [];
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

  _StatusStyle _statusStyle(String status) {
    switch (status) {
      case 'processed':
        return _StatusStyle(
          color: kAccent,
          icon: Icons.check_circle_outline_rounded,
          label: 'Done',
        );
      case 'processing':
        return _StatusStyle(
          color: kPrimary,
          icon: Icons.hourglass_top_outlined,
          label: 'Processing',
        );
      case 'pending':
        return _StatusStyle(
          color: const Color(0xFFFF6F00),
          icon: Icons.schedule_outlined,
          label: 'Queued',
        );
      case 'processed_empty':
        return _StatusStyle(
          color: kTextGrey,
          icon: Icons.inbox_outlined,
          label: 'No data',
        );
      case 'failed':
        return _StatusStyle(
          color: kRed,
          icon: Icons.error_outline_rounded,
          label: 'Failed',
        );
      default:
        return _StatusStyle(
          color: kTextGrey,
          icon: Icons.help_outline_rounded,
          label: status,
        );
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
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kPrimary),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_off_outlined,
                    size: 40, color: kTextGrey),
              ),
              const SizedBox(height: 16),
              const Text(
                'Connection issue',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: kTextDark,
                ),
              ),
              const SizedBox(height: 8),
              ErrorBanner(message: _errorMessage),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadPrescriptions,
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, color: kWhite),
                label: const Text('Retry',
                    style: TextStyle(color: kWhite, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    }

    // Wrap empty state in RefreshIndicator so user can pull to refresh
    if (_prescriptions.isEmpty) {
      return RefreshIndicator(
        color: kPrimary,
        onRefresh: _loadPrescriptions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: kPrimary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      size: 44,
                      color: kPrimary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'No prescriptions yet',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: kTextDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Scan your first prescription to begin',
                    style: TextStyle(color: kTextGrey, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pull down to refresh',
                    style: TextStyle(color: kTextGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _loadPrescriptions,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _prescriptions.length,
        itemBuilder: (context, index) {
          final p = _prescriptions[index];
          final int id = p['id'] as int? ?? 0;
          final List meds = p['medicines'] as List? ?? [];
          final String status = p['status'] as String? ?? 'pending';
          final String date = AppDateUtils.formatDate(p['created_at'] as String?);
          final bool canOpen = meds.isNotEmpty;
          final style = _statusStyle(status);

          return _PrescriptionCard(
            id: id,
            meds: meds,
            status: status,
            date: date,
            canOpen: canOpen,
            statusStyle: style,
            onTap: canOpen
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MedicinesScreen(medicines: meds),
                      ),
                    )
                : null,
          );
        },
      ),
    );
  }
}

// ── Status Style model ─────────────────────────────────────────────────────────

class _StatusStyle {
  final Color color;
  final IconData icon;
  final String label;
  const _StatusStyle(
      {required this.color, required this.icon, required this.label});
}

// ── Prescription Card ──────────────────────────────────────────────────────────

class _PrescriptionCard extends StatelessWidget {
  final int id;
  final List meds;
  final String status;
  final String date;
  final bool canOpen;
  final _StatusStyle statusStyle;
  final VoidCallback? onTap;

  const _PrescriptionCard({
    required this.id,
    required this.meds,
    required this.status,
    required this.date,
    required this.canOpen,
    required this.statusStyle,
    required this.onTap,
  });

  String get _subtitle {
    if (meds.isEmpty) {
      return status == 'failed' ? 'Processing failed' : 'AI is processing...';
    }
    return '${meds.length} medicine${meds.length == 1 ? '' : 's'} found';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: canOpen ? Colors.grey.shade200 : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusStyle.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: status == 'processing'
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: kPrimary,
                        ),
                      )
                    : Icon(statusStyle.icon,
                        color: statusStyle.color, size: 24),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Prescription #$id',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: kTextDark,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusStyle.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statusStyle.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: statusStyle.color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle,
                      style: const TextStyle(
                          color: kTextGrey, fontSize: 13),
                    ),
                    if (date.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 11, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            date,
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Chevron
              if (canOpen) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: kTextGrey, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}