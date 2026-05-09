import 'package:dio/dio.dart';

import '../models/model_registry.dart';

class ModelRegistryService {
  const ModelRegistryService(this._dio);

  final Dio _dio;

  Future<List<ModelRegistry>> listModels({
    String? runner,
    bool activeOnly = false,
  }) async {
    final response = await _dio.get<dynamic>(
      '/models',
      queryParameters: {
        if (runner != null) 'runner': runner,
        'active_only': activeOnly,
      },
    );
    final items = _list(response.data);
    return items.map((e) => ModelRegistry.fromJson(_map(e))).toList();
  }

  Future<ModelRegistry> createModel(ModelRegistryCreateRequest request) async {
    final response = await _dio.post<dynamic>(
      '/models',
      data: request.toJson(),
    );
    return ModelRegistry.fromJson(_map(response.data));
  }

  Future<ModelRegistryUpdateResult> updateModel({
    required String modelId,
    required ModelRegistryUpdateRequest request,
  }) async {
    final response = await _dio.patch<dynamic>(
      '/models/$modelId',
      data: request.toJson(),
    );
    final data = _map(response.data);
    return ModelRegistryUpdateResult(
      model: ModelRegistry.fromJson(data),
      warning: data['warning'] as String?,
    );
  }

  Future<void> deleteModel(String modelId) async {
    await _dio.delete<dynamic>('/models/$modelId');
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
