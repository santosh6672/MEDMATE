import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// REMINDER STORAGE
// Saves scheduled medicines locally so the
// Dashboard can show Today's Schedule.
//
// Each entry stored as JSON:
//   {
//     "name":        "Metformin",
//     "dosage":      "500mg",
//     "frequency":   "Twice daily",
//     "hour":        8,
//     "minute":      0,
//     "baseId":      123456,
//     "doseNumber":  1,
//     "dosesPerDay": 2,
//     "foodTag":     "With food",
//     "beforeBed":   false,
//     "taken":       false
//   }
// ─────────────────────────────────────────────
class ReminderStorage {

  static const String _key = "scheduled_medicines";

  // Save new medicines — skips duplicates by name + hour + minute
  static Future<void> saveReminders(
      List<Map<String, dynamic>> medicines) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> existing = await loadReminders();

    for (var newMed in medicines) {
      bool alreadyExists = existing.any((m) =>
          m["name"] == newMed["name"] &&
          m["hour"] == newMed["hour"] &&
          m["minute"] == newMed["minute"]);
      if (!alreadyExists) existing.add(newMed);
    }

    await prefs.setString(_key, jsonEncode(existing));
  }

  // Load all saved reminders
  static Future<List<Map<String, dynamic>>> loadReminders() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? raw = prefs.getString(_key);
    if (raw == null) return [];

    List decoded = jsonDecode(raw);
    return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // Mark a single medicine as taken by its list index
  static Future<void> markAsTaken(int index) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> list = await loadReminders();

    if (index < list.length) {
      list[index]["taken"] = true;
      await prefs.setString(_key, jsonEncode(list));
    }
  }

  // Mark taken by baseId — called from notification callback in main.dart
  static Future<void> markAsTakenByBaseId(int baseId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> list = await loadReminders();

    for (var med in list) {
      if (med["baseId"] == baseId) {
        med["taken"] = true;
      }
    }
    await prefs.setString(_key, jsonEncode(list));
  }

  // Reset all taken statuses — call this at the start of a new day
  static Future<void> resetTakenStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> list = await loadReminders();
    for (var med in list) {
      med["taken"] = false;
    }
    await prefs.setString(_key, jsonEncode(list));
  }

  // Delete all saved reminders
  static Future<void> clearAll() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}