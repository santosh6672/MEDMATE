import 'package:flutter/material.dart';
import '../services/schedule_engine.dart'; // for MedicationIntent

class MedConfig {
  int dosesPerDay;
  int gapHours;
  TimeOfDay? firstDoseTime;
  String foodTag;
  bool beforeBed;
  TimeOfDay bedtime;
  String maxDoseInput;
  bool useAutomatic;
  MedicationIntent? intent;
  int? intervalHours;

  MedConfig({
    required this.dosesPerDay,
    required this.gapHours,
    this.firstDoseTime,
    this.foodTag = 'No preference',
    this.beforeBed = false,
    this.bedtime = const TimeOfDay(hour: 22, minute: 0),
    this.maxDoseInput = '',
    this.useAutomatic = true,
    this.intent,
    this.intervalHours,
  });

  List<TimeOfDay> get allDoseTimes {
    // If automatic mode, we compute times via engine later; this getter is for manual.
    if (useAutomatic) return [];
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
