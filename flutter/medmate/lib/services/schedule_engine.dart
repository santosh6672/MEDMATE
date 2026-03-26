import 'package:flutter/material.dart';
import '../models/user_anchors.dart';

enum MedicationIntent {
  beforeBreakfast,
  afterBreakfast,
  withBreakfast,
  beforeLunch,
  afterLunch,
  beforeDinner,
  afterDinner,
  atBedtime,
  emptyStomach,
  everyXHours,
}

class ScheduleEngine {
  /// Computes the next occurrence of a medication based on its intent and user anchors.
  static DateTime? computeTime({
    required MedicationIntent intent,
    required UserAnchors anchors,
    DateTime? referenceDate,
    int? intervalHours, // for everyXHours
  }) {
    final now = referenceDate ?? DateTime.now();
    final date = DateTime(now.year, now.month, now.day);

    TimeOfDay targetAnchor;
    int offsetMinutes;

    switch (intent) {
      case MedicationIntent.beforeBreakfast:
        targetAnchor = anchors.breakfast;
        offsetMinutes = -30;
        break;
      case MedicationIntent.afterBreakfast:
        targetAnchor = anchors.breakfast;
        offsetMinutes = 15;
        break;
      case MedicationIntent.withBreakfast:
        targetAnchor = anchors.breakfast;
        offsetMinutes = 0;
        break;
      case MedicationIntent.beforeLunch:
        targetAnchor = anchors.lunch;
        offsetMinutes = -30;
        break;
      case MedicationIntent.afterLunch:
        targetAnchor = anchors.lunch;
        offsetMinutes = 15;
        break;
      case MedicationIntent.beforeDinner:
        targetAnchor = anchors.dinner;
        offsetMinutes = -30;
        break;
      case MedicationIntent.afterDinner:
        targetAnchor = anchors.dinner;
        offsetMinutes = 15;
        break;
      case MedicationIntent.atBedtime:
        targetAnchor = anchors.sleep;
        offsetMinutes = 0;
        break;
      case MedicationIntent.emptyStomach:
        // Use wakeUp + 30 minutes as default (or before breakfast)
        targetAnchor = anchors.wakeUp;
        offsetMinutes = 30;
        break;
      case MedicationIntent.everyXHours:
        // Not implemented in MVP – will be handled separately
        return null;
    }

    final baseTime = DateTime(
      date.year,
      date.month,
      date.day,
      targetAnchor.hour,
      targetAnchor.minute,
    ).add(Duration(minutes: offsetMinutes));

    // If the computed time is already in the past, return tomorrow's time.
    if (baseTime.isBefore(now)) {
      return baseTime.add(const Duration(days: 1));
    }
    return baseTime;
  }

  static List<DateTime> computeAllTimes({
    required int dosesPerDay,
    required int gapHours,
    required MedicationIntent intent,
    required UserAnchors anchors,
    DateTime? referenceDate,
  }) {
    final firstTime = computeTime(
      intent: intent,
      anchors: anchors,
      referenceDate: referenceDate,
    );
    if (firstTime == null) return [];
    final times = <DateTime>[firstTime];
    for (int i = 1; i < dosesPerDay; i++) {
      final nextTime = firstTime.add(Duration(hours: gapHours * i));
      times.add(nextTime);
    }
    return times;
  }
}
