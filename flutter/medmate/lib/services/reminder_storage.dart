import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'alarm_service.dart';

class ReminderStorage {
  ReminderStorage._();

  static const String _key          = 'scheduled_medicines';
  static const String _lastResetKey = 'last_reset_date';

  // ── Save / Load ────────────────────────────────────────────────────────────

  static Future<void> saveReminders(
    List<Map<String, dynamic>> medicines,
  ) async {
    final prefs    = await SharedPreferences.getInstance();
    final existing = await loadReminders();

    for (final newMed in medicines) {
      final alreadyExists = existing.any(
        (m) =>
            m['name']   == newMed['name'] &&
            m['hour']   == newMed['hour'] &&
            m['minute'] == newMed['minute'],
      );
      if (!alreadyExists) existing.add(newMed);
    }

    await prefs.setString(_key, jsonEncode(existing));
  }

  static Future<List<Map<String, dynamic>>> loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Mark as taken ──────────────────────────────────────────────────────────

  static Future<void> markAsTaken(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list  = await loadReminders();
    if (index >= 0 && index < list.length) {
      list[index]['taken'] = true;
      await prefs.setString(_key, jsonEncode(list));
    }
  }

  static Future<void> markAsTakenByBaseId(int baseId) async {
    final prefs   = await SharedPreferences.getInstance();
    final list    = await loadReminders();
    bool modified = false;

    for (final med in list) {
      if (med['baseId'] == baseId && med['taken'] != true) {
        med['taken'] = true;
        modified     = true;
      }
    }

    if (modified) {
      await prefs.setString(_key, jsonEncode(list));
    }
  }

  static Future<void> unmarkAsTakenByBaseId(int baseId) async {
    final prefs   = await SharedPreferences.getInstance();
    final list    = await loadReminders();
    bool modified = false;

    for (final med in list) {
      if (med['baseId'] == baseId && med['taken'] == true) {
        med['taken'] = false;
        modified     = true;
      }
    }

    if (modified) {
      await prefs.setString(_key, jsonEncode(list));
    }
  }

  // ── Daily reset ────────────────────────────────────────────────────────────

  static Future<void> resetTakenStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final list  = await loadReminders();
    for (final med in list) {
      med['taken'] = false;
    }
    await prefs.setString(_key, jsonEncode(list));
  }

  static Future<String?> getLastResetDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastResetKey);
  }

  static Future<void> setLastResetDate(String dateStr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastResetKey, dateStr);
  }

  static Future<void> checkAndResetIfNewDay() async {
    final today     = DateTime.now().toIso8601String().substring(0, 10);
    final lastReset = await getLastResetDate();

    if (lastReset != today) {
      await resetTakenStatus();
      await setLastResetDate(today);
    }
  }

  // ── Delete a single reminder ───────────────────────────────────────────────

  static Future<void> removeByBaseId(int baseId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadReminders();
    
    String? medicineName;
    for (final med in list) {
      if (med['baseId'] == baseId) {
        medicineName = med['name'];
        break;
      }
    }
    
    list.removeWhere((med) => med['baseId'] == baseId);
    await prefs.setString(_key, jsonEncode(list));

    if (medicineName != null && medicineName.isNotEmpty) {
      await AlarmService.instance.cancelAlarmsForMedicine(medicineName);
    }
  }

  // ── Clear all ──────────────────────────────────────────────────────────────

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_key),
      prefs.remove(_lastResetKey),
    ]);

    await AlarmService.instance.cancelAllAlarms();
  }
}