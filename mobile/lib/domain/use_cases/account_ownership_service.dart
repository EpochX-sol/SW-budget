/// Resolves partial bank account masks (e.g. `1000****4122`, `*4122`, `...7890`)
/// against registered user accounts to prevent multi-account collisions.
class AccountOwnershipService {
  /// Checks whether a full account number satisfies a masked representation.
  static bool matchesMask(String fullAccountNumber, String mask) {
    final cleanFull = fullAccountNumber.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final cleanMask = mask.replaceAll(RegExp(r'\s+'), '').toLowerCase();

    if (cleanFull == cleanMask) return true;
    if (cleanMask.isEmpty) return false;

    // Split on mask characters (*, ., x, X, -)
    final parts = cleanMask.split(RegExp(r'[\*\.xX\-]+')).where((p) => p.isNotEmpty).toList();

    if (parts.isEmpty) {
      // Pure mask with no digits
      return true;
    }

    if (parts.length == 1) {
      // Either prefix or suffix
      final part = parts.first;
      if (cleanMask.startsWith('*') || cleanMask.startsWith('.') || cleanMask.startsWith('x')) {
        return cleanFull.endsWith(part);
      } else {
        return cleanFull.startsWith(part);
      }
    }

    // Has both prefix and suffix (e.g. 1000****4122)
    final prefix = parts.first;
    final suffix = parts.last;

    return cleanFull.startsWith(prefix) && cleanFull.endsWith(suffix);
  }

  /// Resolves an ambiguous account mask against known user accounts for the bank.
  ///
  /// Returns the matching account ID if unambiguous.
  /// Returns `null` if zero accounts match or multiple accounts match (quarantine under "Other Transactions").
  static String? resolveAccountId({
    required List<Map<String, dynamic>> userAccounts,
    required String? accountMask,
    String? bankNameOrProvider,
  }) {
    if (userAccounts.isEmpty) return null;

    // Filter accounts by provider/bank if provided
    List<Map<String, dynamic>> candidateAccounts = userAccounts;
    if (bankNameOrProvider != null && bankNameOrProvider.isNotEmpty) {
      final pLower = bankNameOrProvider.toLowerCase();
      final filtered = userAccounts.where((a) {
        final prov = (a['provider'] ?? a['bank'] ?? '').toString().toLowerCase();
        return prov.contains(pLower) || pLower.contains(prov);
      }).toList();

      if (filtered.isNotEmpty) {
        candidateAccounts = filtered;
      }
    }

    // If user has only 1 account for this bank, and no conflicting mask
    if (candidateAccounts.length == 1) {
      if (accountMask == null || accountMask.trim().isEmpty) {
        return candidateAccounts.first['id']?.toString();
      }
      final accNum = (candidateAccounts.first['account_number'] ?? candidateAccounts.first['accountMask'] ?? '').toString();
      if (accNum.isEmpty || matchesMask(accNum, accountMask)) {
        return candidateAccounts.first['id']?.toString();
      }
      return null;
    }

    // Multiple accounts exist: require unambiguous mask matching
    if (accountMask == null || accountMask.trim().isEmpty) {
      // Cannot differentiate -> quarantine
      return null;
    }

    final matched = candidateAccounts.where((a) {
      final accNum = (a['account_number'] ?? a['accountMask'] ?? '').toString();
      return accNum.isNotEmpty && matchesMask(accNum, accountMask);
    }).toList();

    if (matched.length == 1) {
      return matched.first['id']?.toString();
    }

    // Zero or multiple matches -> quarantine under "Other Transactions"
    return null;
  }
}
