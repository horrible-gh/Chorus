import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/routes.dart';
import '../models/auth_exception.dart';
import '../models/settings.dart';
import '../providers/auth_provider.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsService _service;

  UserProfile? _profile;
  bool _isLoadingProfile = true;
  String? _profileError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    _service = SettingsService(auth.dio);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoadingProfile = true;
      _profileError = null;
    });
    try {
      final profile = await _service.getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _profileError = 'Failed to load profile.';
          _isLoadingProfile = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : _profileError != null
              ? _ErrorView(
                  message: _profileError!,
                  onRetry: _loadProfile,
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _ProfileSection(profile: _profile!),
                    const Divider(height: 32),
                    _NavigationSection(),
                    const Divider(height: 32),
                    _ChangePasswordSection(service: _service),
                    const Divider(height: 32),
                    _TotpSection(
                      service: _service,
                      totpEnabled: _profile!.totpEnabled,
                      onTotpChanged: _loadProfile,
                    ),
                  ],
                ),
    );
  }
}

// ── Profile section ──────────────────────────────────────────────────────
class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: const Text('Email'),
            subtitle: Text(profile.userId),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              profile.emailVerified
                  ? Icons.verified_outlined
                  : Icons.mail_outline,
              color: profile.emailVerified
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            title: const Text('Email verification'),
            subtitle: Text(
              profile.emailVerified ? 'Verified' : 'Not verified',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Navigation section ──────────────────────────────────────────────────
class _NavigationSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Integrations',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: const Text('Token Management'),
          subtitle: const Text('Manage API provider tokens'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.tokenManagement),
        ),
        ListTile(
          leading: const Icon(Icons.tune_outlined),
          title: const Text('Model Management'),
          subtitle: const Text('Manage AI model registry'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.modelManagement),
        ),
      ],
    );
  }
}

// ── Change password section ───────────────────────────────────────────────
class _ChangePasswordSection extends StatefulWidget {
  const _ChangePasswordSection({required this.service});

  final SettingsService service;

  @override
  State<_ChangePasswordSection> createState() => _ChangePasswordSectionState();
}

class _ChangePasswordSectionState extends State<_ChangePasswordSection> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    _error = null;
    _success = false;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _isSaving = true);

    try {
      await widget.service.changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (mounted) {
        _currentCtrl.clear();
        _newCtrl.clear();
        _confirmCtrl.clear();
        setState(() {
          _isSaving = false;
          _success = true;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = _mapError(e.detail);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'Failed to change password. Please try again.';
        });
      }
    }
  }

  String _mapError(String detail) {
    switch (detail) {
      case 'current_password_incorrect':
        return 'Current password is incorrect.';
      case 'new_password_same_as_current':
        return 'New password must differ from the current one.';
      default:
        return detail;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change Password', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _currentCtrl,
                  obscureText: _obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureCurrent
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(
                          () => _obscureCurrent = !_obscureCurrent),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newCtrl,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(
                          () => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v != _newCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (_success)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Password changed successfully.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _submit,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Update Password'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── TOTP security section ───────────────────────────────────────────
class _TotpSection extends StatelessWidget {
  const _TotpSection({
    required this.service,
    required this.totpEnabled,
    required this.onTotpChanged,
  });

  final SettingsService service;
  final bool totpEnabled;
  final VoidCallback onTotpChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Two-Factor Authentication (2FA)', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              totpEnabled ? Icons.lock_outlined : Icons.lock_open_outlined,
              color: totpEnabled
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            title: const Text('Authenticator app'),
            subtitle: Text(totpEnabled ? 'Enabled' : 'Disabled'),
            trailing: totpEnabled
                ? OutlinedButton(
                    onPressed: () =>
                        _showDisableTotpDialog(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                    child: const Text('Disable'),
                  )
                : FilledButton.tonal(
                    onPressed: () => _showSetupTotpSheet(context),
                    child: const Text('Enable'),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSetupTotpSheet(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _TotpSetupSheet(service: service),
    );
    if (result == true) {
      onTotpChanged();
    }
  }

  Future<void> _showDisableTotpDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _TotpDisableDialog(service: service),
    );
    if (result == true) {
      onTotpChanged();
    }
  }
}

// ── TOTP setup bottom sheet ─────────────────────────────────────────
class _TotpSetupSheet extends StatefulWidget {
  const _TotpSetupSheet({required this.service});

  final SettingsService service;

  @override
  State<_TotpSetupSheet> createState() => _TotpSetupSheetState();
}

class _TotpSetupSheetState extends State<_TotpSetupSheet> {
  _SetupStep _step = _SetupStep.loading;
  TotpSetupData? _setupData;
  String? _error;

  final _codeCtrl = TextEditingController();
  bool _isActivating = false;
  bool _codeError = false;

  @override
  void initState() {
    super.initState();
    _startSetup();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    setState(() {
      _step = _SetupStep.loading;
      _error = null;
    });
    try {
      final data = await widget.service.setupTotp();
      if (mounted) {
        setState(() {
          _setupData = data;
          _step = _SetupStep.scan;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.detail == 'totp_already_enabled'
              ? '2FA is already enabled.'
              : 'Failed to start 2FA setup: ${e.detail}';
          _step = _SetupStep.error;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Failed to start 2FA setup.';
          _step = _SetupStep.error;
        });
      }
    }
  }

  Future<void> _activate() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _codeError = true);
      return;
    }

    setState(() {
      _isActivating = true;
      _codeError = false;
    });

    try {
      final ok = await widget.service.activateTotp(code);
      if (mounted) {
        if (ok) {
          Navigator.of(context).pop(true);
        } else {
          setState(() {
            _isActivating = false;
            _codeError = true;
          });
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _isActivating = false;
          _codeError = e.detail == 'invalid_totp_code';
          if (!_codeError) {
            _error = e.detail;
            _step = _SetupStep.error;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isActivating = false;
          _error = 'Activation failed. Please try again.';
          _step = _SetupStep.error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Set Up Two-Factor Authentication',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: _buildStepContent(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _SetupStep.loading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(),
          ),
        );

      case _SetupStep.error:
        return Column(
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(_error ?? 'An error occurred'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _startSetup,
              child: const Text('Retry'),
            ),
          ],
        );

      case _SetupStep.scan:
        final data = _setupData!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Scan the QR code below with your authenticator app '
              '(e.g. Google Authenticator, Authy).',
            ),
            const SizedBox(height: 16),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(data.qrImage),
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy secret key'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: data.secret));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Secret key copied to clipboard')),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text('2. Enter the 6-digit code from your app to confirm:'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: InputDecoration(
                labelText: 'Verification code',
                errorText: _codeError ? 'Invalid code. Try again.' : null,
                counterText: '',
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (_) => _activate(),
            ),
            const SizedBox(height: 8),
            const Text(
              '3. Save these recovery codes in a safe place. '
              'Each can be used once if you lose access to your app.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            _RecoveryCodesBox(codes: data.recoveryCodes),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isActivating ? null : _activate,
                child: _isActivating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enable 2FA'),
              ),
            ),
          ],
        );
    }
  }
}

enum _SetupStep { loading, scan, error }

// ── Recovery code box ───────────────────────────────────────────────
class _RecoveryCodesBox extends StatelessWidget {
  const _RecoveryCodesBox({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: codes
                .map(
                  (code) => Chip(
                    label: Text(
                      code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('Copy all codes'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: codes.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Recovery codes copied to clipboard')),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── TOTP disable dialog ─────────────────────────────────────────
class _TotpDisableDialog extends StatefulWidget {
  const _TotpDisableDialog({required this.service});

  final SettingsService service;

  @override
  State<_TotpDisableDialog> createState() => _TotpDisableDialogState();
}

class _TotpDisableDialogState extends State<_TotpDisableDialog> {
  final _codeCtrl = TextEditingController();
  bool _isDisabling = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _disable() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code from your app.');
      return;
    }

    setState(() {
      _isDisabling = true;
      _error = null;
    });

    try {
      await widget.service.disableTotp(code);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _isDisabling = false;
          _error = e.detail == 'invalid_totp_code'
              ? 'Invalid code. Try again.'
              : e.detail;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isDisabling = false;
          _error = 'Failed to disable 2FA. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Disable Two-Factor Authentication'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the 6-digit code from your authenticator app to confirm.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: InputDecoration(
              labelText: 'Verification code',
              errorText: _error,
              counterText: '',
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDisabling ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _isDisabling ? null : _disable,
          child: _isDisabling
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Disable'),
        ),
      ],
    );
  }
}

// ── Error view ──────────────────────────────────────────────────────────
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
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
