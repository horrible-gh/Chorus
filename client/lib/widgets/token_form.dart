import 'package:flutter/material.dart';

import '../models/provider_token.dart';

class TokenForm extends StatefulWidget {
  const TokenForm({
    super.key,
    required this.ownerUserId,
    required this.onSubmit,
    this.token,
    this.isSaving = false,
    this.enabled = true,
  });

  final String ownerUserId;
  final ProviderToken? token;
  final bool isSaving;
  final bool enabled;
  final ValueChanged<ProviderTokenDraft> onSubmit;

  @override
  State<TokenForm> createState() => _TokenFormState();
}

class _TokenFormState extends State<TokenForm> {
  final _formKey = GlobalKey<FormState>();
  final _aliasCtrl = TextEditingController();
  final _tokenValueCtrl = TextEditingController();

  String _provider = providerOptions.first;
  bool _active = true;
  bool _obscureToken = true;

  bool get _canEdit => widget.enabled && !widget.isSaving;

  @override
  void initState() {
    super.initState();
    _loadValues();
  }

  @override
  void didUpdateWidget(covariant TokenForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token?.tokenId != widget.token?.tokenId ||
        oldWidget.ownerUserId != widget.ownerUserId) {
      _loadValues();
    }
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _tokenValueCtrl.dispose();
    super.dispose();
  }

  void _loadValues() {
    final t = widget.token;
    if (t != null) {
      _aliasCtrl.text = t.alias;
      _provider = providerOptions.contains(t.provider) ? t.provider : providerOptions.first;
      _active = t.status != 'inactive';
      _tokenValueCtrl.clear();
    } else {
      _aliasCtrl.clear();
      _provider = providerOptions.first;
      _active = true;
      _tokenValueCtrl.clear();
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(
      ProviderTokenDraft(
        ownerUserId: widget.ownerUserId,
        alias: _aliasCtrl.text.trim(),
        provider: _provider,
        tokenValue: _tokenValueCtrl.text,
        status: _active ? 'active' : 'inactive',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.token != null;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEditing ? 'Edit Token' : 'New Token',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _aliasCtrl,
              enabled: _canEdit,
              decoration: const InputDecoration(
                labelText: 'Alias',
                hintText: 'e.g. My OpenAI key',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Alias is required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _provider,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: providerOptions
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: _canEdit ? (v) => setState(() => _provider = v!) : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tokenValueCtrl,
              enabled: _canEdit,
              obscureText: _obscureToken,
              decoration: InputDecoration(
                labelText: 'Token value',
                hintText: isEditing ? 'Leave blank to keep current' : 'sk-...',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureToken ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscureToken = !_obscureToken),
                ),
              ),
              validator: (v) {
                if (!isEditing && (v == null || v.isEmpty)) {
                  return 'Token value is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: _canEdit ? (v) => setState(() => _active = v) : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _canEdit ? _submit : null,
              child: widget.isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEditing ? 'Update' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }
}
