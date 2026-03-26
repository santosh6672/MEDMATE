import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/med_config.dart';
import '../models/user_anchors.dart';
import '../services/schedule_engine.dart';
import '../services/anchor_storage.dart';
import 'anchor_setup_screen.dart';
import 'schedule_preview_screen.dart';

// ── Helpers (top-level) ────────────────────────────────────────────────────────

int _parseDoseCount(String frequency) {
  final f = frequency.toLowerCase();
  if (f.contains('4') || f.contains('four') || f.contains('qid')) return 4;
  if (f.contains('3') || f.contains('three') || f.contains('tid')) return 3;
  if (f.contains('2') || f.contains('twice') || f.contains('bid')) return 2;
  return 1;
}

int _defaultGap(int doses) {
  switch (doses) {
    case 2:
      return 8;
    case 3:
      return 6;
    case 4:
      return 4;
    default:
      return 12;
  }
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class MedicinesScreen extends StatefulWidget {
  final List medicines;
  const MedicinesScreen({super.key, required this.medicines});

  @override
  State<MedicinesScreen> createState() => _MedicinesScreenState();
}

class _MedicinesScreenState extends State<MedicinesScreen> {
  late final List<MedConfig> _configs;
  UserAnchors? _anchors;

  @override
  void initState() {
    super.initState();
    _configs = widget.medicines.map((med) {
      final doses = _parseDoseCount(med['frequency'] ?? '');
      return MedConfig(
        dosesPerDay: doses,
        gapHours: _defaultGap(doses),
        useAutomatic: true,
        intent: MedicationIntent.beforeBreakfast,
      );
    }).toList();

    _loadAnchors();
  }

  Future<void> _loadAnchors() async {
    final anchors = await AnchorStorage.loadAnchors();
    if (anchors == null) {
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AnchorSetupScreen(isEditing: true),
          ),
        );
        _loadAnchors();
      }
      return;
    }
    setState(() => _anchors = anchors);
  }

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _configs[index].firstDoseTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _configs[index].firstDoseTime = picked);
    }
  }

  Future<void> _saveReminders() async {
    if (_anchors == null) {
      _showSnack('Please set your daily schedule first', isError: true);
      return;
    }

    for (int i = 0; i < _configs.length; i++) {
      final cfg = _configs[i];
      if (cfg.useAutomatic && cfg.intent == null) {
        _showSnack('Select an intent for all automatic medicines',
            isError: true);
        return;
      }
      if (!cfg.useAutomatic && cfg.firstDoseTime == null) {
        _showSnack('Pick a first dose time for manual schedules',
            isError: true);
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SchedulePreviewScreen(
          medicines: widget.medicines,
          anchors: _anchors!,
          configs: _configs,
        ),
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? kRed : kAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_anchors == null) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text(
          'Set Schedule',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Summary header
          _SummaryHeader(count: widget.medicines.length),

          // Medicine cards
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: widget.medicines.length,
              itemBuilder: (context, i) {
                final med = widget.medicines[i];
                final cfg = _configs[i];
                return _MedicineCard(
                  index: i,
                  med: med,
                  cfg: cfg,
                  onModeChanged: (val) =>
                      setState(() => cfg.useAutomatic = val),
                  onIntentChanged: (val) =>
                      setState(() => cfg.intent = val),
                  onPickTime: () => _pickTime(i),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _SaveBar(onSave: _saveReminders),
    );
  }
}

// ── Summary header ─────────────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  final int count;
  const _SummaryHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kPrimary,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: kWhite.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.medication_rounded, color: kWhite, size: 20),
            const SizedBox(width: 10),
            Text(
              '$count medicine${count == 1 ? '' : 's'} found',
              style: const TextStyle(
                color: kWhite,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kWhite.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Configure each',
                style: TextStyle(
                  color: kWhite,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Medicine Card ──────────────────────────────────────────────────────────────

class _MedicineCard extends StatelessWidget {
  final int index;
  final dynamic med;
  final MedConfig cfg;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<MedicationIntent?> onIntentChanged;
  final VoidCallback onPickTime;

  const _MedicineCard({
    required this.index,
    required this.med,
    required this.cfg,
    required this.onModeChanged,
    required this.onIntentChanged,
    required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Medicine name header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.04),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                  bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: kPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med['name'] ?? 'Unknown Medicine',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: kTextDark,
                        ),
                      ),
                      if ((med['dosage'] ?? '').isNotEmpty ||
                          (med['frequency'] ?? '').isNotEmpty)
                        Text(
                          [
                            if ((med['dosage'] ?? '').isNotEmpty)
                              med['dosage'],
                            if ((med['frequency'] ?? '').isNotEmpty)
                              med['frequency'],
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: kTextGrey,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Schedule config body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mode label
                const Text(
                  'Schedule mode',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kTextGrey,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),

                // Toggle buttons
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.restaurant_rounded, size: 15),
                      label: Text('Auto (meals)'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.schedule_rounded, size: 15),
                      label: Text('Manual time'),
                    ),
                  ],
                  selected: {cfg.useAutomatic},
                  onSelectionChanged: (s) => onModeChanged(s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Mode-specific controls
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: cfg.useAutomatic
                      ? _AutoSection(
                          key: const ValueKey('auto'),
                          intent: cfg.intent,
                          onChanged: onIntentChanged,
                        )
                      : _ManualSection(
                          key: const ValueKey('manual'),
                          time: cfg.firstDoseTime,
                          onPick: onPickTime,
                          dosesPerDay: cfg.dosesPerDay,
                          gapHours: cfg.gapHours,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Auto Section ───────────────────────────────────────────────────────────────

class _AutoSection extends StatelessWidget {
  final MedicationIntent? intent;
  final ValueChanged<MedicationIntent?> onChanged;

  const _AutoSection({super.key, required this.intent, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<MedicationIntent>(
      value: intent,
      decoration: InputDecoration(
        labelText: 'When to take',
        labelStyle: const TextStyle(color: kTextGrey, fontSize: 13),
        prefixIcon:
            const Icon(Icons.access_time_rounded, color: kPrimary, size: 18),
        filled: true,
        fillColor: kBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary),
        ),
      ),
      items: MedicationIntent.values.map((intent) {
        return DropdownMenuItem(
          value: intent,
          child: Text(
            intent.name,
            style: const TextStyle(fontSize: 14, color: kTextDark),
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

// ── Manual Section ─────────────────────────────────────────────────────────────

class _ManualSection extends StatelessWidget {
  final TimeOfDay? time;
  final VoidCallback onPick;
  final int dosesPerDay;
  final int gapHours;

  const _ManualSection({
    super.key,
    required this.time,
    required this.onPick,
    required this.dosesPerDay,
    required this.gapHours,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    time != null ? kPrimary : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  color: time != null ? kPrimary : kTextGrey,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    time == null
                        ? 'Pick first dose time'
                        : time!.format(context),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: time != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: time != null ? kTextDark : kTextGrey,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (time != null && dosesPerDay > 1) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: kAccent, size: 14),
                const SizedBox(width: 6),
                Text(
                  '$dosesPerDay doses · $gapHours hrs apart',
                  style: const TextStyle(
                    fontSize: 12,
                    color: kAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Save Bar ───────────────────────────────────────────────────────────────────

class _SaveBar extends StatelessWidget {
  final VoidCallback onSave;
  const _SaveBar({required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: kWhite,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SizedBox(
        height: 50,
        child: FilledButton.icon(
          onPressed: onSave,
          style: FilledButton.styleFrom(
            backgroundColor: kPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.arrow_forward_rounded, color: kWhite),
          label: const Text(
            'Preview Schedule',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kWhite,
            ),
          ),
        ),
      ),
    );
  }
}