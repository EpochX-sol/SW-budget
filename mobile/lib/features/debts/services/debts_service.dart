import '../models/loan_debt_models.dart';

class DebtsService {
  /// Records a repayment against an existing debt, automatically transitioning
  /// status to 'settled' when remaining balance reaches zero.
  static LoanDebt recordRepayment({
    required LoanDebt debt,
    required double repaymentAmount,
  }) {
    if (repaymentAmount <= 0) {
      throw ArgumentError('Repayment amount must be greater than zero');
    }
    final newBalance = (debt.currentBalance - repaymentAmount).clamp(0.0, double.infinity);
    final roundedBalance = (newBalance * 100).roundToDouble() / 100;
    final newStatus = roundedBalance <= 0 ? 'settled' : 'active';

    return debt.copyWith(
      currentBalance: roundedBalance,
      status: newStatus,
    );
  }

  /// Aggregates total lent, total borrowed, and net position.
  static Map<String, double> calculateSummary(List<LoanDebt> debts) {
    double totalLent = 0;
    double totalBorrowed = 0;

    for (final d in debts) {
      if (d.status == 'settled' || d.currentBalance <= 0) continue;
      if (d.type.toLowerCase() == 'lent') {
        totalLent += d.currentBalance;
      } else if (d.type.toLowerCase() == 'borrowed') {
        totalBorrowed += d.currentBalance;
      }
    }

    return {
      'totalLent': (totalLent * 100).roundToDouble() / 100,
      'totalBorrowed': (totalBorrowed * 100).roundToDouble() / 100,
      'netBalance': ((totalLent - totalBorrowed) * 100).roundToDouble() / 100,
    };
  }
}
