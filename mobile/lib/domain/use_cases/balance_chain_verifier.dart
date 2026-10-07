/// Result of evaluating mathematical balance-chain integrity between successive transactions
class BalanceChainResult {
  final bool? isChainOk;
  final double? gapAmount;
  final bool needsReview;
  final String? debugReason;

  const BalanceChainResult({
    required this.isChainOk,
    this.gapAmount,
    this.needsReview = false,
    this.debugReason,
  });

  bool get isVerified => isChainOk == true;
  bool get isDiscrepancy => isChainOk == false;
  bool get isUnchecked => isChainOk == null;
}

/// Evaluates running balance continuity: prev_balance ± amount == current_balance
class BalanceChainVerifier {
  static const double tolerance = 0.01;

  /// Verifies balance continuity for [current] relative to [previous]
  static BalanceChainResult verify({
    required double amount,
    required String type, // 'expense', 'income', 'transfer'
    required double? currentBalanceAfter,
    required double? previousBalanceAfter,
  }) {
    // 1. If current transaction does not report balanceAfter, we cannot verify
    if (currentBalanceAfter == null) {
      return const BalanceChainResult(
        isChainOk: null,
        needsReview: false,
        debugReason: 'Current transaction has no balanceAfter reported',
      );
    }

    // 2. If there is no previous balance baseline, establish initial anchor
    if (previousBalanceAfter == null) {
      return const BalanceChainResult(
        isChainOk: null,
        needsReview: false,
        debugReason: 'No preceding balance found for account anchor',
      );
    }

    // 3. Compute expected balance after
    double expectedBalance;
    if (type.toLowerCase() == 'expense' || type.toLowerCase() == 'transfer') {
      expectedBalance = previousBalanceAfter - amount;
    } else if (type.toLowerCase() == 'income') {
      expectedBalance = previousBalanceAfter + amount;
    } else {
      expectedBalance = previousBalanceAfter;
    }

    // 4. Compute discrepancy difference
    final discrepancy = (currentBalanceAfter - expectedBalance).abs();

    if (discrepancy <= tolerance) {
      return const BalanceChainResult(
        isChainOk: true,
        gapAmount: null,
        needsReview: false,
        debugReason: 'Balance chain arithmetic verified within 0.01 ETB tolerance',
      );
    } else {
      // Round gap amount to 2 decimal places
      final formattedGap = (discrepancy * 100).round() / 100.0;
      return BalanceChainResult(
        isChainOk: false,
        gapAmount: formattedGap,
        needsReview: true,
        debugReason:
            'Discrepancy detected: Expected $expectedBalance ETB but bank reported $currentBalanceAfter ETB (Gap: $formattedGap ETB)',
      );
    }
  }
}
