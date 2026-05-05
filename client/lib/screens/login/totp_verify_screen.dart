import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/routes.dart';
import '../../models/auth_exception.dart';
import '../../providers/auth_provider.dart';

class TotpVerifyScreen extends StatefulWidget {
  const TotpVerifyScreen({
    super.key,
    required this.tempToken,
  });

  final String tempToken;

  @override
  State<TotpVerifyScreen> createState() => _TotpVerifyScreenState();
}

class _TotpVerifyScreenState extends State<TotpVerifyScreen> {
  final _codeController = TextEditingController();
  String? _errorMessage;
  bool _useRecoveryCode = false;

  @override
  void initState() {
    super.initState();
    if (widget.tempToken.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(AppRoutes.login);
        }
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final expectedLength = _useRecoveryCode ? 8 : 6;
    if (code.length != expectedLength) {
      setState(() {
        _errorMessage = _useRecoveryCode
            ? 'Enter an 8-character recovery code.'
            : 'Enter the 6-digit code.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    final auth = context.read<AuthProvider>();
    try {
      await auth.verifyTotp(widget.tempToken, code);
      if (!mounted) {
        return;
      }
      context.go(AppRoutes.home);
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.detail == 'token_expired') {
        context.go(AppRoutes.login);
        return;
      }
      setState(() {
        _errorMessage = auth.error ?? 'The verification code is not valid.';
        _codeController.clear();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to verify the code.';
      });
    }
  }

  void _toggleMode() {
    setState(() {
      _useRecoveryCode = !_useRecoveryCode;
      _codeController.clear();
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.login),
        ),
        title: const Text('Verification'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: colorScheme.primary,
                        size: 40,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _codeController,
                        decoration: InputDecoration(
                          labelText:
                              _useRecoveryCode ? 'Recovery code' : 'Code',
                          prefixIcon: const Icon(Icons.pin_outlined),
                          counterText: '',
                        ),
                        autofocus: true,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 4,
                        ),
                        keyboardType: _useRecoveryCode
                            ? TextInputType.text
                            : TextInputType.number,
                        inputFormatters: _useRecoveryCode
                            ? [
                                FilteringTextInputFormatter.allow(
                                  RegExp('[a-zA-Z0-9]'),
                                ),
                                LengthLimitingTextInputFormatter(8),
                              ]
                            : [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                        autofillHints: const [AutofillHints.oneTimeCode],
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: colorScheme.error,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Consumer<AuthProvider>(
                        builder: (context, auth, child) {
                          return FilledButton.icon(
                            onPressed: auth.isLoading ? null : _submit,
                            icon: auth.isLoading
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: const Text('Verify'),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _toggleMode,
                        icon: Icon(
                          _useRecoveryCode
                              ? Icons.password_outlined
                              : Icons.key_outlined,
                        ),
                        label: Text(
                          _useRecoveryCode
                              ? 'Use authenticator code'
                              : 'Use recovery code',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
