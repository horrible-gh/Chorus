import 'package:dio/dio.dart';

import '../models/auth_exception.dart';
import 'auth_service.dart';

class TotpSetupResponse {
  const TotpSetupResponse({
    required this.qrImage,
    required this.recoveryCodes,
  });

  final String qrImage;
  final List<String> recoveryCodes;

  factory TotpSetupResponse.fromJson(Map<String, dynamic> json) {
    final rawCodes = json['recovery_codes'] as List<dynamic>? ?? const [];
    return TotpSetupResponse(
      qrImage: json['qr_image'] as String? ?? '',
      recoveryCodes: rawCodes.map((code) => code.toString()).toList(),
    );
  }
}

class TotpService {
  TotpService(this._dio);

  final Dio _dio;

  Future<AuthLoginResponse> verifyLogin({
    required String tempToken,
    required String code,
  }) async {
    final authService = AuthService(_dio);
    return authService.verifyTotp(tempToken: tempToken, code: code);
  }

  Future<bool> getStatus() async {
    final response = await _dio.get<Map<String, dynamic>>('/auth/totp/status');
    final data = response.data ?? const <String, dynamic>{};
    return data['enabled'] == true;
  }

  Future<TotpSetupResponse> setup() async {
    final response = await _dio.post<Map<String, dynamic>>('/auth/totp/setup');
    return TotpSetupResponse.fromJson(
      response.data ?? const <String, dynamic>{},
    );
  }

  Future<bool> activate(String code) async {
    return _successFromPost('/auth/totp/activate', {'code': code});
  }

  Future<bool> disable(String code) async {
    return _successFromPost('/auth/totp/disable', {'code': code});
  }

  Future<List<String>> regenerate(String code) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/totp/regenerate',
      data: {'code': code},
    );
    final rawCodes =
        response.data?['recovery_codes'] as List<dynamic>? ?? const [];
    return rawCodes.map((code) => code.toString()).toList();
  }

  Future<bool> _successFromPost(String path, Map<String, dynamic> data) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: data);
      return response.data?['success'] == true;
    } on DioException catch (error) {
      final detail = error.response?.data?.toString() ?? 'totp_request_failed';
      throw AuthException(
        detail,
        statusCode: error.response?.statusCode,
      );
    }
  }
}
