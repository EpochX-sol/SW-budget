class Reimbursement {
  final String id;
  final String userId;
  final String expenseTxnId;
  final String creditTxnId;
  final double amount;
  final String? note;
  final DateTime createdAt;

  const Reimbursement({
    required this.id,
    required this.userId,
    required this.expenseTxnId,
    required this.creditTxnId,
    required this.amount,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'expense_txn_id': expenseTxnId,
        'credit_txn_id': creditTxnId,
        'amount': amount,
        'note': note,
        'created_at': createdAt.toIso8601String(),
      };

  factory Reimbursement.fromJson(Map<String, dynamic> json) {
    return Reimbursement(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      expenseTxnId: json['expense_txn_id'] as String,
      creditTxnId: json['credit_txn_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
