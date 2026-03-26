import 'dart:async';
import 'package:flutter/services.dart';

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  static const MethodChannel _channel = MethodChannel('alarm_channel');

  /// -------------------------------
  /// SET ALARM
  /// -------------------------------
  Future<bool> setAlarm({
    required String medicine,
    required DateTime time,
  }) async {
    try {
      if (medicine.trim().isEmpty) {
        throw ArgumentError('Medicine cannot be empty');
      }

      if (time.isBefore(DateTime.now())) {
        throw ArgumentError('Cannot set alarm in the past');
      }

      final result = await _channel.invokeMethod<bool>('setAlarm', {
        "medicine": medicine,
        "time": time.millisecondsSinceEpoch,
      });

      return result ?? false;
    } catch (e) {
      _log('setAlarm error: $e');
      return false;
    }
  }

  /// -------------------------------
  /// CANCEL ALARM
  /// -------------------------------
  Future<bool> cancelAlarm({
    required String medicine,
    required DateTime time,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('cancelAlarm', {
        "medicine": medicine,
        "time": time.millisecondsSinceEpoch,
      });

      return result ?? false;
    } catch (e) {
      _log('cancelAlarm error: $e');
      return false;
    }
  }

  /// -------------------------------
  /// CANCEL ALL ALARMS FOR MEDICINE
  /// -------------------------------
  Future<bool> cancelAlarmsForMedicine(String medicine) async {
    try {
      final result = await _channel.invokeMethod<bool>('cancelAlarmsForMedicine', {
        "medicine": medicine,
      });
      return result ?? false;
    } catch (e) {
      _log('cancelAlarmsForMedicine error: $e');
      return false;
    }
  }

  /// -------------------------------
  /// CANCEL ALL ALARMS
  /// -------------------------------
  Future<bool> cancelAllAlarms() async {
    try {
      final result = await _channel.invokeMethod<bool>('cancelAllAlarms');
      return result ?? false;
    } catch (e) {
      _log('cancelAllAlarms error: $e');
      return false;
    }
  }

  /// -------------------------------
  /// CHECK EXACT ALARM PERMISSION
  /// -------------------------------
  Future<bool> isExactAlarmPermissionGranted() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isExactAlarmPermissionGranted');
      return result ?? false;
    } catch (e) {
      _log('permission check error: $e');
      return false;
    }
  }

  /// -------------------------------
  /// REQUEST EXACT ALARM PERMISSION
  /// -------------------------------
  Future<void> requestExactAlarmPermission() async {
    try {
      await _channel.invokeMethod('requestExactAlarmPermission');
    } catch (e) {
      _log('request exact alarm error: $e');
    }
  }

  /// -------------------------------
  /// CHECK FULL SCREEN INTENT PERMISSION
  /// -------------------------------
  Future<bool> canUseFullScreenIntent() async {
    try {
      final result = await _channel.invokeMethod<bool>('canUseFullScreenIntent');
      return result ?? true;
    } catch (e) {
      _log('full screen intent check error: $e');
      return true;
    }
  }

  /// -------------------------------
  /// REQUEST FULL SCREEN INTENT PERMISSION
  /// -------------------------------
  Future<void> requestFullScreenIntent() async {
    try {
      await _channel.invokeMethod('requestFullScreenIntent');
    } catch (e) {
      _log('request full screen intent error: $e');
    }
  }

  /// -------------------------------
  /// REQUEST BATTERY OPTIMIZATION EXEMPTION
  /// -------------------------------
  Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } catch (e) {
      _log('battery exemption error: $e');
    }
  }

  /// -------------------------------
  /// CHECK BATTERY OPTIMIZATION STATUS
  /// -------------------------------
  Future<bool> isBatteryOptimizationExempt() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isBatteryOptimizationExempt');
      return result ?? false;
    } catch (e) {
      _log('battery check error: $e');
      return false;
    }
  }

  /// -------------------------------
  /// REQUEST ALL REQUIRED PERMISSIONS
  /// -------------------------------
  Future<void> checkAndRequestPermissions() async {
    final hasExactAlarm = await isExactAlarmPermissionGranted();
    if (!hasExactAlarm) {
      await requestExactAlarmPermission();
    }

    final hasFullScreen = await canUseFullScreenIntent();
    if (!hasFullScreen) {
      await requestFullScreenIntent();
    }
  }

  /// -------------------------------
  /// DEBUG LOGGER
  /// -------------------------------
  void _log(String msg) {
    // ignore: avoid_print
    print('[AlarmService] $msg');
  }
}