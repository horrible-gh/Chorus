import 'dart:convert';

class AgentPreset {
  const AgentPreset({
    required this.agentId,
    required this.ownerUserId,
    required this.displayName,
    required this.roleName,
    required this.defaultRunner,
    required this.defaultModel,
    required this.defaultGrade,
    required this.systemPrompt,
    required this.settings,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.pinnedContext,
  });

  final String agentId;
  final String ownerUserId;
  final String displayName;
  final String roleName;
  final String? description;
  final String defaultRunner;
  final String defaultModel;
  final String defaultGrade;
  final String systemPrompt;
  final String? pinnedContext;
  final AgentPresetSettings settings;
  final String status;
  final String createdAt;
  final String updatedAt;

  bool get isArchived => status == 'archived';

  factory AgentPreset.fromJson(Map<String, dynamic> json) {
    return AgentPreset(
      agentId: _string(json['agent_id']),
      ownerUserId: _string(json['owner_user_id']),
      displayName: _string(json['display_name']),
      roleName: _string(json['role_name']),
      description: _nullableString(json['description']),
      defaultRunner: _string(json['default_runner'], fallback: 'copilot'),
      defaultModel: _string(json['default_model'], fallback: 'gpt-5-mini'),
      defaultGrade: _string(json['default_grade'], fallback: '0급'),
      systemPrompt: _string(json['system_prompt']),
      pinnedContext: _nullableString(json['pinned_context']),
      settings: AgentPresetSettings.fromJson(_map(json['settings_json'])),
      status: _string(json['status'], fallback: 'active'),
      createdAt: _string(json['created_at']),
      updatedAt: _string(json['updated_at']),
    );
  }
}

class AgentPresetSettings {
  const AgentPresetSettings({
    this.providerTokenId,
    this.useAllowAll = false,
    this.codexMode = 'never',
    this.allowedTools = '',
    this.approvalMode = 'default',
    this.workDir = '',
    this.session = 'none',
  });

  final String? providerTokenId;
  final bool useAllowAll;
  final String codexMode;
  final String allowedTools;
  final String approvalMode;
  final String workDir;
  final String session;

  factory AgentPresetSettings.fromJson(Map<String, dynamic> json) {
    return AgentPresetSettings(
      providerTokenId: _nullableString(json['provider_token_id']),
      useAllowAll: _bool(json['use_allow_all']),
      codexMode: _string(json['codex_mode'], fallback: 'never'),
      allowedTools: _string(json['allowed_tools']),
      approvalMode: _string(json['approval_mode'], fallback: 'default'),
      workDir: _string(json['work_dir']),
      session: _string(json['session'], fallback: 'none'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider_token_id': providerTokenId,
      'use_allow_all': useAllowAll,
      'codex_mode': codexMode,
      'allowed_tools': allowedTools,
      'approval_mode': approvalMode,
      'work_dir': workDir,
      'session': session,
    };
  }
}

class AgentPresetDraft {
  const AgentPresetDraft({
    required this.ownerUserId,
    required this.displayName,
    required this.roleName,
    required this.description,
    required this.defaultRunner,
    required this.defaultModel,
    required this.defaultGrade,
    required this.systemPrompt,
    required this.pinnedContext,
    required this.settings,
  });

  final String ownerUserId;
  final String displayName;
  final String roleName;
  final String description;
  final String defaultRunner;
  final String defaultModel;
  final String defaultGrade;
  final String systemPrompt;
  final String pinnedContext;
  final AgentPresetSettings settings;

  factory AgentPresetDraft.fromPreset(AgentPreset preset) {
    return AgentPresetDraft(
      ownerUserId: preset.ownerUserId,
      displayName: preset.displayName,
      roleName: preset.roleName,
      description: preset.description ?? '',
      defaultRunner: preset.defaultRunner,
      defaultModel: preset.defaultModel,
      defaultGrade: preset.defaultGrade,
      systemPrompt: preset.systemPrompt,
      pinnedContext: preset.pinnedContext ?? '',
      settings: preset.settings,
    );
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'owner_user_id': ownerUserId,
      ...toUpdateJson(),
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'display_name': displayName,
      'role_name': roleName,
      'description': description,
      'default_runner': defaultRunner,
      'default_model': defaultModel,
      'default_grade': defaultGrade,
      'system_prompt': systemPrompt,
      'pinned_context': pinnedContext.isEmpty ? null : pinnedContext,
      'settings_json': settings.toJson(),
    };
  }
}

class AgentModelOption {
  const AgentModelOption({
    required this.runner,
    required this.modelName,
    required this.grade,
    this.isDefault = false,
  });

  final String runner;
  final String modelName;
  final String grade;
  final bool isDefault;
}

const agentModelOptions = [
  AgentModelOption(
    runner: 'copilot',
    modelName: 'gpt-5-mini',
    grade: '0급',
    isDefault: true,
  ),
  AgentModelOption(
    runner: 'copilot',
    modelName: 'gpt-4.1',
    grade: '0급',
  ),
  AgentModelOption(
    runner: 'copilot',
    modelName: 'gpt-5.4-mini',
    grade: '0.33급',
  ),
  AgentModelOption(
    runner: 'copilot',
    modelName: 'claude-haiku-4.5',
    grade: '0.33급',
  ),
  AgentModelOption(
    runner: 'copilot',
    modelName: 'claude-sonnet-4.6',
    grade: '1급',
  ),
  AgentModelOption(
    runner: 'copilot',
    modelName: 'gpt-5.4',
    grade: '1급',
  ),
  AgentModelOption(
    runner: 'codex',
    modelName: 'gpt-5.4-mini',
    grade: '0.33급',
    isDefault: true,
  ),
  AgentModelOption(
    runner: 'codex',
    modelName: 'gpt-5.3-codex',
    grade: '1급',
  ),
  AgentModelOption(
    runner: 'codex',
    modelName: 'gpt-5.4',
    grade: '1급',
  ),
  AgentModelOption(
    runner: 'codex',
    modelName: 'gpt-5.5',
    grade: '7.5급',
  ),
  AgentModelOption(
    runner: 'claude',
    modelName: 'claude-haiku-4.5',
    grade: '0.33급',
    isDefault: true,
  ),
  AgentModelOption(
    runner: 'claude',
    modelName: 'claude-sonnet-4-6',
    grade: '1급',
  ),
  AgentModelOption(
    runner: 'claude',
    modelName: 'claude-opus-4-7',
    grade: '15급',
  ),
  AgentModelOption(
    runner: 'gemini',
    modelName: 'gemini-3.1-flash-lite-preview',
    grade: '0.33급',
  ),
  AgentModelOption(
    runner: 'gemini',
    modelName: 'gemini-3-flash-preview',
    grade: '0.33급',
    isDefault: true,
  ),
  AgentModelOption(
    runner: 'gemini',
    modelName: 'gemini-3.1-pro-preview',
    grade: '1급',
  ),
];

List<AgentModelOption> agentModelsForRunner(String runner) {
  return agentModelOptions
      .where((option) => option.runner == runner)
      .toList(growable: false);
}

AgentModelOption agentDefaultModelForRunner(String runner) {
  final options = agentModelsForRunner(runner);
  return options.firstWhere(
    (option) => option.isDefault,
    orElse: () => options.first,
  );
}

AgentModelOption? agentModelFor(String runner, String modelName) {
  for (final option in agentModelOptions) {
    if (option.runner == runner && option.modelName == modelName) {
      return option;
    }
  }
  return null;
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return fallback;
  }
  return text;
}

String? _nullableString(Object? value) {
  final stringValue = value?.toString();
  if (stringValue == null || stringValue.isEmpty) {
    return null;
  }
  return stringValue;
}

bool _bool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  return value?.toString().toLowerCase() == 'true';
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  if (value is String && value.isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      return const <String, dynamic>{};
    }
  }
  return const <String, dynamic>{};
}
