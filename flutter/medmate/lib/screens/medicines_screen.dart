import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../services/reminder_storage.dart';
import '../services/notification_service.dart';

class MedicinesScreen extends StatefulWidget {
  final List medicines;
  const MedicinesScreen({super.key, required this.medicines});

  @override
  State<MedicinesScreen> createState() => _MedicinesScreenState();
}

class _MedConfig {
  int dosesPerDay;
  int gapHours;
  TimeOfDay? firstDoseTime;
  String foodTag;
  bool beforeBed;
  TimeOfDay bedtime;
  String maxDoseInput;

  _MedConfig({
    required this.dosesPerDay,
    required this.gapHours,
    this.firstDoseTime,
    this.foodTag = 'No preference',
    this.beforeBed = false,
    this.bedtime = const TimeOfDay(hour: 22, minute: 0),
    this.maxDoseInput = '',
  });

  List<TimeOfDay> get allDoseTimes {
    if (firstDoseTime == null) return [];

    final times = List.generate(dosesPerDay, (i) {
      final totalMinutes =
          firstDoseTime!.hour * 60 + firstDoseTime!.minute + i * gapHours * 60;

      return TimeOfDay(
        hour: (totalMinutes ~/ 60) % 24,
        minute: totalMinutes % 60,
      );
    });

    if (beforeBed && dosesPerDay > 1) {
      times[times.length - 1] = bedtime;
    }

    return times;
  }

  String maxDoseWarning(String dosageStr) {
    if (maxDoseInput.trim().isEmpty) return '';

    final maxVal = double.tryParse(maxDoseInput.trim());
    if (maxVal == null) return '';

    final match = RegExp(r'(\d+\.?\d*)').firstMatch(dosageStr);
    if (match == null) return '';

    final doseVal = double.tryParse(match.group(1)!);
    if (doseVal == null) return '';

    final total = doseVal * dosesPerDay;

    if (total > maxVal) {
      return 'Total daily: ${total.toStringAsFixed(0)} mg exceeds max of ${maxVal.toStringAsFixed(0)} mg';
    }

    return '';
  }
}

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

class _MedicinesScreenState extends State<MedicinesScreen> {
  late final List<_MedConfig> _configs;
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();

    _configs = widget.medicines.map((med) {
      final doses = _parseDoseCount(med['frequency'] ?? '');
      return _MedConfig(
        dosesPerDay: doses,
        gapHours: _defaultGap(doses),
      );
    }).toList();

    _controllers =
        List.generate(widget.medicines.length, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          _configs[index].firstDoseTime ?? TimeOfDay.now(),
    );

    if (picked != null) {
      setState(() => _configs[index].firstDoseTime = picked);
    }
  }

  Future<void> _saveReminders() async {
    int saved = 0;
    final List<Map<String, dynamic>> toSave = [];

    for (int i = 0; i < widget.medicines.length; i++) {
      final cfg = _configs[i];

      if (cfg.firstDoseTime == null) continue;

      final med = widget.medicines[i];
      final name = med['name'] ?? 'Unknown';

      final times = cfg.allDoseTimes;

      for (int d = 0; d < times.length; d++) {
        final t = times[d];

        final baseId =
            ('$name${t.hour}${t.minute}').hashCode.abs();

        await scheduleReminder(
          baseId: baseId,
          medicineName: name,
          hour: t.hour,
          minute: t.minute,
        );

        toSave.add({
          'name': name,
          'hour': t.hour,
          'minute': t.minute,
          'baseId': baseId,
          'doseNumber': d + 1,
          'dosesPerDay': cfg.dosesPerDay,
          'foodTag': cfg.foodTag,
          'beforeBed': cfg.beforeBed && d == times.length - 1,
          'taken': false,
        });

        saved++;
      }
    }

    if (toSave.isNotEmpty) {
      await ReminderStorage.saveReminders(toSave);
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved > 0
              ? '$saved reminders saved'
              : 'No reminders set',
        ),
        backgroundColor: saved > 0 ? kAccent : kTextGrey,
      ),
    );

    if (saved > 0) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Schedule'),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.medicines.length,
        itemBuilder: (context, i) {
          final med = widget.medicines[i];
          final cfg = _configs[i];

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    med['name'] ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => _pickTime(i),
                    child: Text(
                      cfg.firstDoseTime == null
                          ? 'Pick time'
                          : cfg.firstDoseTime!.format(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _saveReminders,
            child: const Text('Save'),
          ),
        ),
      ),
    );
  }
}