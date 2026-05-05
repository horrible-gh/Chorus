import 'package:dio/dio.dart';

import '../models/agent_preset.dart';

class AgentPresetService {
  const AgentPresetService(this._dio);

  final Dio _dio;

  Future<List<AgentPreset>> listPresets({
    required String ownerUserId,
    required bool includeArchived,
  }) async {
    final active = await _listByStatus(
      ownerUserId: ownerUserId,
      status: 'active',
    );
    if (!includeArchived) {
      return active;
    }

    final archived = await _listByStatus(
      ownerUserId: ownerUserId,
      status: 'archived',
    );
    return [...active, ...archived];
  }

  Future<AgentPreset> createPreset(AgentPresetDraft draft) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/agent/presets',
      data: draft.toCreateJson(),
    );
    return AgentPreset.fromJson(_map(response.data?['agent']));
  }

  Future<AgentPreset> updatePreset({
    required String agentId,
    required AgentPresetDraft draft,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/agent/presets/$agentId',
      data: draft.toUpdateJson(),
    );
    return AgentPreset.fromJson(_map(response.data?['agent']));
  }

  Future<AgentPreset> archivePreset(String agentId) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/agent/presets/$agentId',
    );
    return AgentPreset.fromJson(_map(response.data?['agent']));
  }

  Future<List<AgentPreset>> _listByStatus({
    required String ownerUserId,
    required String status,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/agent/presets',
      queryParameters: {
        'owner_user_id': ownerUserId,
        'status': status,
      },
    );
    final agents = _list(response.data?['agents']);
    return agents.map((item) => AgentPreset.fromJson(_map(item))).toList();
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  static List<dynamic> _list(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }
}
