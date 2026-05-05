import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/auth_exception.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/totp_service.dart';
import '../utils/jwt_util.dart';
import '../utils/secure_storage.dart';

enum AuthStatus { checking, authenticated, unauthenticated }

enum LoginResult { success, totpRequired, maintenance, failed }

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    ApiClient? apiClient,
    SecureStorage? secureStorage,
  })  : _apiClient = apiClient ?? ApiClient(),
        _secureStorage = secureStorage ?? SecureStorage() {
    _authService = AuthService(_apiClient.dio);
    _totpService = TotpService(_apiClient.dio);
    _apiClient.configure(
      getAccessToken: () => _accessToken,
      onSessionExpired: handleSessionExpired,
    );
  }

  final ApiClient _apiClient;
  final SecureStorage _secureStorage;
  late final AuthService _authService;
  late final TotpService _totpService;

  AuthStatus _status = AuthStatus.checking;
  User? _user;
  String? _accessToken;
  String? _tokenType;
  String? _tempToken;
  bool _isLoading = false;
  String? _error;

  AuthStatus get status => _status;
  User? get user => _user;
  String? get accessToken => _accessToken;
  String? get tokenType => _tokenType;
  String? get tempToken => _tempToken;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _accessToken != null;
  Dio get dio => _apiClient.dio;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> restoreSession() async {
    _status = AuthStatus.checking;
    notifyListeners();

    try {
      final token = await _secureStorage.read(AppConfig.keyAccessToken);
      final tokenType = await _secureStorage.read(AppConfig.keyTokenType);
      final userJson = await _secureStorage.read(AppConfig.keyUser);

      if (token == null || userJson == null || JwtUtil.isExpired(token)) {
        await _clearSession(setUnauthenticated: true);
        return;
      }

      final decodedUser = jsonDecode(userJson);
      if (decodedUser is! Map<String, dynamic>) {
        await _clearSession(setUnauthenticated: true);
        return;
      }

      _accessToken = token;
      _tokenType = tokenType ?? 'bearer';
      _user = User.fromJson(decodedUser);
      _status = AuthStatus.authenticated;
      _error = null;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('[AuthProvider.restoreSession] $error');
      debugPrint('$stackTrace');
      await _clearSession(setUnauthenticated: true);
    }
  }

  Future<LoginResult> login(String username, String password) async {
    _error = null;
    _setLoading(true);

    try {
      final outcome = await _authService.login(
        username: username,
        password: password,
      );

      if (outcome.isMaintenance) {
        _error = outcome.maintenanceMessage;
        _setLoading(false);
        return LoginResult.maintenance;
      }

      if (outcome.isTotpRequired) {
        _tempToken = outcome.tempToken;
        _setLoading(false);
        return LoginResult.totpRequired;
      }

      final session = outcome.session;
      if (session == null || session.accessToken.isEmpty) {
        _error = 'Login response was incomplete.';
        _setLoading(false);
        return LoginResult.failed;
      }

      await _saveSession(session);
      _setLoading(false);
      return LoginResult.success;
    } on AuthException catch (error) {
      _error = _messageForAuthError(error.detail, error.code);
      _setLoading(false);
      return LoginResult.failed;
    } catch (error, stackTrace) {
      debugPrint('[AuthProvider.login] $error');
      debugPrint('$stackTrace');
      _error = 'Unable to sign in. Please try again.';
      _setLoading(false);
      return LoginResult.failed;
    }
  }

  Future<void> verifyTotp(String tempToken, String code) async {
    _error = null;
    _setLoading(true);

    try {
      final session = await _totpService.verifyLogin(
        tempToken: tempToken,
        code: code,
      );
      await _saveSession(session);
      _tempToken = null;
      _setLoading(false);
    } on AuthException catch (error) {
      _error = _messageForAuthError(error.detail, error.code);
      _setLoading(false);
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('[AuthProvider.verifyTotp] $error');
      debugPrint('$stackTrace');
      _error = 'Unable to verify the code.';
      _setLoading(false);
      rethrow;
    }
  }

  Future<void> logout() async {
    _setLoading(true);
    try {
      if (_accessToken != null) {
        await _authService.logout();
      }
    } catch (error) {
      debugPrint('[AuthProvider.logout] $error');
    } finally {
      await _clearSession(setUnauthenticated: true);
      _setLoading(false);
    }
  }

  Future<void> handleSessionExpired() async {
    await _clearSession(setUnauthenticated: true);
    _error = 'Your session expired. Please sign in again.';
    notifyListeners();
  }

  Future<void> _saveSession(AuthLoginResponse session) async {
    _accessToken = session.accessToken;
    _tokenType = session.tokenType;
    _user = session.user;
    _status = AuthStatus.authenticated;
    _error = null;

    await Future.wait([
      _secureStorage.write(AppConfig.keyAccessToken, session.accessToken),
      _secureStorage.write(AppConfig.keyTokenType, session.tokenType),
      _secureStorage.write(AppConfig.keyUser, jsonEncode(session.user.toJson())),
      _secureStorage.write(
        AppConfig.keyLastLoginAt,
        DateTime.now().toIso8601String(),
      ),
    ]);

    notifyListeners();
  }

  Future<void> _clearSession({required bool setUnauthenticated}) async {
    _accessToken = null;
    _tokenType = null;
    _user = null;
    _tempToken = null;
    if (setUnauthenticated) {
      _status = AuthStatus.unauthenticated;
    }

    await Future.wait([
      _secureStorage.delete(AppConfig.keyAccessToken),
      _secureStorage.delete(AppConfig.keyTokenType),
      _secureStorage.delete(AppConfig.keyUser),
      _secureStorage.delete(AppConfig.keyLastLoginAt),
    ]);

    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  String _messageForAuthError(String detail, String? code) {
    final normalized = code ?? detail;
    switch (normalized) {
      case 'Invalid credentials':
        return 'Email or password is incorrect.';
      case 'email_not_verified':
        return 'Please verify your email before signing in.';
      case 'invalid_code':
        return 'The verification code is not valid.';
      case 'token_expired':
        return 'The verification session expired. Sign in again.';
      case 'AUTH_TOKEN_EXPIRED':
      case 'Token has expired':
        return 'Your session expired. Please sign in again.';
      default:
        return detail.isEmpty ? 'Authentication failed.' : detail;
    }
  }
}
