import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/auth_exception.dart';
import '../models/user.dart';

class AuthLoginResponse {
  const AuthLoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });

  final String accessToken;
  final String tokenType;
  final User user;

  factory AuthLoginResponse.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final userJson = rawUser is Map<String, dynamic>
        ? rawUser
        : rawUser is Map
            ? Map<String, dynamic>.from(rawUser)
            : <String, dynamic>{};

    return AuthLoginResponse(
      accessToken: json['access_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'bearer',
      user: User.fromJson(userJson),
    );
  }
}

class AuthLoginOutcome {
  const AuthLoginOutcome._({
    this.session,
    this.tempToken,
    this.maintenanceMessage,
  });

  final AuthLoginResponse? session;
  final String? tempToken;
  final String? maintenanceMessage;

  bool get isSuccess => session != null;
  bool get isTotpRequired => tempToken != null && tempToken!.isNotEmpty;
  bool get isMaintenance => maintenanceMessage != null;

  factory AuthLoginOutcome.success(AuthLoginResponse session) {
    return AuthLoginOutcome._(session: session);
  }

  factory AuthLoginOutcome.totpRequired(String tempToken) {
    return AuthLoginOutcome._(tempToken: tempToken);
  }

  factory AuthLoginOutcome.maintenance(String message) {
    return AuthLoginOutcome._(maintenanceMessage: message);
  }
}

class AuthService {
  AuthService(this._dio);

  final Dio _dio;

  Future<AuthLoginOutcome> login({
    required String username,
    required String password,
    String locale = AppConfig.defaultLocale,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/login',
        data: {
          'username': username,
          'password': password,
          'locale': locale,
        },
      );
      final data = response.data ?? const <String, dynamic>{};

      if (data['maintenance'] == true) {
        return AuthLoginOutcome.maintenance(
          data['message'] as String? ?? 'Server maintenance in progress.',
        );
      }

      if (data['totp_required'] == true) {
        return AuthLoginOutcome.totpRequired(
          data['temp_token'] as String? ?? '',
        );
      }

      return AuthLoginOutcome.success(AuthLoginResponse.fromJson(data));
    } on DioException catch (error) {
      debugPrint('[AuthService.login] ${error.response?.statusCode}');
      throw _toAuthException(error);
    }
  }

  Future<AuthLoginResponse> verifyTotp({
    required String tempToken,
    required String code,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/login/totp/verify',
        data: {
          'temp_token': tempToken,
          'code': code,
        },
      );
      return AuthLoginResponse.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on DioException catch (error) {
      debugPrint('[AuthService.verifyTotp] ${error.response?.statusCode}');
      throw _toAuthException(error);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post<void>('/logout');
    } on DioException catch (error) {
      throw _toAuthException(error);
    }
  }

  AuthException _toAuthException(DioException error) {
    final data = error.response?.data;
    String detail = 'unknown_error';
    String? code;

    if (data is Map<String, dynamic>) {
      final nested = data['error'];
      if (nested is Map<String, dynamic>) {
        code = nested['code']?.toString();
        detail = nested['message']?.toString() ?? code ?? detail;
      } else {
        code = data['code']?.toString();
        detail = data['detail']?.toString() ??
            data['message']?.toString() ??
            code ??
            detail;
      }
    } else if (data is String && data.isNotEmpty) {
      detail = data;
    }

    return AuthException(
      detail,
      statusCode: error.response?.statusCode,
      code: code,
    );
  }
}
