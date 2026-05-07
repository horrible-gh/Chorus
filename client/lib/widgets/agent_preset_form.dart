import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../models/agent_preset.dart';
import '../models/model_registry.dart';
import '../models/provider_token.dart';

class AgentPresetForm extends StatefulWidget {
  const AgentPresetForm({
    super.key,
    required this.ownerUserId,
    required this.onSubmit,
    required this.tokens,
    this.preset,
    this.isSaving = false,
    this.enabled = true,
    this.registryModels = const [],
  });

  final String ownerUserId;
  final AgentPreset? preset;
  final bool isSaving;
  final bool enabled;
  final List<ProviderToken> tokens;
  final List<ModelRegistry> registryModels;
  final ValueChanged<AgentPresetDraft> onSubmit;

  @override
  State<AgentPresetForm> createState() => _AgentPresetFormState();
}

class _AgentPresetFormState extends State<AgentPresetForm> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _roleNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _pinnedContextController = TextEditingController();
  final _allowedToolsController = TextEditingController();
  final _workDirController = TextEditingController();

  String _runner = 'copilot';
  String _model = 'gpt-5-mini';
  String _grade = '0급';
  String _codexMode = 'never';
  String _approvalMode = 'default';
  String _session = 'none';
  String? _providerTokenId;
  bool _useAllowAll = false;
  String _authType = 'api_token';
  String? _cliProvider;

  bool get _canEdit => widget.enabled && !widget.isSaving;

  @override
  void initState() {
    super.initState();
    _loadInitialValues();
  }

  @override
  void didUpdateWidget(covariant AgentPresetForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preset?.agentId != widget.preset?.agentId ||
        oldWidget.ownerUserId != widget.ownerUserId) {
      _loadInitialValues();
    } else if (widget.preset == null &&
        oldWidget.registryModels.isEmpty &&
        widget.registryModels.isNotEmpty) {
      // Registry loaded after form init for new preset — re-pick DB default
      _loadInitialValues();
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _roleNameController.dispose();
    _descriptionController.dispose();
    _systemPromptController.dispose();
    _pinnedContextController.dispose();
    _allowedToolsController.dispose();
    _workDirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              preset: widget.preset,
              enabled: widget.enabled,
            ),
            const SizedBox(height: 18),
            _ResponsiveFields(
              children: [
                TextFormField(
                  controller: _displayNameController,
                  enabled: _canEdit,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _required,
                ),
                TextFormField(
                  controller: _roleNameController,
                  enabled: _canEdit,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.assignment_ind_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: _required,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              enabled: _canEdit,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 18),
            _ResponsiveFields(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _runner,
                  decoration: const InputDecoration(
                    labelText: 'Runner',
                    prefixIcon: Icon(Icons.terminal_outlined),
                  ),
                  items: _runners
                      .map(
                        (runner) => DropdownMenuItem(
                          value: runner,
                          child: Text(runner),
                        ),
                      )
                      .toList(),
                  onChanged: _canEdit ? _onRunnerChanged : null,
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('model-$_runner-$_model'),
                  initialValue: _model,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    prefixIcon: Icon(Icons.memory_outlined),
                  ),
                  items: _modelOptions
                      .map(
                        (option) => DropdownMenuItem(
                          value: option.modelName,
                          child: Text(
                            option.modelName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _canEdit ? _onModelChanged : null,
                ),
                TextFormField(
                  enabled: false,
                  initialValue: publicGradeLabel(_grade),
                  key: ValueKey(_grade),
                  decoration: const InputDecoration(
                    labelText: 'Grade',
                    prefixIcon: Icon(Icons.speed_outlined),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _session,
                  decoration: const InputDecoration(
                    labelText: 'Session',
                    prefixIcon: Icon(Icons.history_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('none')),
                    DropdownMenuItem(
                      value: 'continue',
                      child: Text('continue'),
                    ),
                  ],
                  onChanged: _canEdit
                      ? (value) => setState(() => _session = value ?? 'none')
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _AuthSection(
              authType: _authType,
              cliProvider: _cliProvider,
              providerTokenId: _providerTokenId,
              enabled: _canEdit,
              tokens: widget.tokens,
              onAuthTypeChanged: (value) {
                setState(() {
                  _authType = value;
                  if (value == 'cli') _providerTokenId = null;
                });
              },
              onCliProviderChanged: (value) =>
                  setState(() => _cliProvider = value),
              onTokenChanged: (value) =>
                  setState(() => _providerTokenId = value),
            ),
            const SizedBox(height: 18),
            _RunnerSettings(
              runner: _runner,
              enabled: _canEdit,
              useAllowAll: _useAllowAll,
              codexMode: _codexMode,
              approvalMode: _approvalMode,
              allowedToolsController: _allowedToolsController,
              workDirController: _workDirController,
              onUseAllowAllChanged: (value) {
                setState(() {
                  _useAllowAll = value;
                });
              },
              onCodexModeChanged: (value) {
                setState(() {
                  _codexMode = value;
                });
              },
              onApprovalModeChanged: (value) {
                setState(() {
                  _approvalMode = value;
                });
              },
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _systemPromptController,
              enabled: _canEdit,
              decoration: const InputDecoration(
                labelText: 'System prompt',
                prefixIcon: Icon(Icons.psychology_alt_outlined),
              ),
              minLines: 4,
              maxLines: 8,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pinnedContextController,
              enabled: _canEdit,
              decoration: InputDecoration(
                labelText: 'Pinned context',
                prefixIcon: const Icon(Icons.push_pin_outlined),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Upload file',
                      icon: const Icon(Icons.upload_file_outlined),
                      onPressed: _canEdit ? _pickPinnedContext : null,
                    ),
                    if (_pinnedContextController.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear),
                        onPressed: _canEdit
                            ? () {
                                setState(_pinnedContextController.clear);
                              }
                            : null,
                      ),
                  ],
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 56),
              ),
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _canEdit ? _submit : null,
                icon: widget.isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(widget.preset == null ? 'Create' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<AgentModelOption> _optionsForRunner(String runner) {
    final dbOptions = widget.registryModels
        .where((m) => m.runner == runner)
        .map((m) => AgentModelOption(
              runner: m.runner,
              modelName: m.modelName,
              grade: m.grade,
              isDefault: m.isDefault,
            ))
        .toList(growable: false);
    if (dbOptions.isNotEmpty) return dbOptions;
    return agentModelsForRunner(runner);
  }

  List<AgentModelOption> get _modelOptions {
    final options = _optionsForRunner(_runner);
    if (options.any((o) => o.modelName == _model)) return options;
    return [
      AgentModelOption(runner: _runner, modelName: _model, grade: _grade),
      ...options,
    ];
  }

  void _loadInitialValues() {
    final preset = widget.preset;
    final String runner;
    final String modelName;
    final String grade;

    if (preset == null) {
      runner = 'copilot';
      final dbDefault = widget.registryModels
          .where((m) => m.runner == 'copilot' && m.isDefault)
          .firstOrNull;
      if (dbDefault != null) {
        modelName = dbDefault.modelName;
        grade = dbDefault.grade;
      } else {
        final fallback = agentDefaultModelForRunner('copilot');
        modelName = fallback.modelName;
        grade = fallback.grade;
      }
    } else {
      runner = preset.defaultRunner;
      modelName = preset.defaultModel;
      final dbModel = widget.registryModels
          .where((m) => m.runner == runner && m.modelName == modelName)
          .firstOrNull;
      grade = dbModel?.grade ?? preset.defaultGrade;
    }

    final settings = preset?.settings ?? const AgentPresetSettings();

    _displayNameController.text = preset?.displayName ?? '';
    _roleNameController.text = preset?.roleName ?? '';
    _descriptionController.text = preset?.description ?? '';
    _systemPromptController.text = preset?.systemPrompt ?? '';
    _pinnedContextController.text = preset?.pinnedContext ?? '';
    _allowedToolsController.text = settings.allowedTools;
    _workDirController.text = settings.workDir;

    _runner = runner;
    _model = modelName;
    _grade = grade;
    _providerTokenId = settings.providerTokenId;
    _useAllowAll = settings.useAllowAll;
    _codexMode =
        _codexModes.contains(settings.codexMode) ? settings.codexMode : 'never';
    _approvalMode = _approvalModes.contains(settings.approvalMode)
        ? settings.approvalMode
        : 'default';
    _session = _sessions.contains(settings.session) ? settings.session : 'none';
    _authType =
        _authTypes.contains(settings.authType) ? settings.authType : 'api_token';
    _cliProvider = _cliProviderIds.contains(settings.cliProvider)
        ? settings.cliProvider
        : null;
    _formKey.currentState?.reset();
  }

  void _onRunnerChanged(String? value) {
    if (value == null) return;
    final dbDefault = widget.registryModels
        .where((m) => m.runner == value && m.isDefault)
        .firstOrNull;
    final String newModel;
    final String newGrade;
    if (dbDefault != null) {
      newModel = dbDefault.modelName;
      newGrade = dbDefault.grade;
    } else {
      final fallback = agentDefaultModelForRunner(value);
      newModel = fallback.modelName;
      newGrade = fallback.grade;
    }
    setState(() {
      _runner = value;
      _model = newModel;
      _grade = newGrade;
    });
  }

  void _onModelChanged(String? value) {
    if (value == null) return;
    final dbModel = widget.registryModels
        .where((m) => m.runner == _runner && m.modelName == value)
        .firstOrNull;
    final grade = dbModel?.grade ?? agentModelFor(_runner, value)?.grade ?? '';
    setState(() {
      _model = value;
      _grade = grade;
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    widget.onSubmit(
      AgentPresetDraft(
        ownerUserId: widget.ownerUserId,
        displayName: _displayNameController.text.trim(),
        roleName: _roleNameController.text.trim(),
        description: _descriptionController.text.trim(),
        defaultRunner: _runner,
        defaultModel: _model,
        defaultGrade: _grade,
        systemPrompt: _systemPromptController.text.trim(),
        pinnedContext: _pinnedContextController.text.trim(),
        settings: AgentPresetSettings(
          providerTokenId: _authType == 'cli' ? null : _providerTokenId,
          useAllowAll: _runner == 'copilot' && _useAllowAll,
          codexMode: _runner == 'codex' ? _codexMode : 'never',
          allowedTools:
              _runner == 'claude' ? _allowedToolsController.text.trim() : '',
          approvalMode: _runner == 'gemini' ? _approvalMode : 'default',
          workDir: _runner == 'codex' ? _workDirController.text.trim() : '',
          session: _session,
          authType: _authType,
          cliProvider: _authType == 'cli' ? _cliProvider : null,
        ),
      ),
    );
  }

  Future<void> _pickPinnedContext() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Documents',
          extensions: ['md', 'txt', 'json'],
        ),
      ],
    );
    if (file == null || !mounted) {
      return;
    }
    setState(() {
      _pinnedContextController.text =
          file.path.isNotEmpty ? file.path : file.name;
    });
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.preset,
    required this.enabled,
  });

  final AgentPreset? preset;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final title = preset == null ? 'New preset' : preset!.displayName;
    final subtitle = preset == null
        ? 'Create'
        : preset!.isArchived
            ? 'Archived'
            : 'Edit';

    return Row(
      children: [
        Icon(
          enabled ? Icons.smart_toy_outlined : Icons.archive_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 680;
        final width =
            twoColumns ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(
                width: width,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _RunnerSettings extends StatelessWidget {
  const _RunnerSettings({
    required this.runner,
    required this.enabled,
    required this.useAllowAll,
    required this.codexMode,
    required this.approvalMode,
    required this.allowedToolsController,
    required this.workDirController,
    required this.onUseAllowAllChanged,
    required this.onCodexModeChanged,
    required this.onApprovalModeChanged,
  });

  final String runner;
  final bool enabled;
  final bool useAllowAll;
  final String codexMode;
  final String approvalMode;
  final TextEditingController allowedToolsController;
  final TextEditingController workDirController;
  final ValueChanged<bool> onUseAllowAllChanged;
  final ValueChanged<String> onCodexModeChanged;
  final ValueChanged<String> onApprovalModeChanged;

  @override
  Widget build(BuildContext context) {
    switch (runner) {
      case 'copilot':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.verified_user_outlined),
          title: const Text('use_allow_all'),
          value: useAllowAll,
          onChanged: enabled ? onUseAllowAllChanged : null,
        );
      case 'codex':
        return _ResponsiveFields(
          children: [
            DropdownButtonFormField<String>(
              initialValue: codexMode,
              decoration: const InputDecoration(
                labelText: 'codex_mode',
                prefixIcon: Icon(Icons.tune_outlined),
              ),
              items: _codexModes
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(mode),
                    ),
                  )
                  .toList(),
              onChanged: enabled
                  ? (value) => onCodexModeChanged(value ?? 'never')
                  : null,
            ),
            TextFormField(
              controller: workDirController,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'work_dir',
                prefixIcon: Icon(Icons.folder_open_outlined),
              ),
            ),
          ],
        );
      case 'claude':
        return TextFormField(
          controller: allowedToolsController,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: 'allowed_tools',
            prefixIcon: Icon(Icons.handyman_outlined),
          ),
        );
      case 'gemini':
        return DropdownButtonFormField<String>(
          initialValue: approvalMode,
          decoration: const InputDecoration(
            labelText: 'approval_mode',
            prefixIcon: Icon(Icons.fact_check_outlined),
          ),
          items: _approvalModes
              .map(
                (mode) => DropdownMenuItem(
                  value: mode,
                  child: Text(mode),
                ),
              )
              .toList(),
          onChanged: enabled
              ? (value) => onApprovalModeChanged(value ?? 'default')
              : null,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _TokenDropdown extends StatelessWidget {
  const _TokenDropdown({
    required this.value,
    required this.enabled,
    required this.tokens,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final List<ProviderToken> tokens;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: value == null || value!.isEmpty ? null : value,
      decoration: const InputDecoration(
        labelText: 'Token',
        prefixIcon: Icon(Icons.key_outlined),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('No token'),
        ),
        for (final token in tokens)
          DropdownMenuItem<String?>(
            value: token.tokenId,
            child: Text(
              token.alias,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

const _runners = ['copilot', 'codex', 'claude', 'gemini'];
const _codexModes = ['never', 'full-auto'];
const _approvalModes = ['default', 'auto_edit', 'yolo', 'sandbox_yolo'];
const _sessions = ['none', 'continue'];
const _authTypes = ['api_token', 'cli'];
const _cliProviderIds = ['claude_cli', 'codex_cli', 'copilot', 'gcloud_adc'];

class _AuthSection extends StatelessWidget {
  const _AuthSection({
    required this.authType,
    required this.cliProvider,
    required this.providerTokenId,
    required this.enabled,
    required this.tokens,
    required this.onAuthTypeChanged,
    required this.onCliProviderChanged,
    required this.onTokenChanged,
  });

  final String authType;
  final String? cliProvider;
  final String? providerTokenId;
  final bool enabled;
  final List<ProviderToken> tokens;
  final ValueChanged<String> onAuthTypeChanged;
  final ValueChanged<String?> onCliProviderChanged;
  final ValueChanged<String?> onTokenChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.security_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'Auth type',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'api_token',
              label: Text('API token'),
              icon: Icon(Icons.key_outlined),
            ),
            ButtonSegment(
              value: 'cli',
              label: Text('CLI session'),
              icon: Icon(Icons.terminal_outlined),
            ),
          ],
          selected: {authType},
          onSelectionChanged:
              enabled ? (s) => onAuthTypeChanged(s.first) : null,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(height: 12),
        if (authType == 'api_token')
          _TokenDropdown(
            value: providerTokenId,
            enabled: enabled,
            tokens: tokens,
            onChanged: onTokenChanged,
          )
        else ...[
          DropdownButtonFormField<String?>(
            key: ValueKey('cli-provider-$cliProvider'),
            initialValue: cliProvider,
            decoration: const InputDecoration(
              labelText: 'CLI provider',
              prefixIcon: Icon(Icons.account_tree_outlined),
            ),
            items: const [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('Select provider'),
              ),
              DropdownMenuItem<String?>(
                value: 'claude_cli',
                child: Text('Claude CLI'),
              ),
              DropdownMenuItem<String?>(
                value: 'codex_cli',
                child: Text('Codex CLI'),
              ),
              DropdownMenuItem<String?>(
                value: 'copilot',
                child: Text('Copilot'),
              ),
              DropdownMenuItem<String?>(
                value: 'gcloud_adc',
                child: Text('gcloud ADC'),
              ),
            ],
            onChanged: enabled ? onCliProviderChanged : null,
            validator: (value) =>
                value == null ? 'CLI provider is required' : null,
          ),
          const SizedBox(height: 8),
          _CliAuthHint(),
        ],
      ],
    );
  }
}

class _CliAuthHint extends StatelessWidget {
  const _CliAuthHint();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withOpacity(0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'CLI session mode: uses the CLI login session of the account running the server. '
              'Operates without an API token; for server administrators (owner/internal) only.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
