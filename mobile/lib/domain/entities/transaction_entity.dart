/// Domain entity representing a financial transaction in SW-budget
class TransactionEntity {
  final String id;
  final String accountId;
  final String? categoryId;
  final String type; // 'expense', 'income', 'transfer'
  final double amount;
  final double? balanceAfter;
  final String? counterparty;
  final String? reference;
  final String? note;
  final DateTime occurredAt;
  final String source; // 'sms', 'notification', 'manual'
  final double? parseConfidence;
  final String? dedupeKey;
  final String? rawBody;
  final String? sender;

  // Balance-Chain Mathematical Integrity
  final bool? balanceChainOk; // true = mathematically verified, false = gap detected, null = unverified
  final double? gapBeforeAmount; // Discrepancy amount if balance jump occurred
  final bool needsReview;

  // Sync state
  final int changeSeq;
  final bool isDirty;
  final DateTime? deletedAt;

  const TransactionEntity({
    required this.id,
    required this.accountId,
    this.categoryId,
    required this.type,
    required this.amount,
    this.balanceAfter,
    this.counterparty,
    this.reference,
    this.note,
    required this.occurredAt,
    required this.source,
    this.parseConfidence,
    this.dedupeKey,
    this.rawBody,
    this.sender,
    this.balanceChainOk,
    this.gapBeforeAmount,
    this.needsReview = false,
    this.changeSeq = 0,
    this.isDirty = false,
    this.deletedAt,
  });

  bool get isVerified => balanceChainOk == true;
  bool get hasGap => balanceChainOk == false && (gapBeforeAmount != null && gapBeforeAmount! > 0);

  TransactionEntity copyWith({
    String? id,
    String? accountId,
    String? categoryId,
    String? type,
    double? amount,
    double? balanceAfter,
    String? counterparty,
    String? reference,
    String? note,
    DateTime? occurredAt,
    String? source,
    double? parseConfidence,
    String? dedupeKey,
    String? rawBody,
    String? sender,
    bool? balanceChainOk,
    double? gapBeforeAmount,
    bool? needsReview,
    int? changeSeq,
    bool? isDirty,
    DateTime? deletedAt,
  }) {
    return TransactionEntity(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      counterparty: counterparty ?? this.counterparty,
      reference: reference ?? this.reference,
      note: note ?? this.note,
      occurredAt: occurredAt ?? this.occurredAt,
      source: source ?? this.source,
      parseConfidence: parseConfidence ?? this.parseConfidence,
      dedupeKey: dedupeKey ?? this.dedupeKey,
      rawBody: rawBody ?? this.rawBody,
      sender: sender ?? this.sender,
      balanceChainOk: balanceChainOk ?? this.balanceChainOk,
      gapBeforeAmount: gapBeforeAmount ?? this.gapBeforeAmount,
      needsReview: needsReview ?? this.needsReview,
      changeSeq: changeSeq ?? this.changeSeq,
      isDirty: isDirty ?? this.isDirty,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'category_id': categoryId,
      'type': type,
      'amount': amount,
      'balance_after': balanceAfter,
      'counterparty': counterparty,
      'reference': reference,
      'note': note,
      'occurred_at': occurredAt.toIso8601String(),
      'source': source,
      'parse_confidence': parseConfidence,
      'dedupe_key': dedupeKey,
      'raw_body': rawBody,
      'sender': sender,
      'balance_chain_ok': balanceChainOk == null ? null : (balanceChainOk! ? 1 : 0),
      'gap_before_amount': gapBeforeAmount,
      'needs_review': needsReview ? 1 : 0,
      'change_seq': changeSeq,
      'is_dirty': isDirty ? 1 : 0,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory TransactionEntity.fromMap(Map<String, dynamic> map) {
    return TransactionEntity(
      id: map['id'] as String,
      accountId: map['account_id'] as String,
      categoryId: map['category_id'] as String?,
      type: map['type'] as String,
      amount: (map['amount'] as num).toDouble(),
      balanceAfter: (map['balance_after'] as num?)?.toDouble(),
      counterparty: map['counterparty'] as String?,
      reference: map['reference'] as String?,
      note: map['note'] as String?,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      source: map['source'] as String,
      parseConfidence: (map['parse_confidence'] as num?)?.toDouble(),
      dedupeKey: map['dedupe_key'] as String?,
      rawBody: map['raw_body'] as String?,
      sender: map['sender'] as String?,
      balanceChainOk: map['balance_chain_ok'] == null
          ? null
          : (map['balance_chain_ok'] == 1 || map['balance_chain_ok'] == true),
      gapBeforeAmount: (map['gap_before_amount'] as num?)?.toDouble(),
      needsReview: map['needs_review'] == 1 || map['needs_review'] == true,
      changeSeq: (map['change_seq'] as num?)?.toInt() ?? 0,
      isDirty: map['is_dirty'] == 1 || map['is_dirty'] == true,
      deletedAt: map['deleted_at'] == null ? null : DateTime.parse(map['deleted_at'] as String),
    );
  }
}
