import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/provider_connection.dart';
import '../models/provider_token.dart';
import '../providers/auth_provider.dart';
import '../services/provider_connection_service.dart';
import '../services/provider_token_service.dart';
import '../widgets/token_form.dart';
import '../widgets/token_list_item.dart';

class TokenManagementScreen extends StatefulWidget {
  const TokenManagementScreen({super.key});

  @override
  State<TokenManagementScreen> createState() => _TokenManagementScreenState();
}

class _TokenManagementScreenState extends State<TokenManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── API Token tab state ──────────────────────────────────────────
  ProviderTokenService? _service;
  List<ProviderToken> _tokens = const [];
  String? _selectedTokenId;
  bool _isCreating = true;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  // ── AI Connection Status tab state ───────────────────────────────
  ProviderConnectionService? _connectionService;

  ProviderToken? get _selectedToken {
    if (_selectedTokenId == null) return null;
    for (final t in _tokens) {
      if (t.tokenId == _selectedTokenId) return t;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // AI Connection Status tab is self-loading via its own StatefulWidget
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (_service == null) {
      _service = ProviderTokenService(auth.dio);
      _connectionService = ProviderConnectionService(auth.dio);
      _loadTokens();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.userId ?? '';
    final selectedToken = _selectedToken;
    final editingEnabled = selectedToken == null || !selectedToken.isArchived;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider Management'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_tabController.index == 0) {
                if (!_isLoading) _loadTokens();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'API Tokens'),
            Tab(text: 'AI Connection Status'),
          ],
        ),
      ),
      body: userId.isEmpty
          ? const _EmptyState(
              icon: Icons.lock_outline,
              title: 'Sign in required',
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // ── Tab 1: API Token ──
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 900;
                    final listPane = _TokenListPane(
                      tokens: _tokens,
                      selectedTokenId: _selectedTokenId,
                      isLoading: _isLoading,
                      error: _error,
                      onNew: _startCreating,
                      onRetry: _loadTokens,
                      onSelect: _selectToken,
                      onArchive: _confirmArchive,
                    );
                    final formPane = TokenForm(
                      key: ValueKey(
                        _isCreating ? 'new' : selectedToken?.tokenId ?? 'new',
                      ),
                      ownerUserId: userId,
                      token: _isCreating ? null : selectedToken,
                      enabled: editingEnabled,
                      isSaving: _isSaving,
                      onSubmit: _saveToken,
                    );

                    if (compact) {
                      return Column(
                        children: [
                          Expanded(child: listPane),
                          const Divider(height: 1),
                          SizedBox(height: 380, child: formPane),
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
                // ── Tab 2: AI Connection Status ──
                _AiConnectionTab(service: _connectionService!),
              ],
            ),
    );
  }

  // ── API Token tab helpers ────────────────────────────────────────

  Future<void> _loadTokens() async {
    final userId = context.read<AuthProvider>().user?.userId ?? '';
    if (userId.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final tokens = await _service!.listTokens(ownerUserId: userId);
      if (mounted) {
        setState(() {
          _tokens = tokens.where((t) => !t.isArchived).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load tokens.';
          _isLoading = false;
        });
      }
    }
  }

  void _startCreating() {
    setState(() {
      _isCreating = true;
      _selectedTokenId = null;
    });
  }

  void _selectToken(String tokenId) {
    setState(() {
      _selectedTokenId = tokenId;
      _isCreating = false;
    });
  }

  Future<void> _saveToken(ProviderTokenDraft draft) async {
    setState(() => _isSaving = true);
    try {
      if (_isCreating) {
        await _service!.createToken(draft);
      } else {
        await _service!.updateToken(tokenId: _selectedTokenId!, draft: draft);
      }
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isCreating = true;
          _selectedTokenId = null;
        });
        await _loadTokens();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _confirmArchive(String tokenId) async {
    final token = _tokens.firstWhere((t) => t.tokenId == tokenId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive token'),
        content: Text('Archive "${token.alias}"? It will no longer be usable.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await _service!.archiveToken(tokenId);
        if (mounted) {
          if (_selectedTokenId == tokenId) {
            setState(() {
              _selectedTokenId = null;
              _isCreating = true;
            });
          }
          await _loadTokens();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }
}

// ── Token list pane ──────────────────────────────────────────────────────────

class _TokenListPane extends StatelessWidget {
  const _TokenListPane({
    required this.tokens,
    required this.selectedTokenId,
    required this.isLoading,
    required this.error,
    required this.onNew,
    required this.onRetry,
    required this.onSelect,
    required this.onArchive,
  });

  final List<ProviderToken> tokens;
  final String? selectedTokenId;
  final bool isLoading;
  final String? error;
  final VoidCallback onNew;
  final VoidCallback onRetry;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onArchive;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _EmptyState(
        icon: Icons.error_outline,
        title: error!,
        action: TextButton(onPressed: onRetry, child: const Text('Retry')),
      );
    }

    final grouped = <String, List<ProviderToken>>{};
    for (final provider in providerOptions) {
      final group = tokens.where((t) => t.provider == provider).toList();
      if (group.isNotEmpty) grouped[provider] = group;
    }
    final otherTokens =
        tokens.where((t) => !providerOptions.contains(t.provider)).toList();
    if (otherTokens.isNotEmpty) grouped['other'] = otherTokens;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                'Tokens',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Add token',
                icon: const Icon(Icons.add),
                onPressed: onNew,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (tokens.isEmpty)
          const Expanded(
            child: _EmptyState(
              icon: Icons.key_off_outlined,
              title: 'No tokens yet',
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                    child: Text(
                      entry.key.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ),
                  for (final token in entry.value)
                    TokenListItem(
                      token: token,
                      selected: token.tokenId == selectedTokenId,
                      onTap: () => onSelect(token.tokenId),
                      onArchive: () => onArchive(token.tokenId),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.action,
  });

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

// ── AI Connection Status tab ─────────────────────────────────────────────────

class _AiConnectionTab extends StatefulWidget {
  const _AiConnectionTab({required this.service});

  final ProviderConnectionService service;

  @override
  State<_AiConnectionTab> createState() => _AiConnectionTabState();
}

class _AiConnectionTabState extends State<_AiConnectionTab> {
  List<ProviderConnectionStatus> _statuses = const [];
  bool _loading = false;
  String? _error;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _saving = {};
  final Map<String, bool> _verifying = {};
  final Map<String, String?> _rowErrors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    for (final s in _statuses) {
      final ctrl = _controllers.putIfAbsent(
        s.provider,
        () => TextEditingController(),
      );
      if (ctrl.text != s.executablePath) {
        ctrl.text = s.executablePath;
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statuses = await widget.service.getProvidersStatus();
      if (mounted) {
        setState(() {
          _statuses = statuses;
          _loading = false;
        });
        _syncControllers();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load provider status.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _savePath(String provider) async {
    final path = _controllers[provider]?.text ?? '';
    setState(() {
      _saving[provider] = true;
      _rowErrors[provider] = null;
    });
    try {
      await widget.service.setExecutablePath(provider, path);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _rowErrors[provider] = 'Failed to save path.';
          _saving[provider] = false;
        });
      }
    }
  }

  Future<void> _verify(String provider) async {
    setState(() {
      _verifying[provider] = true;
      _rowErrors[provider] = null;
    });
    try {
      final updated = await widget.service.verifyProvider(provider);
      if (mounted) {
        setState(() {
          _statuses =
              _statuses.map((s) => s.provider == provider ? updated : s).toList();
          _verifying[provider] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _rowErrors[provider] = 'Verify failed.';
          _verifying[provider] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _EmptyState(
        icon: Icons.error_outline,
        title: _error!,
        action: TextButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final status in _statuses)
          _ProviderConnectionCard(
            status: status,
            controller:
                _controllers[status.provider] ?? TextEditingController(),
            isSaving: _saving[status.provider] ?? false,
            isVerifying: _verifying[status.provider] ?? false,
            rowError: _rowErrors[status.provider],
            onSave: () => _savePath(status.provider),
            onVerify: () => _verify(status.provider),
            onRefresh: _load,
          ),
      ],
    );
  }
}

class _ProviderConnectionCard extends StatelessWidget {
  const _ProviderConnectionCard({
    required this.status,
    required this.controller,
    required this.isSaving,
    required this.isVerifying,
    required this.onSave,
    required this.onVerify,
    required this.onRefresh,
    this.rowError,
  });

  final ProviderConnectionStatus status;
  final TextEditingController controller;
  final bool isSaving;
  final bool isVerifying;
  final String? rowError;
  final VoidCallback onSave;
  final VoidCallback onVerify;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  status.provider.toUpperCase(),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                _ProviderStatusBadge(status: status.status),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Executable Path',
                      hintText: 'Leave empty to use auto-detected path',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: isSaving ? null : onSave,
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Path'),
                ),
              ],
            ),
            if (rowError != null) ...[
              const SizedBox(height: 4),
              Text(
                rowError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _InfoRow(
              label: 'Resolved Path',
              value: status.resolvedPath ?? '(not resolved)',
            ),
            _InfoRow(
              label: 'Last Checked',
              value: status.lastCheckedAt ?? '—',
            ),
            _InfoRow(
              label: 'Last Available',
              value: status.lastAvailableAt ?? '—',
            ),
            if (status.lastError != null)
              _InfoRow(label: 'Last Error', value: status.lastError!),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: isVerifying ? null : onVerify,
                child: isVerifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Verify'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderStatusBadge extends StatelessWidget {
  const _ProviderStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'available' => ('Available', Colors.green),
      'unavailable' => ('Unavailable', Colors.red),
      _ => ('Unverified', Colors.grey),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
