import 'package:dio/dio.dart';

import '../models/auth_exception.dart';
import '../models/settings.dart';

class SettingsService {
  const SettingsService(this._dio);

  final Dio _dio;

  Future<UserProfile> getProfile() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/settings/profile');
    return UserProfile.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.put<void>(
        '/settings/password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
    } on DioException catch (error) {
      throw _toAuthException(error);
    }
  }

  Future<TotpSetupData> setupTotp() async {
    try {
      final response =
          await _dio.post<Map<String, dynamic>>('/settings/totp/setup');
      return TotpSetupData.fromJson(
          response.data ?? const <String, dynamic>{});
    } on DioException catch (error) {
      throw _toAuthException(error);
    }
  }

  Future<bool> activateTotp(String code) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/settings/totp/activate',
        data: {'code': code},
      );
      return response.data?['ok'] == true;
    } on DioException catch (error) {
      throw _toAuthException(error);
    }
  }

  Future<void> disableTotp(String code) async {
    try {
      await _dio.delete<void>(
        '/settings/totp',
        data: {'code': code},
      );
    } on DioException catch (error) {
      throw _toAuthException(error);
    }
  }

  AuthException _toAuthException(DioException error) {
    final data = error.response?.data;
    String detail = 'unknown_error';

    if (data is Map<String, dynamic>) {
      detail = data['detail']?.toString() ??
          data['message']?.toString() ??
          detail;
    } else if (data is String && data.isNotEmpty) {
      detail = data;
    }

    return AuthException(
      detail,
      statusCode: error.response?.statusCode,
    );
  }
}
