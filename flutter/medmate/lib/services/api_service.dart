import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

class ApiService {
  ApiService._();

  static const String _keyAccess  = 'access';
  static const String _keyRefresh = 'refresh';

  static const Map<String, String> _baseHeaders = {
    'Content-Type':              'application/json',
    'ngrok-skip-browser-warning': 'true',
  };

  // ── Token storage ──────────────────────────────────────────────────────────

  static Future<void> saveTokens(String access, String refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_keyAccess,  access),
      prefs.setString(_keyRefresh, refresh),
    ]);
  }

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccess);
  }

  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRefresh);
  }

  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyAccess),
      prefs.remove(_keyRefresh),
    ]);
  }

  // ── Headers ────────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders({
    bool includeContentType = false,
  }) async {
    final token = await getAccessToken();
    return {
      ..._baseHeaders,
      if (!includeContentType) ...{'Content-Type': ''},
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    }..removeWhere((_, v) => v.isEmpty);
  }

  // ── Token refresh ──────────────────────────────────────────────────────────

  static Future<bool> refreshToken() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final response = await http
          .post(
            Uri.parse('$kBaseUrl/api/users/token/refresh/'),
            headers: _baseHeaders,
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccess = data['access'] as String?;
        if (newAccess == null || newAccess.isEmpty) return false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyAccess, newAccess);
        return true;
      }
    } on SocketException {
      return false;
    } on http.ClientException {
      return false;
    } catch (_) {
      return false;
    }

    return false;
  }

  // ── GET with auth + auto-refresh ───────────────────────────────────────────

  static Future<http.Response> getWithAuth(String url) async {
    var headers  = await _authHeaders();
    var response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401 && await refreshToken()) {
      headers  = await _authHeaders();
      response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));
    }

    return response;
  }

  // ── POST with auth + auto-refresh ──────────────────────────────────────────

  static Future<http.Response> postWithAuth(
    String url,
    Map<String, dynamic> body,
  ) async {
    var headers  = await _authHeaders(includeContentType: true);
    var response = await http
        .post(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401 && await refreshToken()) {
      headers  = await _authHeaders(includeContentType: true);
      response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    }

    return response;
  }
}