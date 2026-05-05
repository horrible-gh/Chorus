import 'package:dio/dio.dart';

import '../models/provider_token.dart';

class ProviderTokenService {
  const ProviderTokenService(this._dio);

  final Dio _dio;

  Future<List<ProviderToken>> listTokens({required String ownerUserId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/tokens',
      queryParameters: {'owner_user_id': ownerUserId},
    );
    final items = _list(response.data?['tokens']);
    return items.map((e) => ProviderToken.fromJson(_map(e))).toList();
  }

  Future<ProviderToken> createToken(ProviderTokenDraft draft) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/tokens',
      data: draft.toCreateJson(),
    );
    return ProviderToken.fromJson(_map(response.data?['token']));
  }

  Future<ProviderToken> updateToken({
    required String tokenId,
    required ProviderTokenDraft draft,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/tokens/$tokenId',
      data: draft.toUpdateJson(),
    );
    return ProviderToken.fromJson(_map(response.data?['token']));
  }

  Future<ProviderToken> archiveToken(String tokenId) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/tokens/$tokenId',
    );
    return ProviderToken.fromJson(_map(response.data?['token']));
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static List<dynamic> _list(Object? value) {
    if (value is List) return value;
    return const [];
  }
}
