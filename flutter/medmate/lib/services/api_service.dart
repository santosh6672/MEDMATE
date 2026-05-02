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

  static Map<String, String> get _supabaseHeaders => {
    'Content-Type': 'application/json',
    'apikey': kSupabaseAnonKey,
  };

  // ── Supabase Auth ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$kSupabaseUrl/auth/v1/token?grant_type=password'),
            headers: _supabaseHeaders,
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_authTimeout);

      if (response.statusCode == 200) {
        final data    = jsonDecode(response.body) as Map<String, dynamic>;
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

  /// [username] is stored in Supabase user_metadata so profile can read it.
  static Future<Map<String, dynamic>?> signUp(
    String email,
    String password, {
    String username = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$kSupabaseUrl/auth/v1/signup'),
            headers: _supabaseHeaders,
            body: jsonEncode({
              'email':    email,
              'password': password,
              'data':     {'username': username},
            }),
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

  static Future<bool> refreshToken() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    try {
      final response = await http
          .post(
            Uri.parse('$kSupabaseUrl/auth/v1/token?grant_type=refresh_token'),
            headers: _supabaseHeaders,
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(_authTimeout);

      if (response.statusCode == 200) {
        final data       = jsonDecode(response.body) as Map<String, dynamic>;
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

  static Future<void> logout() async {
    final token = await getAccessToken();
    if (token != null && token.isNotEmpty) {
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

  // ── AWS API Gateway — Health ───────────────────────────────────────────────

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

  // ── AWS API Gateway — Prescriptions ───────────────────────────────────────

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

    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 401 && await refreshToken()) {
      final newToken   = await getAccessToken();
      final retryReq   = http.MultipartRequest(
        'POST',
        Uri.parse('$kBaseUrl/api/prescriptions/'),
      );
      retryReq.headers.addAll({
        if (newToken != null && newToken.isNotEmpty)
          'Authorization': 'Bearer $newToken',
      });
      retryReq.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );
      final retryStreamed = await retryReq.send().timeout(_timeout);
      return http.Response.fromStream(retryStreamed);
    }

    return response;
  }

  static Future<http.Response> getPrescriptions() =>
      getWithAuth('$kBaseUrl/api/prescriptions/');

  static Future<http.Response> getPrescription(String id) =>
      getWithAuth('$kBaseUrl/api/prescriptions/$id');

  static Future<http.Response> deletePrescription(String id) =>
      deleteWithAuth('$kBaseUrl/api/prescriptions/$id');

  // ── Core HTTP helpers ──────────────────────────────────────────────────────

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
    var headers  = await _authHeaders();
    var response = await http
        .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(_timeout);
    if (response.statusCode == 401 && await refreshToken()) {
      headers  = await _authHeaders();
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
    var headers  = await _authHeaders();
    var response = await http
        .patch(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(_timeout);
    if (response.statusCode == 401 && await refreshToken()) {
      headers  = await _authHeaders();
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
