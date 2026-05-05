import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../models/agent_preset.dart';

class AgentPresetForm extends StatefulWidget {
  const AgentPresetForm({
    super.key,
    required this.ownerUserId,
    required this.onSubmit,
    this.preset,
    this.isSaving = false,
    this.enabled = true,
  });

  final String ownerUserId;
  final AgentPreset? preset;
  final bool isSaving;
  final bool enabled;
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
                  initialValue: _grade,
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
            _TokenDropdown(
              value: _providerTokenId,
              enabled: _canEdit,
              onChanged: (value) {
                setState(() {
                  _providerTokenId = value;
                });
              },
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

  List<AgentModelOption> get _modelOptions {
    final options = agentModelsForRunner(_runner);
    if (agentModelFor(_runner, _model) != null) {
      return options;
    }
    return [
      AgentModelOption(
        runner: _runner,
        modelName: _model,
        grade: _grade,
      ),
      ...options,
    ];
  }

  void _loadInitialValues() {
    final preset = widget.preset;
    final model = preset == null
        ? agentDefaultModelForRunner('copilot')
        : agentModelFor(preset.defaultRunner, preset.defaultModel) ??
            AgentModelOption(
              runner: preset.defaultRunner,
              modelName: preset.defaultModel,
              grade: preset.defaultGrade,
            );
    final settings = preset?.settings ?? const AgentPresetSettings();

    _displayNameController.text = preset?.displayName ?? '';
    _roleNameController.text = preset?.roleName ?? '';
    _descriptionController.text = preset?.description ?? '';
    _systemPromptController.text = preset?.systemPrompt ?? '';
    _pinnedContextController.text = preset?.pinnedContext ?? '';
    _allowedToolsController.text = settings.allowedTools;
    _workDirController.text = settings.workDir;

    _runner = model.runner;
    _model = model.modelName;
    _grade = model.grade;
    _providerTokenId = settings.providerTokenId;
    _useAllowAll = settings.useAllowAll;
    _codexMode =
        _codexModes.contains(settings.codexMode) ? settings.codexMode : 'never';
    _approvalMode = _approvalModes.contains(settings.approvalMode)
        ? settings.approvalMode
        : 'default';
    _session = _sessions.contains(settings.session) ? settings.session : 'none';
    _formKey.currentState?.reset();
  }

  void _onRunnerChanged(String? value) {
    if (value == null) {
      return;
    }
    final model = agentDefaultModelForRunner(value);
    setState(() {
      _runner = value;
      _model = model.modelName;
      _grade = model.grade;
    });
  }

  void _onModelChanged(String? value) {
    if (value == null) {
      return;
    }
    final option = agentModelFor(_runner, value);
    setState(() {
      _model = value;
      _grade = option?.grade ?? '';
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
          providerTokenId: _providerTokenId,
          useAllowAll: _runner == 'copilot' && _useAllowAll,
          codexMode: _runner == 'codex' ? _codexMode : 'never',
          allowedTools:
              _runner == 'claude' ? _allowedToolsController.text.trim() : '',
          approvalMode: _runner == 'gemini' ? _approvalMode : 'default',
          workDir: _runner == 'codex' ? _workDirController.text.trim() : '',
          session: _session,
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
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = [
      if (value != null && value!.isNotEmpty) value!,
    ];

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
            value: token,
            child: Text(
              token,
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
