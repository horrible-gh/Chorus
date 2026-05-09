import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

class ApiClient {
  ApiClient() {
    final options = BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/json',
      },
    );
    dio = Dio(options);
    _refreshDio = Dio(options);
    _setupInterceptors();
  }

  late final Dio dio;
  late final Dio _refreshDio;

  String? Function()? _getAccessToken;
  FutureOr<void> Function()? _onSessionExpired;
  String? Function()? _getRefreshToken;
  FutureOr<void> Function(String accessToken, String refreshToken)?
      _onTokenRefreshed;
  bool _sessionExpiryInProgress = false;
  bool _isRefreshing = false;

  void configure({
    required String? Function() getAccessToken,
    required FutureOr<void> Function() onSessionExpired,
    String? Function()? getRefreshToken,
    FutureOr<void> Function(String accessToken, String refreshToken)?
        onTokenRefreshed,
  }) {
    _getAccessToken = getAccessToken;
    _onSessionExpired = onSessionExpired;
    _getRefreshToken = getRefreshToken;
    _onTokenRefreshed = onTokenRefreshed;
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
          if (error.response?.statusCode == 401) {
            final path = error.requestOptions.path;

            if (path.contains('/login')) {
              handler.next(error);
              return;
            }

            if (path.contains('/login/token/refresh')) {
              await _expireSessionOnce();
              handler.next(error);
              return;
            }

            if (_isRefreshing) {
              await _expireSessionOnce();
              handler.next(error);
              return;
            }

            final refreshToken = _getRefreshToken?.call();
            if (refreshToken == null || refreshToken.isEmpty) {
              await _expireSessionOnce();
              handler.next(error);
              return;
            }

            _isRefreshing = true;
            bool refreshed = false;
            Response<dynamic>? retryResponse;
            try {
              final resp = await _refreshDio.post<Map<String, dynamic>>(
                '/login/token/refresh',
                data: {'refresh_token': refreshToken},
              );
              final data = resp.data;
              final newAccessToken = data?['access_token'] as String?;
              final newRefreshToken = data?['refresh_token'] as String?;
              if (newAccessToken != null &&
                  newAccessToken.isNotEmpty &&
                  newRefreshToken != null &&
                  newRefreshToken.isNotEmpty) {
                await _onTokenRefreshed?.call(newAccessToken, newRefreshToken);
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newAccessToken';
                retryResponse = await dio.fetch(opts);
                refreshed = true;
              }
            } catch (_) {
              // refresh failed, fall through to session expiry
            } finally {
              _isRefreshing = false;
            }

            if (refreshed && retryResponse != null) {
              handler.resolve(retryResponse);
              return;
            }
            await _expireSessionOnce();
            handler.next(error);
            return;
          }

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
