import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent_preset.dart';
import '../models/model_registry.dart';
import '../providers/auth_provider.dart';
import '../services/model_registry_service.dart';

const _kRunners = ['ALL', 'copilot', 'claude', 'codex', 'gemini'];
const _kGrades = ['0급', '0.33급', '1급', '7.5급'];

class ModelManagementScreen extends StatefulWidget {
  const ModelManagementScreen({super.key});

  @override
  State<ModelManagementScreen> createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen> {
  ModelRegistryService? _service;
  List<ModelRegistry> _models = const [];
  bool _isLoading = true;
  String? _error;
  String _selectedRunner = 'ALL';
  bool _activeOnly = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (_service == null) {
      _service = ModelRegistryService(auth.dio);
      _loadModels();
    }
  }

  Future<void> _loadModels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final runner = _selectedRunner == 'ALL' ? null : _selectedRunner;
      final models = await _service!.listModels(
        runner: runner,
        activeOnly: _activeOnly,
      );
      if (mounted) {
        setState(() {
          _models = models;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showAddModal() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModelFormModal(
        service: _service!,
        existingModel: null,
      ),
    );
    if (result == true) {
      await _loadModels();
    }
  }

  Future<void> _showEditModal(ModelRegistry model) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModelFormModal(
        service: _service!,
        existingModel: model,
      ),
    );
    if (result == true) {
      await _loadModels();
    }
  }

  Future<void> _toggleActive(ModelRegistry model) async {
    final willDeactivate = model.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:
            Text(willDeactivate ? 'Deactivate Model?' : 'Activate Model?'),
        content: Text(
          willDeactivate
              ? 'Deactivate "${model.modelName}" (${model.runner})?'
              : 'Activate "${model.modelName}" (${model.runner})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await _service!.updateModel(
        modelId: model.modelId,
        request: ModelRegistryUpdateRequest(isActive: !model.isActive),
      );
      if (mounted && result.warning != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ${result.warning}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      await _loadModels();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _setDefault(ModelRegistry model) async {
    try {
      await _service!.updateModel(
        modelId: model.modelId,
        request: const ModelRegistryUpdateRequest(isDefault: true),
      );
      await _loadModels();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Management'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadModels,
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            selectedRunner: _selectedRunner,
            activeOnly: _activeOnly,
            onRunnerChanged: (r) {
              setState(() => _selectedRunner = r);
              _loadModels();
            },
            onActiveOnlyChanged: (v) {
              setState(() => _activeOnly = v);
              _loadModels();
            },
            onAdd: _showAddModal,
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorView(message: _error!, onRetry: _loadModels)
                    : _models.isEmpty
                        ? const _EmptyView()
                        : _ModelList(
                            models: _models,
                            onEdit: _showEditModal,
                            onToggleActive: _toggleActive,
                            onSetDefault: _setDefault,
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Filter Bar ───────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selectedRunner,
    required this.activeOnly,
    required this.onRunnerChanged,
    required this.onActiveOnlyChanged,
    required this.onAdd,
  });

  final String selectedRunner;
  final bool activeOnly;
  final ValueChanged<String> onRunnerChanged;
  final ValueChanged<bool> onActiveOnlyChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _kRunners.map((runner) {
                  final selected = runner == selectedRunner;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(runner),
                      selected: selected,
                      onSelected: (_) => onRunnerChanged(runner),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              Text(
                'Active only',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Switch(
                value: activeOnly,
                onChanged: onActiveOnlyChanged,
              ),
            ],
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Model'),
          ),
        ],
      ),
    );
  }
}

// ── Model List ───────────────────────────────────────────────────────

class _ModelList extends StatelessWidget {
  const _ModelList({
    required this.models,
    required this.onEdit,
    required this.onToggleActive,
    required this.onSetDefault,
  });

  final List<ModelRegistry> models;
  final ValueChanged<ModelRegistry> onEdit;
  final ValueChanged<ModelRegistry> onToggleActive;
  final ValueChanged<ModelRegistry> onSetDefault;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('Runner')),
            DataColumn(label: Text('Model Name')),
            DataColumn(label: Text('Grade')),
            DataColumn(label: Text('Default')),
            DataColumn(label: Text('Active')),
            DataColumn(label: Text('Cost Rank'), numeric: true),
            DataColumn(label: Text('Priority'), numeric: true),
            DataColumn(label: Text('Max Tokens'), numeric: true),
            DataColumn(label: Text('Actions')),
          ],
          rows: models.map((m) => _buildRow(context, m)).toList(),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, ModelRegistry m) {
    final colorScheme = Theme.of(context).colorScheme;
    return DataRow(
      cells: [
        DataCell(Text(m.runner)),
        DataCell(Text(m.modelName)),
        DataCell(Text(m.grade)),
        DataCell(
          m.isDefault
              ? Icon(Icons.star, color: colorScheme.primary, size: 18)
              : const Icon(Icons.star_border, size: 18),
        ),
        DataCell(_ActiveBadge(isActive: m.isActive, isDefault: m.isDefault)),
        DataCell(Text('${m.estimatedCostRank}')),
        DataCell(Text('${m.priority}')),
        DataCell(Text(m.maxContextTokens != null ? '${m.maxContextTokens}' : '—')),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => onEdit(m),
              ),
              IconButton(
                tooltip: m.isActive ? 'Deactivate' : 'Activate',
                icon: Icon(
                  m.isActive
                      ? Icons.toggle_on_outlined
                      : Icons.toggle_off_outlined,
                  size: 18,
                ),
                onPressed: () => onToggleActive(m),
              ),
              if (!m.isDefault)
                IconButton(
                  tooltip: 'Set as Default',
                  icon: const Icon(Icons.star_outline, size: 18),
                  onPressed: () => onSetDefault(m),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.isActive, required this.isDefault});

  final bool isActive;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (isActive && isDefault) {
      return _badge('Default Active', colorScheme.primary);
    } else if (isActive) {
      return _badge('Active', Colors.green);
    } else if (!isActive && isDefault) {
      return _badge('Inactive (Default)', Colors.orange);
    } else {
      return _badge('Inactive', colorScheme.onSurfaceVariant);
    }
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}

// ── Model Form Modal ─────────────────────────────────────────────────

class _ModelFormModal extends StatefulWidget {
  const _ModelFormModal({
    required this.service,
    required this.existingModel,
  });

  final ModelRegistryService service;
  final ModelRegistry? existingModel;

  @override
  State<_ModelFormModal> createState() => _ModelFormModalState();
}

class _ModelFormModalState extends State<_ModelFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _modelNameCtrl = TextEditingController();
  final _costRankCtrl = TextEditingController();
  final _priorityCtrl = TextEditingController();
  final _maxTokensCtrl = TextEditingController();
  final _providerOptionsCtrl = TextEditingController();

  String _runner = 'copilot';
  String _grade = '0급';
  bool _isDefault = false;

  bool _isSaving = false;
  String? _error;

  bool get _isEdit => widget.existingModel != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existingModel;
    if (m != null) {
      _runner = m.runner;
      _grade = m.grade;
      _isDefault = m.isDefault;
      _modelNameCtrl.text = m.modelName;
      _costRankCtrl.text = '${m.estimatedCostRank}';
      _priorityCtrl.text = '${m.priority}';
      _maxTokensCtrl.text =
          m.maxContextTokens != null ? '${m.maxContextTokens}' : '';
      _providerOptionsCtrl.text = m.providerOptionsJson != null
          ? const JsonEncoder.withIndent('  ').convert(m.providerOptionsJson)
          : '';
    } else {
      _costRankCtrl.text = '0';
      _priorityCtrl.text = '0';
    }
  }

  @override
  void dispose() {
    _modelNameCtrl.dispose();
    _costRankCtrl.dispose();
    _priorityCtrl.dispose();
    _maxTokensCtrl.dispose();
    _providerOptionsCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _parseProviderOptions() {
    final text = _providerOptionsCtrl.text.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } on FormatException {
      return null;
    }
  }

  bool _validateProviderOptions() {
    final text = _providerOptionsCtrl.text.trim();
    if (text.isEmpty) return true;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map;
    } on FormatException {
      return false;
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_validateProviderOptions()) {
      setState(() => _error = 'provider_options_json must be a valid JSON object or empty.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final providerOptions = _parseProviderOptions();
      final providerOptionsText = _providerOptionsCtrl.text.trim();

      if (_isEdit) {
        await widget.service.updateModel(
          modelId: widget.existingModel!.modelId,
          request: ModelRegistryUpdateRequest(
            grade: _grade,
            isDefault: _isDefault,
            estimatedCostRank: int.tryParse(_costRankCtrl.text.trim()),
            priority: int.tryParse(_priorityCtrl.text.trim()),
            maxContextTokens: _maxTokensCtrl.text.trim().isEmpty
                ? null
                : int.tryParse(_maxTokensCtrl.text.trim()),
            providerOptionsJson: providerOptions,
            clearProviderOptions: providerOptionsText.isEmpty,
          ),
        );
      } else {
        await widget.service.createModel(
          ModelRegistryCreateRequest(
            runner: _runner,
            modelName: _modelNameCtrl.text.trim(),
            grade: _grade,
            isDefault: _isDefault,
            estimatedCostRank:
                int.tryParse(_costRankCtrl.text.trim()) ?? 0,
            priority: int.tryParse(_priorityCtrl.text.trim()) ?? 0,
            maxContextTokens: _maxTokensCtrl.text.trim().isEmpty
                ? null
                : int.tryParse(_maxTokensCtrl.text.trim()),
            providerOptionsJson: providerOptions,
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Model' : 'Add Model'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 400, maxWidth: 520),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                // runner
                DropdownButtonFormField<String>(
                  initialValue: _runner,
                  decoration: const InputDecoration(
                    labelText: 'Runner *',
                    border: OutlineInputBorder(),
                  ),
                  items: _kRunners
                      .where((r) => r != 'ALL')
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: _isEdit
                      ? null
                      : (v) => setState(() => _runner = v ?? _runner),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                // model_name
                TextFormField(
                  controller: _modelNameCtrl,
                  readOnly: _isEdit,
                  decoration: InputDecoration(
                    labelText: 'Model Name *',
                    border: const OutlineInputBorder(),
                    filled: _isEdit,
                    fillColor: _isEdit
                        ? Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                        : null,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!RegExp(r'^[a-zA-Z0-9\-\.]+$').hasMatch(v.trim())) {
                      return 'Only letters, numbers, hyphens and dots allowed';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                // grade
                DropdownButtonFormField<String>(
                  initialValue: _kGrades.contains(_grade) ? _grade : _kGrades.first,
                  decoration: const InputDecoration(
                    labelText: 'Grade *',
                    border: OutlineInputBorder(),
                  ),
                  items: _kGrades
                      .map((g) => DropdownMenuItem(value: g, child: Text(publicGradeLabel(g))))
                      .toList(),
                  onChanged: (v) => setState(() => _grade = v ?? _grade),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                // estimated_cost_rank
                TextFormField(
                  controller: _costRankCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Estimated Cost Rank *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (int.tryParse(v.trim()) == null) {
                      return 'Must be an integer';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                // priority
                TextFormField(
                  controller: _priorityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v != null &&
                        v.trim().isNotEmpty &&
                        int.tryParse(v.trim()) == null) {
                      return 'Must be an integer';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                // max_context_tokens
                TextFormField(
                  controller: _maxTokensCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Max Context Tokens',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v != null &&
                        v.trim().isNotEmpty &&
                        int.tryParse(v.trim()) == null) {
                      return 'Must be an integer';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                // provider_options_json
                TextFormField(
                  controller: _providerOptionsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Provider Options JSON (optional)',
                    hintText: '{"temperature": 0.5}',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 8),
                // is_default
                CheckboxListTile(
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v ?? false),
                  title: const Text('Set as default for this runner'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: colorScheme.onErrorContainer, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: colorScheme.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error / Empty ────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48),
          SizedBox(height: 12),
          Text('No models found.'),
        ],
      ),
    );
  }
}
