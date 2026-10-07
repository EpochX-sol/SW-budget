/// Represents a normalized, strongly-typed transaction parsed from raw SMS or notification.
class ParsedTransaction {
  final String provider; // CBE, TELEBIRR, ABYSSINIA, DASHEN, ENAT, OTHER
  final String type; // income, expense, transfer
  final double amount;
  final double? balanceAfter;
  final String? counterparty;
  final String? reference;
  final DateTime occurredAt;
  final double parseConfidence;
  final String dedupeKey;
  final String rawBody;
  final String? templateId;
  final bool needsReview;

  const ParsedTransaction({
    required this.provider,
    required this.type,
    required this.amount,
    this.balanceAfter,
    this.counterparty,
    this.reference,
    required this.occurredAt,
    required this.parseConfidence,
    required this.dedupeKey,
    required this.rawBody,
    this.templateId,
    this.needsReview = false,
  });

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'type': type,
        'amount': amount,
        'balance_after': balanceAfter,
        'counterparty': counterparty,
        'reference': reference,
        'occurred_at': occurredAt.toIso8601String(),
        'parse_confidence': parseConfidence,
        'dedupe_key': dedupeKey,
        'raw_body': rawBody,
        'template_id': templateId,
        'needs_review': needsReview,
      };

  factory ParsedTransaction.fromJson(Map<String, dynamic> json) =>
      ParsedTransaction(
        provider: json['provider'] as String,
        type: json['type'] as String,
        amount: (json['amount'] as num).toDouble(),
        balanceAfter: (json['balance_after'] as num?)?.toDouble(),
        counterparty: json['counterparty'] as String?,
        reference: json['reference'] as String?,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        parseConfidence: (json['parse_confidence'] as num).toDouble(),
        dedupeKey: json['dedupe_key'] as String,
        rawBody: json['raw_body'] as String,
        templateId: json['template_id'] as String?,
        needsReview: json['needs_review'] as bool? ?? false,
      );

  @override
  String toString() =>
      'ParsedTransaction($provider, $type, amount: $amount, balance: $balanceAfter, ref: $reference)';
}
