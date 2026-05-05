class User {
  const User({
    required this.userId,
    required this.displayName,
    this.email,
    this.emailVerified = false,
    this.raw = const {},
  });

  final String userId;
  final String displayName;
  final String? email;
  final bool emailVerified;
  final Map<String, dynamic> raw;

  factory User.fromJson(Map<String, dynamic> json) {
    final userId = _stringValue(
      json['user_id'] ?? json['id'] ?? json['sub'] ?? json['username'],
    );
    final displayName = _stringValue(
      json['display_name'] ??
          json['user_name'] ??
          json['username'] ??
          json['email'] ??
          userId,
    );
    final email = _stringValueOrNull(json['email']) ??
        (userId.contains('@') ? userId : null);

    return User(
      userId: userId,
      displayName: displayName.isEmpty ? userId : displayName,
      email: email,
      emailVerified: json['email_verified'] == true,
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'display_name': displayName,
      if (email != null) 'email': email,
      'email_verified': emailVerified,
      'raw': raw,
    };
  }

  static String _stringValue(Object? value) => value?.toString() ?? '';

  static String? _stringValueOrNull(Object? value) {
    final stringValue = value?.toString();
    if (stringValue == null || stringValue.isEmpty) {
      return null;
    }
    return stringValue;
  }
}
