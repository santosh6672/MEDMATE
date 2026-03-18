import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

// ─────────────────────────────────────────────
// API SERVICE
// All 9 Django URLs used in this app:
//
//  1. POST  /api/users/register/
//  2. POST  /api/users/login/
//  3. GET   /api/users/profile/
//  4. POST  /api/users/change-password/
//  5. POST  /api/users/logout/
//  6. POST  /api/users/token/refresh/   ← auto called on 401
//  7. POST  /api/prescriptions/upload/
//  8. GET   /api/prescriptions/
//  9. GET   /api/prescriptions/<pk>/
// ─────────────────────────────────────────────
class ApiService {

  // Save both tokens after login / register
  static Future<void> saveTokens(String access, String refresh) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("access", access);
    await prefs.setString("refresh", refresh);
  }

  // Read access token from device storage
  static Future<String?> getAccessToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString("access");
  }

  // Clear both tokens on logout
  static Future<void> clearTokens() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove("access");
    await prefs.remove("refresh");
  }

  // ── URL 6: POST /api/users/token/refresh/ ──
  // Called automatically when any request returns 401.
  // Gets a new access token using the saved refresh token.
  static Future<bool> refreshToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? refresh = prefs.getString("refresh");
    if (refresh == null) return false;

    try {
      final response = await http.post(
        Uri.parse("$kBaseUrl/api/users/token/refresh/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"refresh": refresh}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await prefs.setString("access", data["access"]);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // Build Authorization header from saved token
  static Future<Map<String, String>> authHeader() async {
    String? token = await getAccessToken();
    return {"Authorization": "Bearer $token"};
  }

  // GET with auto token refresh on 401
  static Future<http.Response> getWithAuth(String url) async {
    var headers = await authHeader();
    var response = await http.get(Uri.parse(url), headers: headers);

    if (response.statusCode == 401) {
      bool refreshed = await refreshToken();
      if (refreshed) {
        headers = await authHeader();
        response = await http.get(Uri.parse(url), headers: headers);
      }
    }
    return response;
  }

  // POST with auto token refresh on 401
  static Future<http.Response> postWithAuth(
      String url, Map<String, dynamic> body) async {
    var headers = await authHeader();
    headers["Content-Type"] = "application/json";

    var response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 401) {
      bool refreshed = await refreshToken();
      if (refreshed) {
        headers = await authHeader();
        response = await http.post(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(body),
        );
      }
    }
    return response;
  }
}