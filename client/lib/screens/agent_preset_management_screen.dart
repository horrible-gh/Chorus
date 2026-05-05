import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent_preset.dart';
import '../providers/auth_provider.dart';
import '../services/agent_preset_service.dart';
import '../widgets/agent_preset_form.dart';
import '../widgets/agent_preset_list_item.dart';

class AgentPresetManagementScreen extends StatefulWidget {
  const AgentPresetManagementScreen({super.key});

  @override
  State<AgentPresetManagementScreen> createState() =>
      _AgentPresetManagementScreenState();
}

class _AgentPresetManagementScreenState
    extends State<AgentPresetManagementScreen> {
  AgentPresetService? _service;
  List<AgentPreset> _presets = const [];
  String? _selectedAgentId;
  bool _isCreating = true;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showArchived = false;
  String? _error;

  AgentPreset? get _selectedPreset {
    if (_selectedAgentId == null) {
      return null;
    }
    for (final preset in _presets) {
      if (preset.agentId == _selectedAgentId) {
        return preset;
      }
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (_service == null) {
      _service = AgentPresetService(auth.dio);
      _loadPresets();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.userId ?? '';
    final selectedPreset = _selectedPreset;
    final editingEnabled = selectedPreset == null || !selectedPreset.isArchived;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Presets'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadPresets,
          ),
        ],
      ),
      body: userId.isEmpty
          ? const _EmptyState(
              icon: Icons.lock_outline,
              title: 'Sign in required',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 900;
                final listPane = _PresetListPane(
                  presets: _presets,
                  selectedAgentId: _selectedAgentId,
                  isLoading: _isLoading,
                  error: _error,
                  showArchived: _showArchived,
                  onToggleArchived: (value) {
                    setState(() => _showArchived = value);
                    _loadPresets();
                  },
                  onNew: _startCreating,
                  onRetry: _loadPresets,
                  onSelect: _selectPreset,
                  onArchive: _confirmArchive,
                );
                final formPane = AgentPresetForm(
                  key: ValueKey(
                    _isCreating ? 'new' : selectedPreset?.agentId ?? 'new',
                  ),
                  ownerUserId: userId,
                  preset: _isCreating ? null : selectedPreset,
                  enabled: editingEnabled,
                  isSaving: _isSaving,
                  onSubmit: _savePreset,
                );

                if (compact) {
                  return Column(
                    children: [
                      Expanded(child: listPane),
                      const Divider(height: 1),
                      SizedBox(
                        height: constraints.maxHeight * 0.58,
                        child: formPane,
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    SizedBox(width: 360, child: listPane),
                    const VerticalDivider(width: 1),
                    Expanded(child: formPane),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _loadPresets() async {
    final service = _service;
    final userId = context.read<AuthProvider>().user?.userId ?? '';
    if (service == null || userId.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final presets = await service.listPresets(
        ownerUserId: userId,
        includeArchived: _showArchived,
      );
      presets.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }
        return a.displayName.compareTo(b.displayName);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _presets = presets;
        _isLoading = false;
        if (_selectedAgentId != null &&
            presets.every((preset) => preset.agentId != _selectedAgentId)) {
          _selectedAgentId = presets.isEmpty ? null : presets.first.agentId;
          _isCreating = presets.isEmpty;
        } else if (_selectedAgentId == null && presets.isNotEmpty) {
          _selectedAgentId = presets.first.agentId;
          _isCreating = false;
        } else if (presets.isEmpty) {
          _isCreating = true;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to load presets.';
        _isLoading = false;
      });
    }
  }

  void _startCreating() {
    setState(() {
      _selectedAgentId = null;
      _isCreating = true;
    });
  }

  void _selectPreset(AgentPreset preset) {
    setState(() {
      _selectedAgentId = preset.agentId;
      _isCreating = false;
    });
  }

  Future<void> _savePreset(AgentPresetDraft draft) async {
    final service = _service;
    if (service == null) {
      return;
    }
    final wasCreating = _isCreating;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final saved = wasCreating
          ? await service.createPreset(draft)
          : await service.updatePreset(
              agentId: _selectedAgentId!,
              draft: draft,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _upsertPreset(saved);
        _selectedAgentId = saved.agentId;
        _isCreating = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasCreating ? 'Preset created.' : 'Preset saved.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _error = 'Unable to save preset.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save preset.')),
      );
    }
  }

  Future<void> _confirmArchive(AgentPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive preset'),
        content: Text(preset.displayName),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _archivePreset(preset);
    }
  }

  Future<void> _archivePreset(AgentPreset preset) async {
    final service = _service;
    if (service == null) {
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final archived = await service.archivePreset(preset.agentId);
      if (!mounted) {
        return;
      }
      setState(() {
        if (_showArchived) {
          _upsertPreset(archived);
          _selectedAgentId = archived.agentId;
          _isCreating = false;
        } else {
          _presets = _presets
              .where((item) => item.agentId != preset.agentId)
              .toList(growable: false);
          if (_selectedAgentId == preset.agentId) {
            _selectedAgentId = _presets.isEmpty ? null : _presets.first.agentId;
            _isCreating = _presets.isEmpty;
          }
        }
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preset archived.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _error = 'Unable to archive preset.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to archive preset.')),
      );
    }
  }

  void _upsertPreset(AgentPreset preset) {
    final presets = [..._presets];
    final index = presets.indexWhere((item) => item.agentId == preset.agentId);
    if (index == -1) {
      presets.add(preset);
    } else {
      presets[index] = preset;
    }
    presets.sort((a, b) {
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }
      return a.displayName.compareTo(b.displayName);
    });
    _presets = presets;
  }
}

class _PresetListPane extends StatelessWidget {
  const _PresetListPane({
    required this.presets,
    required this.selectedAgentId,
    required this.isLoading,
    required this.showArchived,
    required this.onToggleArchived,
    required this.onNew,
    required this.onRetry,
    required this.onSelect,
    required this.onArchive,
    this.error,
  });

  final List<AgentPreset> presets;
  final String? selectedAgentId;
  final bool isLoading;
  final bool showArchived;
  final String? error;
  final ValueChanged<bool> onToggleArchived;
  final VoidCallback onNew;
  final VoidCallback onRetry;
  final ValueChanged<AgentPreset> onSelect;
  final ValueChanged<AgentPreset> onArchive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Presets',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'New preset',
                  icon: const Icon(Icons.add),
                  onPressed: onNew,
                ),
              ],
            ),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
            secondary: const Icon(Icons.archive_outlined),
            title: const Text('Archived'),
            value: showArchived,
            onChanged: isLoading ? null : onToggleArchived,
          ),
          if (isLoading) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      error!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retry',
                    icon: const Icon(Icons.refresh),
                    onPressed: onRetry,
                  ),
                ],
              ),
            ),
          Expanded(
            child: presets.isEmpty && !isLoading
                ? const _EmptyState(
                    icon: Icons.smart_toy_outlined,
                    title: 'No presets',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                    itemCount: presets.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final preset = presets[index];
                      return AgentPresetListItem(
                        preset: preset,
                        selected: preset.agentId == selectedAgentId,
                        onTap: () => onSelect(preset),
                        onArchive:
                            preset.isArchived ? null : () => onArchive(preset),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 42,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
