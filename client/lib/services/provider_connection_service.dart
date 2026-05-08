import 'package:dio/dio.dart';

import '../models/provider_connection.dart';

class ProviderConnectionService {
  const ProviderConnectionService(this._dio);

  final Dio _dio;

  Future<List<ProviderConnectionStatus>> getProvidersStatus() async {
    final response = await _dio.get<List<dynamic>>('/auth/providers/status');
    final items = response.data ?? [];
    return items.map((e) => ProviderConnectionStatus.fromJson(_map(e))).toList();
  }

  Future<void> setExecutablePath(String provider, String path) async {
    await _dio.patch<Map<String, dynamic>>(
      '/auth/providers/$provider/executable-path',
      data: {'executable_path': path},
    );
  }

  Future<ProviderConnectionStatus> verifyProvider(String provider) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/providers/$provider/verify',
    );
    return ProviderConnectionStatus.fromJson(_map(response.data));
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }
}
