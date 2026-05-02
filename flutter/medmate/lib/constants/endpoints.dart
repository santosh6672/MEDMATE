import '../constants.dart';

abstract final class Endpoints {
  // ── AWS API Gateway ─────────────────────────────────────

  // Health check
  static const health = '$kBaseUrl/health';

  // Prescriptions
  static const prescriptions = '$kBaseUrl/api/prescriptions/';

  // Single prescription (GET, DELETE)
  static String prescription(String id) =>
      '$kBaseUrl/api/prescriptions/$id/';


  // ── Supabase Auth ──────────────────────────────────────

  // Login (email + password)
  static const login =
      '$kSupabaseUrl/auth/v1/token?grant_type=password';

  // Refresh token
  static const refreshToken =
      '$kSupabaseUrl/auth/v1/token?grant_type=refresh_token';

  // Signup
  static const signup =
      '$kSupabaseUrl/auth/v1/signup';

  // Logout
  static const logout =
      '$kSupabaseUrl/auth/v1/logout';

  // Update user (password, metadata)
  static const updateUser =
      '$kSupabaseUrl/auth/v1/user';
}
