class SmsPattern {
  final int bankId;
  final String senderId; // e.g., "CBE", "telebirr"
  final String regex;
  final String type; // CREDIT or DEBIT
  final String description;
  final bool? refRequired;
  final bool? hasAccount;

  const SmsPattern({
    required this.bankId,
    required this.senderId,
    required this.regex,
    required this.type,
    this.description = '',
    this.refRequired,
    this.hasAccount,
  });

  factory SmsPattern.fromJson(Map<String, dynamic> json) {
    return SmsPattern(
      bankId: json['bankId'] as int,
      senderId: json['senderId'] as String,
      regex: json['regex'] as String,
      type: json['type'] as String,
      description: json['description'] as String? ?? '',
      refRequired: json['refRequired'] as bool?,
      hasAccount: json['hasAccount'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bankId': bankId,
      'senderId': senderId,
      'regex': regex,
      'type': type,
      'description': description,
      'refRequired': refRequired,
      'hasAccount': hasAccount,
    };
  }
}
