import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

class ApiClient {
  ApiClient() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: const {
          'Accept': 'application/json',
        },
      ),
    );
    _setupInterceptors();
  }

  late final Dio dio;

  String? Function()? _getAccessToken;
  FutureOr<void> Function()? _onSessionExpired;
  bool _sessionExpiryInProgress = false;

  void configure({
    required String? Function() getAccessToken,
    required FutureOr<void> Function() onSessionExpired,
  }) {
    _getAccessToken = getAccessToken;
    _onSessionExpired = onSessionExpired;
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _getAccessToken?.call();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (_shouldExpireSession(error)) {
            await _expireSessionOnce();
          }
          handler.next(error);
        },
      ),
    );
  }

  bool _shouldExpireSession(DioException error) {
    final path = error.requestOptions.path;
    if (path.contains('/login')) {
      return false;
    }

    if (error.response?.statusCode == 401) {
      return true;
    }

    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final code = data['error'] is Map<String, dynamic>
          ? (data['error'] as Map<String, dynamic>)['code']
          : data['code'];
      return code == 'AUTH_TOKEN_EXPIRED';
    }

    return false;
  }

  Future<void> _expireSessionOnce() async {
    if (_sessionExpiryInProgress) {
      return;
    }
    _sessionExpiryInProgress = true;
    try {
      await _onSessionExpired?.call();
    } finally {
      _sessionExpiryInProgress = false;
    }
  }
}
