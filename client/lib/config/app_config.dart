class AppConfig {
  static const appName = 'Chorus';
  static const defaultLocale = String.fromEnvironment(
    'CHORUS_LOCALE',
    defaultValue: 'ko',
  );

  static const _defaultBaseUrl = String.fromEnvironment(
    'CHORUS_API_BASE_URL',
    defaultValue: 'http://localhost:8018/chorus',
  );

  static String get baseUrl => _trimTrailingSlash(_defaultBaseUrl);

  static const keyAccessToken = 'auth.access_token';
  static const keyTokenType = 'auth.token_type';
  static const keyUser = 'auth.user';
  static const keyLastLoginAt = 'auth.last_login_at';

  static String _trimTrailingSlash(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}
