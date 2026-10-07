/// Defines field extraction regex rules inside a financial template.
class TemplateFieldRules {
  final String amount;
  final String? counterparty;
  final String? balance;
  final String? reference;
  final String? date;

  const TemplateFieldRules({
    required this.amount,
    this.counterparty,
    this.balance,
    this.reference,
    this.date,
  });

  factory TemplateFieldRules.fromJson(Map<String, dynamic> json) =>
      TemplateFieldRules(
        amount: json['amount'] as String,
        counterparty: json['counterparty'] as String?,
        balance: json['balance'] as String?,
        reference: json['reference'] as String?,
        date: json['date'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'amount': amount,
        if (counterparty != null) 'counterparty': counterparty,
        if (balance != null) 'balance': balance,
        if (reference != null) 'reference': reference,
        if (date != null) 'date': date,
      };
}

/// Represents an individual regex pattern template for an institution.
class RegexTemplate {
  final String id;
  final String bank; // CBE, TELEBIRR, ABYSSINIA, etc.
  final String sender; // CBE, Telebirr, 127, etc.
  final String type; // income, expense, transfer
  final String pattern; // Root pattern to match incoming text
  final TemplateFieldRules fields;
  final int priority;

  const RegexTemplate({
    required this.id,
    required this.bank,
    required this.sender,
    required this.type,
    required this.pattern,
    required this.fields,
    this.priority = 0,
  });

  factory RegexTemplate.fromJson(Map<String, dynamic> json) => RegexTemplate(
        id: json['id'] as String,
        bank: json['bank'] as String,
        sender: json['sender'] as String,
        type: json['type'] as String,
        pattern: json['pattern'] as String,
        fields: TemplateFieldRules.fromJson(
            json['fields'] as Map<String, dynamic>),
        priority: json['priority'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bank': bank,
        'sender': sender,
        'type': type,
        'pattern': pattern,
        'fields': fields.toJson(),
        'priority': priority,
      };
}
