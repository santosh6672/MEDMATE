import 'package:flutter/material.dart';

class UserAnchors {
  final TimeOfDay wakeUp;
  final TimeOfDay breakfast;
  final TimeOfDay lunch;
  final TimeOfDay dinner;
  final TimeOfDay sleep;

  UserAnchors({
    required this.wakeUp,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.sleep,
  });

  Map<String, int> toMap() => {
        'wakeUpHour': wakeUp.hour,
        'wakeUpMinute': wakeUp.minute,
        'breakfastHour': breakfast.hour,
        'breakfastMinute': breakfast.minute,
        'lunchHour': lunch.hour,
        'lunchMinute': lunch.minute,
        'dinnerHour': dinner.hour,
        'dinnerMinute': dinner.minute,
        'sleepHour': sleep.hour,
        'sleepMinute': sleep.minute,
      };

  factory UserAnchors.fromMap(Map<String, dynamic> map) {
    return UserAnchors(
      wakeUp: TimeOfDay(
        hour: map['wakeUpHour'] as int? ?? 7,
        minute: map['wakeUpMinute'] as int? ?? 0,
      ),
      breakfast: TimeOfDay(
        hour: map['breakfastHour'] as int? ?? 8,
        minute: map['breakfastMinute'] as int? ?? 0,
      ),
      lunch: TimeOfDay(
        hour: map['lunchHour'] as int? ?? 13,
        minute: map['lunchMinute'] as int? ?? 0,
      ),
      dinner: TimeOfDay(
        hour: map['dinnerHour'] as int? ?? 19,
        minute: map['dinnerMinute'] as int? ?? 0,
      ),
      sleep: TimeOfDay(
        hour: map['sleepHour'] as int? ?? 22,
        minute: map['sleepMinute'] as int? ?? 0,
      ),
    );
  }

  /// Provides some default sensible anchors when none are set.
  factory UserAnchors.defaults() {
    return UserAnchors(
      wakeUp: const TimeOfDay(hour: 7, minute: 0),
      breakfast: const TimeOfDay(hour: 8, minute: 0),
      lunch: const TimeOfDay(hour: 13, minute: 0),
      dinner: const TimeOfDay(hour: 19, minute: 0),
      sleep: const TimeOfDay(hour: 22, minute: 0),
    );
  }
}
