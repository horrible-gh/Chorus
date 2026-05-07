class CliProviderStatus {
  const CliProviderStatus({
    required this.provider,
    required this.status,
    required this.checkedAt,
    required this.logoutSupported,
  });

  factory CliProviderStatus.fromJson(Map<String, dynamic> json) {
    return CliProviderStatus(
      provider: json['provider'] as String,
      status: json['status'] as String,
      checkedAt: json['checked_at'] as String,
      logoutSupported: json['logout_supported'] as bool,
    );
  }

  final String provider;
  final String status;
  final String checkedAt;
  final bool logoutSupported;
}

class CliLoginResponse {
  const CliLoginResponse({
    required this.provider,
    required this.result,
    required this.message,
  });

  factory CliLoginResponse.fromJson(Map<String, dynamic> json) {
    return CliLoginResponse(
      provider: json['provider'] as String,
      result: json['result'] as String,
      message: json['message'] as String,
    );
  }

  final String provider;
  final String result;
  final String message;
}

class CliLogoutResponse {
  const CliLogoutResponse({
    required this.provider,
    required this.result,
  });

  factory CliLogoutResponse.fromJson(Map<String, dynamic> json) {
    return CliLogoutResponse(
      provider: json['provider'] as String,
      result: json['result'] as String,
    );
  }

  final String provider;
  final String result;
}
