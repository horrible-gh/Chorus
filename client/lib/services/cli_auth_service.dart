import 'package:dio/dio.dart';

import '../models/cli_auth.dart';

class CliAuthService {
  const CliAuthService(this._dio);

  final Dio _dio;

  Future<List<CliProviderStatus>> getCliStatus() async {
    final response = await _dio.get<List<dynamic>>('/auth/cli-status');
    final items = response.data ?? [];
    return items
        .map((e) => CliProviderStatus.fromJson(_map(e)))
        .toList();
  }

  Future<CliLoginResponse> cliLogin(String provider) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/cli-login/$provider',
    );
    return CliLoginResponse.fromJson(_map(response.data));
  }

  Future<CliLogoutResponse> cliLogout(String provider) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/cli-logout/$provider',
    );
    return CliLogoutResponse.fromJson(_map(response.data));
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }
}
