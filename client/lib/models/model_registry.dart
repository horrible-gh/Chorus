import 'dart:convert';

class ModelRegistry {
  const ModelRegistry({
    required this.modelId,
    required this.runner,
    required this.modelName,
    required this.grade,
    required this.isActive,
    required this.isDefault,
    required this.estimatedCostRank,
    required this.priority,
    this.maxContextTokens,
    this.providerOptionsJson,
    required this.createdAt,
    required this.updatedAt,
  });

  final String modelId;
  final String runner;
  final String modelName;
  final String grade;
  final bool isActive;
  final bool isDefault;
  final int estimatedCostRank;
  final int priority;
  final int? maxContextTokens;
  final Map<String, dynamic>? providerOptionsJson;
  final String createdAt;
  final String updatedAt;

  factory ModelRegistry.fromJson(Map<String, dynamic> json) {
    return ModelRegistry(
      modelId: _str(json['model_id']),
      runner: _str(json['runner']),
      modelName: _str(json['model_name']),
      grade: _str(json['grade']),
      isActive: _bool(json['is_active']),
      isDefault: _bool(json['is_default']),
      estimatedCostRank: _int(json['estimated_cost_rank']),
      priority: _int(json['priority']),
      maxContextTokens: _nullableInt(json['max_context_tokens']),
      providerOptionsJson: _nullableMap(json['provider_options_json']),
      createdAt: _str(json['created_at']),
      updatedAt: _str(json['updated_at']),
    );
  }
}

class ModelRegistryCreateRequest {
  const ModelRegistryCreateRequest({
    required this.runner,
    required this.modelName,
    required this.grade,
    this.isDefault = false,
    required this.estimatedCostRank,
    this.priority = 0,
    this.maxContextTokens,
    this.providerOptionsJson,
  });

  final String runner;
  final String modelName;
  final String grade;
  final bool isDefault;
  final int estimatedCostRank;
  final int priority;
  final int? maxContextTokens;
  final Map<String, dynamic>? providerOptionsJson;

  Map<String, dynamic> toJson() {
    return {
      'runner': runner,
      'model_name': modelName,
      'grade': grade,
      'is_default': isDefault,
      'estimated_cost_rank': estimatedCostRank,
      'priority': priority,
      if (maxContextTokens != null) 'max_context_tokens': maxContextTokens,
      'provider_options_json': providerOptionsJson,
    };
  }
}

class ModelRegistryUpdateRequest {
  const ModelRegistryUpdateRequest({
    this.modelName,
    this.grade,
    this.isActive,
    this.isDefault,
    this.estimatedCostRank,
    this.priority,
    this.maxContextTokens,
    this.providerOptionsJson,
    this.clearProviderOptions = false,
  });

  final String? modelName;
  final String? grade;
  final bool? isActive;
  final bool? isDefault;
  final int? estimatedCostRank;
  final int? priority;
  final int? maxContextTokens;
  final Map<String, dynamic>? providerOptionsJson;
  final bool clearProviderOptions;

  Map<String, dynamic> toJson() {
    return {
      if (modelName != null) 'model_name': modelName,
      if (grade != null) 'grade': grade,
      if (isActive != null) 'is_active': isActive,
      if (isDefault != null) 'is_default': isDefault,
      if (estimatedCostRank != null) 'estimated_cost_rank': estimatedCostRank,
      if (priority != null) 'priority': priority,
      if (maxContextTokens != null) 'max_context_tokens': maxContextTokens,
      if (clearProviderOptions || providerOptionsJson != null)
        'provider_options_json': providerOptionsJson,
    };
  }
}

class ModelRegistryUpdateResult {
  const ModelRegistryUpdateResult({required this.model, this.warning});

  final ModelRegistry model;
  final String? warning;
}

String _str(Object? value, {String fallback = ''}) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return fallback;
  return text;
}

bool _bool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value?.toString().toLowerCase() == 'true';
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value?.toString() ?? '');
  return parsed ?? fallback;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

Map<String, dynamic>? _nullableMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
  }
  return null;
}
