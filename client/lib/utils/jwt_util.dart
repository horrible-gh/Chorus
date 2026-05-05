import 'dart:convert';

class JwtUtil {
  static bool isExpired(String token) {
    final expiresAt = expiration(token);
    if (expiresAt == null) {
      return true;
    }
    return !DateTime.now().isBefore(expiresAt);
  }

  static DateTime? expiration(String token) {
    final payload = payloadMap(token);
    final exp = payload?['exp'];
    if (exp is int) {
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    }
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    }
    return null;
  }

  static Map<String, dynamic>? payloadMap(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return null;
      }
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final jsonValue = jsonDecode(decoded);
      if (jsonValue is Map<String, dynamic>) {
        return jsonValue;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
