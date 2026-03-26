import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

class ApiService {
  ApiService._();

  static const String _keyAccess  = 'access';
  static const String _keyRefresh = 'refresh';

  // Headers that every request needs (no auth, no content-type).
  static const Map<String, String> _baseHeaders = {
    'ngrok-skip-browser-warning': 'true',
  };

  static const Duration _timeout = Duration(seconds: 30);

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

  /// Builds auth headers.
  /// Set [includeContentType] to true for requests that send a JSON body.
  static Future<Map<String, String>> _authHeaders({
    bool includeContentType = false,
  }) async {
    final token = await getAccessToken();
    return {
      ..._baseHeaders,
      if (includeContentType) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    };
  }

  // ── Token refresh ──────────────────────────────────────────────────────────

  /// Attempts to exchange the stored refresh token for a new access token.
  /// Returns `true` on success, `false` on any failure.
  ///
  /// When ROTATE_REFRESH_TOKENS=True is enabled on the Django backend,
  /// the response also contains a new refresh token — we save both so the
  /// next refresh call doesn't 401 with a blacklisted token.
  static Future<bool> refreshToken() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final response = await http
          .post(
            Uri.parse('$kBaseUrl/api/users/token/refresh/'),
            headers: {
              ..._baseHeaders,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data      = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccess = data['access'] as String?;
        if (newAccess == null || newAccess.isEmpty) return false;

        final prefs = await SharedPreferences.getInstance();
        // Always save the new access token.
        await prefs.setString(_keyAccess, newAccess);
        // If the backend rotated the refresh token, save that too.
        // Without this, the next refresh will 401 with a blacklisted token.
        final newRefresh = data['refresh'] as String?;
        if (newRefresh != null && newRefresh.isNotEmpty) {
          await prefs.setString(_keyRefresh, newRefresh);
        }
        return true;
      }

      return false;
    } on SocketException {
      return false;
    } on http.ClientException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Public POST (no auth header) ──────────────────────────────────────────

  /// Sends a POST request WITHOUT an Authorization header.
  /// Use this for public endpoints: /login/, /register/, /token/refresh/.
  /// Using postWithAuth on these endpoints attaches a stale/empty Bearer
  /// token which Django rejects before the view runs → 401.
  static Future<http.Response> postPublic(
    String url,
    Map<String, dynamic> body,
  ) async {
    return http
        .post(
          Uri.parse(url),
          headers: {
            ..._baseHeaders,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
  }

  // ── GET with auth + auto-refresh ───────────────────────────────────────────

  /// Sends an authenticated GET request.
  /// If the server returns 401 the token is refreshed once and the call
  /// is retried automatically.
  static Future<http.Response> getWithAuth(String url) async {
    var headers  = await _authHeaders();
    var response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(_timeout);

    if (response.statusCode == 401 && await refreshToken()) {
      headers  = await _authHeaders();
      response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(_timeout);
    }

    return response;
  }

  // ── POST with auth + auto-refresh ──────────────────────────────────────────

  /// Sends an authenticated POST request with a JSON [body].
  /// If the server returns 401 the token is refreshed once and the call
  /// is retried automatically.
  static Future<http.Response> postWithAuth(
    String url,
    Map<String, dynamic> body,
  ) async {
    var headers  = await _authHeaders(includeContentType: true);
    var response = await http
        .post(
          Uri.parse(url),
          headers: headers,
          body:    jsonEncode(body),
        )
        .timeout(_timeout);

    if (response.statusCode == 401 && await refreshToken()) {
      headers  = await _authHeaders(includeContentType: true);
      response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body:    jsonEncode(body),
          )
          .timeout(_timeout);
    }

    return response;
  }

  // ── PATCH with auth + auto-refresh ─────────────────────────────────────────

  /// Sends an authenticated PATCH request with a JSON [body].
  static Future<http.Response> patchWithAuth(
    String url,
    Map<String, dynamic> body,
  ) async {
    var headers  = await _authHeaders(includeContentType: true);
    var response = await http
        .patch(
          Uri.parse(url),
          headers: headers,
          body:    jsonEncode(body),
        )
        .timeout(_timeout);

    if (response.statusCode == 401 && await refreshToken()) {
      headers  = await _authHeaders(includeContentType: true);
      response = await http
          .patch(
            Uri.parse(url),
            headers: headers,
            body:    jsonEncode(body),
          )
          .timeout(_timeout);
    }

    return response;
  }

  // ── DELETE with auth + auto-refresh ────────────────────────────────────────

  /// Sends an authenticated DELETE request.
  static Future<http.Response> deleteWithAuth(String url) async {
    var headers  = await _authHeaders();
    var response = await http
        .delete(Uri.parse(url), headers: headers)
        .timeout(_timeout);

    if (response.statusCode == 401 && await refreshToken()) {
      headers  = await _authHeaders();
      response = await http
          .delete(Uri.parse(url), headers: headers)
          .timeout(_timeout);
    }

    return response;
  }
}