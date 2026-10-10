/// Heuristic token fallback parser ensuring unpatterned Ethiopian bank SMS messages
/// extract amounts, directions, balances, and references without dropping records.
class FallbackSmsParser {
  static Map<String, dynamic>? extract({
    required String messageBody,
    required String senderAddress,
    DateTime? messageDate,
  }) {
    final clean = messageBody.trim();
    final lower = clean.toLowerCase();

    // 1. Determine Transaction Direction
    String type = 'expense';
    if (lower.contains('credited') ||
        lower.contains('received') ||
        lower.contains('deposited') ||
        lower.contains('ገቢ') ||
        lower.contains('ተቀብለዋል')) {
      type = 'income';
    } else if (lower.contains('debited') ||
        lower.contains('transferred') ||
        lower.contains('paid') ||
        lower.contains('withdrawn') ||
        lower.contains('ተቀንሷል') ||
        lower.contains('ተከፍሏል')) {
      type = 'expense';
    } else {
      // If no explicit cue, check if it's financial at all
      if (!lower.contains('etb') && !lower.contains('birr') && !lower.contains('ብር')) {
        return null;
      }
    }

    // 2. Extract Amount
    double? amount;
    final amountPatterns = [
      RegExp(r'(?:etb|birr|ብር)\s*([0-9,]+(?:\.[0-9]+)?)', caseSensitive: false),
      RegExp(r'([0-9,]+(?:\.[0-9]+)?)\s*(?:etb|birr|ብር)', caseSensitive: false),
      RegExp(r'(?:debited|credited|with|for)\s*([0-9,]+(?:\.[0-9]+)?)', caseSensitive: false),
    ];

    for (final p in amountPatterns) {
      final match = p.firstMatch(clean);
      if (match != null) {
        final raw = match.group(1)?.replaceAll(',', '').trim();
        if (raw != null) {
          amount = double.tryParse(raw);
          if (amount != null && amount > 0) break;
        }
      }
    }

    if (amount == null) {
      return null; // Cannot parse without at least an amount
    }

    // 3. Extract Balance After
    double? balanceAfter;
    final balancePatterns = [
      RegExp(r'(?:current balance|available balance|balance|bal|ቀሪ ሂሳብ)(?:\s+is)?:?\s*(?:etb|birr|ብር)?\s*([0-9,]+(?:\.[0-9]+)?)', caseSensitive: false),
      RegExp(r'(?:bal|balance)[:\s]+([0-9,]+(?:\.[0-9]+)?)', caseSensitive: false),
    ];

    for (final p in balancePatterns) {
      final match = p.firstMatch(clean);
      if (match != null) {
        final raw = match.group(1)?.replaceAll(',', '').trim();
        if (raw != null) {
          balanceAfter = double.tryParse(raw);
          if (balanceAfter != null) break;
        }
      }
    }

    // 4. Extract Reference
    String? reference;
    final refPattern = RegExp(
      r'(?:txn id|txn|transaction id|ref no|ref|id|የግብይት ቁጥር)[:.]?\s*([A-Za-z0-9_-]+)',
      caseSensitive: false,
    );
    final refMatch = refPattern.firstMatch(clean);
    if (refMatch != null) {
      reference = refMatch.group(1)?.trim();
    }

    // 5. Extract Counterparty
    String? counterparty;
    final counterpartyPatterns = [
      RegExp(r'(?:to|paid to|transferred to|ለ)\s+([A-Za-z0-9\u1200-\u137F\s]+?)(?:on|\.|,|at|ref|txn)', caseSensitive: false),
      RegExp(r'(?:from|received from|ከ)\s+([A-Za-z0-9\u1200-\u137F\s]+?)(?:on|\.|,|at|ref|txn)', caseSensitive: false),
    ];

    for (final p in counterpartyPatterns) {
      final match = p.firstMatch(clean);
      if (match != null) {
        final val = match.group(1)?.trim();
        if (val != null && val.isNotEmpty && !val.toLowerCase().contains('your account')) {
          counterparty = val;
          break;
        }
      }
    }

    // 6. Extract Masked Account Number
    String? accountMask;
    final accPattern = RegExp(
      r'(?:account|acc|a/c|ሂሳብ ቁጥር)[:\s]+([0-9\*\.xX\-]+)',
      caseSensitive: false,
    );
    final accMatch = accPattern.firstMatch(clean);
    if (accMatch != null) {
      accountMask = accMatch.group(1)?.trim();
    }

    return {
      'type': type,
      'amount': amount,
      'balanceAfter': balanceAfter,
      'reference': reference,
      'counterparty': counterparty,
      'accountMask': accountMask,
      'isFallback': true,
      'parseConfidence': 0.65,
    };
  }
}
