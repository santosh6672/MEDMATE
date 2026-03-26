import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_anchors.dart';

class AnchorStorage {
  AnchorStorage._();

  static const String _key = 'user_anchors';

  static Future<void> saveAnchors(UserAnchors anchors) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(anchors.toMap()));
  }

  static Future<UserAnchors?> loadAnchors() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return UserAnchors.fromMap(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasAnchors() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key);
  }

  static Future<void> clearAnchors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
