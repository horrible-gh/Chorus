class UserProfile {
  const UserProfile({
    required this.userId,
    required this.emailVerified,
    required this.totpEnabled,
  });

  final String userId;
  final bool emailVerified;
  final bool totpEnabled;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['user_id'] as String? ?? '',
      emailVerified: json['email_verified'] as bool? ?? false,
      totpEnabled: json['totp_enabled'] as bool? ?? false,
    );
  }
}

class TotpSetupData {
  const TotpSetupData({
    required this.secret,
    required this.qrUri,
    required this.qrImage,
    required this.recoveryCodes,
  });

  final String secret;
  final String qrUri;
  final String qrImage; // base64-encoded PNG
  final List<String> recoveryCodes;

  factory TotpSetupData.fromJson(Map<String, dynamic> json) {
    final rawCodes = json['recovery_codes'];
    final codes = rawCodes is List
        ? rawCodes.map((e) => e.toString()).toList()
        : <String>[];

    return TotpSetupData(
      secret: json['secret'] as String? ?? '',
      qrUri: json['qr_uri'] as String? ?? '',
      qrImage: json['qr_image'] as String? ?? '',
      recoveryCodes: codes,
    );
  }
}
