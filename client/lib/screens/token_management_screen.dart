import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/provider_token.dart';
import '../providers/auth_provider.dart';
import '../services/provider_token_service.dart';
import '../widgets/token_form.dart';
import '../widgets/token_list_item.dart';

class TokenManagementScreen extends StatefulWidget {
  const TokenManagementScreen({super.key});

  @override
  State<TokenManagementScreen> createState() => _TokenManagementScreenState();
}

class _TokenManagementScreenState extends State<TokenManagementScreen> {
  ProviderTokenService? _service;
  List<ProviderToken> _tokens = const [];
  String? _selectedTokenId;
  bool _isCreating = true;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  ProviderToken? get _selectedToken {
    if (_selectedTokenId == null) return null;
    for (final t in _tokens) {
      if (t.tokenId == _selectedTokenId) return t;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (_service == null) {
      _service = ProviderTokenService(auth.dio);
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
        title: const Text('Token Management'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadTokens,
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
                      SizedBox(
                        height: 380,
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
