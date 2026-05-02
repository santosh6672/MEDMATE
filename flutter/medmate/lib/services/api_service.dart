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

  static const Duration _timeout     = Duration(seconds: 30);
  static const Duration _authTimeout = Duration(seconds: 15);

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

  /// Standard headers for all AWS API Gateway requests.
  static Future<Map<String, String>> _authHeaders({
    bool includeContentType = false,
  }) async {
    final token = await getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    };
  }

  /// Headers for Supabase auth endpoints.
  static Map<String, String> get _supabaseHeaders => {
    'Content-Type': 'application/json',
    'apikey': kSupabaseAnonKey,
  };

  // ── Supabase Auth ──────────────────────────────────────────────────────────

  /// Login with email + password via Supabase.
  /// Returns the full response body map on success, null on failure.
  static Future<Map<String, dynamic>?> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '$kSupabaseUrl/auth/v1/token?grant_type=password',
            ),
            headers: _supabaseHeaders,
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_authTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final access  = data['access_token']  as String?;
        final refresh = data['refresh_token'] as String?;
        if (access != null && refresh != null) {
          await saveTokens(access, refresh);
          return data;
        }
      }
      return null;
    } on SocketException  { return null; }
      on TimeoutException { return null; }
      catch (_)           { return null; }
  }

  /// Sign up a new user via Supabase.
  static Future<Map<String, dynamic>?> signUp(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$kSupabaseUrl/auth/v1/signup'),
            headers: _supabaseHeaders,
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_authTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } on SocketException  { return null; }
      on TimeoutException { return null; }
      catch (_)           { return null; }
  }

  /// Refreshes the Supabase access token using the stored refresh token.
  /// Returns true on success, false on any failure.
  static Future<bool> refreshToken() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final response = await http
          .post(
            Uri.parse(
              '$kSupabaseUrl/auth/v1/token?grant_type=refresh_token',
            ),
            headers: _supabaseHeaders,
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(_authTimeout);

      if (response.statusCode == 200) {
        final data      = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccess  = data['access_token']  as String?;
        final newRefresh = data['refresh_token'] as String?;
        if (newAccess == null || newAccess.isEmpty) return false;
        await saveTokens(newAccess, newRefresh ?? refresh);
        return true;
      }
      return false;
    } on SocketException  { return false; }
      on TimeoutException { return false; }
      catch (_)           { return false; }
  }

  /// Logs out the current user and clears stored tokens.
  static Future<void> logout() async {
    final token = await getAccessToken();
    if (token != null) {
      try {
        await http
            .post(
              Uri.parse('$kSupabaseUrl/auth/v1/logout'),
              headers: {
                ..._supabaseHeaders,
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(_authTimeout);
      } catch (_) {}
    }
    await clearTokens();
  }

  // ── AWS API Gateway — Prescriptions ───────────────────────────────────────

  /// GET /health — checks if the backend is alive.
  static Future<bool> healthCheck() async {
    try {
      final response = await http
          .get(Uri.parse('$kBaseUrl/health'))
          .timeout(_authTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// POST /api/prescriptions/ — upload a prescription image (multipart).
  /// [imageFile] is the image picked from the camera/gallery.
  static Future<http.Response> uploadPrescription(File imageFile) async {
    final token   = await getAccessToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$kBaseUrl/api/prescriptions/'),
    );

    request.headers.addAll({
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    });

    request.files.add(
      await http.MultipartFile.fromPath('file', imageFile.path),
    );

    final streamed  = await request.send().timeout(_timeout);
    final response  = await http.Response.fromStream(streamed);

    // If 401, refresh and retry once.
    if (response.statusCode == 401 && await refreshToken()) {
      final newToken  = await getAccessToken();
      final retryReq  = http.MultipartRequest(
        'POST',
        Uri.parse('$kBaseUrl/api/prescriptions/'),
      );
      retryReq.headers.addAll({
        if (newToken != null) 'Authorization': 'Bearer $newToken',
      });
      retryReq.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );
      final retryStreamed = await retryReq.send().timeout(_timeout);
      return http.Response.fromStream(retryStreamed);
    }

    return response;
  }

  /// GET /api/prescriptions/ — fetch all prescriptions for the current user.
  static Future<http.Response> getPrescriptions() async {
    return getWithAuth('$kBaseUrl/api/prescriptions/');
  }

  /// GET /api/prescriptions/{id} — fetch a single prescription by ID.
  static Future<http.Response> getPrescription(String id) async {
    return getWithAuth('$kBaseUrl/api/prescriptions/$id');
  }

  /// DELETE /api/prescriptions/{id} — delete a prescription by ID.
  static Future<http.Response> deletePrescription(String id) async {
    return deleteWithAuth('$kBaseUrl/api/prescriptions/$id');
  }

  // ── Core HTTP helpers with auth + auto-refresh ────────────────────────────

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

  static Future<http.Response> postWithAuth(
    String url,
    Map<String, dynamic> body,
  ) async {
    var headers  = await _authHeaders(includeContentType: true);
    var response = await http
        .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(_timeout);

    if (response.statusCode == 401 && await refreshToken()) {
      headers  = await _authHeaders(includeContentType: true);
      response = await http
          .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
    }
    return response;
  }

  static Future<http.Response> patchWithAuth(
    String url,
    Map<String, dynamic> body,
  ) async {
    var headers  = await _authHeaders(includeContentType: true);
    var response = await http
        .patch(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(_timeout);

    if (response.statusCode == 401 && await refreshToken()) {
      headers  = await _authHeaders(includeContentType: true);
      response = await http
          .patch(Uri.parse(url), headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
    }
    return response;
  }

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
