/// Classifies SMS messages that look financial but are not ledger entries.
/// Ports Totals' production classifier to prevent non-ledger notices from entering the budget.
class SmsMessageClassifier {
  SmsMessageClassifier._();

  static final RegExp _telebirrAtmAuthorization = RegExp(
    r'\bATM\s+withdraw(?:al)?\s+secret\s+code\s+is\s+(\d{4,8})\b',
    caseSensitive: false,
  );

  static final List<RegExp> _telebirrAirtimeReceiptPatterns = <RegExp>[
    RegExp(
      r'you\s+have\s+received\s+ETB\s+[\d,.]+\s+airtime\s+from\s+\S+[\s\S]*?transaction\s+number\s+is\s+([A-Z0-9@-]+)',
      caseSensitive: false,
    ),
    RegExp(
      r'[\d,.]+\s+ብር[\s\S]*?ተሞልቶሎታል[\s\S]*?ቁጥርዎ\s+([A-Z0-9@-]+)',
      caseSensitive: false,
    ),
    RegExp(
      r'ተሞልቶሎታል[\s\S]*?ቁጥርዎ',
      caseSensitive: false,
    ),
  ];

  /// Telebirr sends this authorization notice before an ATM withdrawal is
  /// completed. It contains an amount and code, but no money has moved yet.
  static bool isTelebirrAtmAuthorization(String messageBody) {
    return _telebirrAtmAuthorization.hasMatch(messageBody);
  }

  /// Telebirr sends the recipient phone an airtime delivery acknowledgement.
  /// Airtime was delivered to the mobile line, but the wallet E-Money balance
  /// was NOT credited or debited on the recipient end. Treating this as a transaction
  /// invents fake income/expense and corrupts the ledger.
  static bool isTelebirrAirtimeReceipt(String messageBody) {
    for (final pattern in _telebirrAirtimeReceiptPatterns) {
      if (pattern.hasMatch(messageBody)) return true;
    }
    return false;
  }

  /// Checks if message should be ignored as a non-ledger notice.
  static bool isNonLedgerNotice(String messageBody) {
    return isTelebirrAtmAuthorization(messageBody) || isTelebirrAirtimeReceipt(messageBody);
  }
}
