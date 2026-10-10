import '../models/bank.dart';

String normalizeBankSenderToken(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class BankSenderMatcher {
  static const Set<String> all8BankSenderTokens = {
    'cbe',
    'cbebirr',
    '889',
    'telebirr',
    '127',
    'boa',
    'abyssinia',
    'bankofabyssinia',
    'awash',
    'awashbank',
    'dashen',
    'dashenbank',
    'amhara',
    'amharabank',
    'nib',
    'nibbank',
    'zemen',
    'zemenbank',
    'coop',
    'coopbank',
    'wegagen',
    'wegagenbank',
    'mpesa',
    'ahadu',
    'siinqee',
    'hijra',
  };

  static bool isRelevantSender(String address) {
    final token = normalizeBankSenderToken(address);
    if (token.isEmpty) return false;
    for (final candidate in all8BankSenderTokens) {
      if (token.contains(candidate) || candidate.contains(token)) {
        return true;
      }
    }
    return false;
  }

  static bool matchesWhitelist(String address, List<String> whitelist, [Iterable<Bank>? banks]) {
    if (whitelist.isEmpty) return isRelevantSender(address);
    final normalized = normalizeBankSenderToken(address);
    for (final w in whitelist) {
      final nw = normalizeBankSenderToken(w);
      if (normalized.contains(nw) || nw.contains(normalized)) {
        return true;
      }
    }

    if (banks != null) {
      final bank = findBestBank(address, banks);
      if (bank != null) {
        for (final w in whitelist) {
          final nw = normalizeBankSenderToken(w);
          if (normalizeBankSenderToken(bank.name).contains(nw) ||
              normalizeBankSenderToken(bank.shortName).contains(nw)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static Bank? findBestBank(String? address, Iterable<Bank> banks) {
    final normalizedAddress = address == null ? '' : normalizeBankSenderToken(address);
    if (normalizedAddress.isEmpty) return null;

    _BankSenderMatch? bestMatch;
    for (final bank in banks) {
      final candidates = [...bank.codes, bank.shortName, bank.name];
      for (final code in candidates) {
        final normalizedCode = normalizeBankSenderToken(code);
        if (normalizedCode.isEmpty) continue;

        final matchIndex = normalizedAddress.indexOf(normalizedCode);
        if (matchIndex < 0) continue;

        final match = _BankSenderMatch(
          bank: bank,
          codeLength: normalizedCode.length,
          isExact: normalizedAddress == normalizedCode,
          startsAtBeginning: matchIndex == 0,
          unmatchedLength: normalizedAddress.length - normalizedCode.length,
        );
        if (match.isBetterThan(bestMatch)) bestMatch = match;
      }
    }

    return bestMatch?.bank;
  }
}

class _BankSenderMatch {
  final Bank bank;
  final int codeLength;
  final bool isExact;
  final bool startsAtBeginning;
  final int unmatchedLength;

  const _BankSenderMatch({
    required this.bank,
    required this.codeLength,
    required this.isExact,
    required this.startsAtBeginning,
    required this.unmatchedLength,
  });

  bool isBetterThan(_BankSenderMatch? other) {
    if (other == null) return true;
    if (isExact != other.isExact) return isExact;
    if (codeLength != other.codeLength) return codeLength > other.codeLength;
    if (startsAtBeginning != other.startsAtBeginning) {
      return startsAtBeginning;
    }
    if (unmatchedLength != other.unmatchedLength) {
      return unmatchedLength < other.unmatchedLength;
    }
    return false;
  }
}
