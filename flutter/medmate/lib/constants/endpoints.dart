import '../constants.dart';

abstract final class Endpoints {
  static const login           = '$kBaseUrl/api/users/login/';
  static const register        = '$kBaseUrl/api/users/register/';
  static const changePassword  = '$kBaseUrl/api/users/change-password/';
  static const logout          = '$kBaseUrl/api/users/logout/';
  static const profile         = '$kBaseUrl/api/users/profile/';
  static const prescriptions   = '$kBaseUrl/api/prescriptions/';
  static const tokenRefresh    = '$kBaseUrl/api/users/token/refresh/';
  static String prescription(int id) => '$prescriptions$id/';
  static const prescriptionUpload = '${prescriptions}upload/';
}
