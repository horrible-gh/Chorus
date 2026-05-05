class AuthException implements Exception {
  const AuthException(
    this.detail, {
    this.statusCode,
    this.code,
  });

  final String detail;
  final int? statusCode;
  final String? code;

  @override
  String toString() {
    final suffix = statusCode == null ? '' : ' ($statusCode)';
    return 'AuthException$suffix: $detail';
  }
}
