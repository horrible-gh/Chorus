class ProviderToken {
  const ProviderToken({
    required this.tokenId,
    required this.ownerUserId,
    required this.alias,
    required this.provider,
    required this.tokenValue,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String tokenId;
  final String ownerUserId;
  final String alias;
  final String provider;
  final String tokenValue;
  final String status;
  final String createdAt;
  final String updatedAt;

  bool get isActive => status == 'active';
  bool get isArchived => status == 'archived';

  factory ProviderToken.fromJson(Map<String, dynamic> json) {
    return ProviderToken(
      tokenId: _str(json['token_id']),
      ownerUserId: _str(json['owner_user_id']),
      alias: _str(json['alias']),
      provider: _str(json['provider']),
      tokenValue: _str(json['token_value']),
      status: _str(json['status'], fallback: 'active'),
      createdAt: _str(json['created_at']),
      updatedAt: _str(json['updated_at']),
    );
  }
}

class ProviderTokenDraft {
  const ProviderTokenDraft({
    required this.ownerUserId,
    required this.alias,
    required this.provider,
    required this.tokenValue,
    required this.status,
  });

  final String ownerUserId;
  final String alias;
  final String provider;
  final String tokenValue;
  final String status;

  factory ProviderTokenDraft.fromToken(ProviderToken token) {
    return ProviderTokenDraft(
      ownerUserId: token.ownerUserId,
      alias: token.alias,
      provider: token.provider,
      tokenValue: '',
      status: token.status == 'archived' ? 'active' : token.status,
    );
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'owner_user_id': ownerUserId,
      ...toUpdateJson(),
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'alias': alias,
      'provider': provider,
      if (tokenValue.isNotEmpty) 'token_value': tokenValue,
      'status': status,
    };
  }
}

const providerOptions = ['copilot', 'openai', 'anthropic', 'google'];

String _str(Object? value, {String fallback = ''}) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return fallback;
  return text;
}
