class ProviderConnectionStatus {
  const ProviderConnectionStatus({
    required this.provider,
    required this.status,
    required this.executablePath,
    required this.pathSource,
    this.resolvedPath,
    this.lastCheckedAt,
    this.lastAvailableAt,
    this.lastError,
  });

  factory ProviderConnectionStatus.fromJson(Map<String, dynamic> json) {
    return ProviderConnectionStatus(
      provider: json['provider'] as String,
      status: json['status'] as String,
      executablePath: json['executable_path'] as String? ?? '',
      pathSource: json['path_source'] as String? ?? '',
      resolvedPath: json['resolved_path'] as String?,
      lastCheckedAt: json['last_checked_at'] as String?,
      lastAvailableAt: json['last_available_at'] as String?,
      lastError: json['last_error'] as String?,
    );
  }

  final String provider;
  final String status;
  final String executablePath;
  final String pathSource;
  final String? resolvedPath;
  final String? lastCheckedAt;
  final String? lastAvailableAt;
  final String? lastError;

  ProviderConnectionStatus copyWith({
    String? status,
    String? executablePath,
    String? pathSource,
    String? resolvedPath,
    String? lastCheckedAt,
    String? lastAvailableAt,
    String? lastError,
  }) {
    return ProviderConnectionStatus(
      provider: provider,
      status: status ?? this.status,
      executablePath: executablePath ?? this.executablePath,
      pathSource: pathSource ?? this.pathSource,
      resolvedPath: resolvedPath ?? this.resolvedPath,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastAvailableAt: lastAvailableAt ?? this.lastAvailableAt,
      lastError: lastError ?? this.lastError,
    );
  }
}
