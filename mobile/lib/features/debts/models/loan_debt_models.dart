class ContactPerson {
  final String id;
  final String userId;
  final String name;
  final String? phoneNumber;

  const ContactPerson({
    required this.id,
    required this.userId,
    required this.name,
    this.phoneNumber,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'phone_number': phoneNumber,
      };

  factory ContactPerson.fromJson(Map<String, dynamic> json) => ContactPerson(
        id: json['id'] as String,
        userId: json['user_id'] as String? ?? '',
        name: json['name'] as String,
        phoneNumber: json['phone_number'] as String?,
      );
}

class LoanDebt {
  final String id;
  final String userId;
  final String personId;
  final String type; // 'lent' or 'borrowed'
  final double initialAmount;
  final double currentBalance;
  final DateTime? dueDate;
  final String status; // 'active' or 'settled'
  final String? note;
  final ContactPerson? person;

  const LoanDebt({
    required this.id,
    required this.userId,
    required this.personId,
    required this.type,
    required this.initialAmount,
    required this.currentBalance,
    this.dueDate,
    this.status = 'active',
    this.note,
    this.person,
  });

  bool get isSettled => currentBalance <= 0 || status == 'settled';

  LoanDebt copyWith({
    double? currentBalance,
    String? status,
  }) {
    return LoanDebt(
      id: id,
      userId: userId,
      personId: personId,
      type: type,
      initialAmount: initialAmount,
      currentBalance: currentBalance ?? this.currentBalance,
      dueDate: dueDate,
      status: status ?? this.status,
      note: note,
      person: person,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'person_id': personId,
        'type': type,
        'initial_amount': initialAmount,
        'current_balance': currentBalance,
        'due_date': dueDate?.toIso8601String(),
        'status': status,
        'note': note,
      };

  factory LoanDebt.fromJson(Map<String, dynamic> json) => LoanDebt(
        id: json['id'] as String,
        userId: json['user_id'] as String? ?? '',
        personId: json['person_id'] as String,
        type: json['type'] as String,
        initialAmount: (json['initial_amount'] as num).toDouble(),
        currentBalance: (json['current_balance'] as num).toDouble(),
        dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
        status: json['status'] as String? ?? 'active',
        note: json['note'] as String?,
      );
}

class LoanRepayment {
  final String id;
  final String loanDebtId;
  final double amount;
  final DateTime repaidAt;
  final String? note;

  const LoanRepayment({
    required this.id,
    required this.loanDebtId,
    required this.amount,
    required this.repaidAt,
    this.note,
  });
}
