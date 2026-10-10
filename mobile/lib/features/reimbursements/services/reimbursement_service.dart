import '../models/reimbursement.dart';

class ReimbursementService {
  /// Calculates the net spending amount after deducting all linked reimbursements.
  /// NetSpend = Amount - Sum(ReimbursedAmount)
  static double calculateNetSpend(double originalAmount, List<Reimbursement> reimbursements) {
    final totalReimbursed = reimbursements.fold(0.0, (sum, r) => sum + r.amount);
    final net = originalAmount - totalReimbursed;
    return net > 0 ? (net * 100).roundToDouble() / 100 : 0.0;
  }

  /// Validates whether a new credit allocation can be linked to the expense.
  /// Throws an [ArgumentError] if the new allocation exceeds the remaining unreimbursed portion.
  static void validateReimbursementAllocation({
    required double originalAmount,
    required double alreadyReimbursed,
    required double newAllocationAmount,
  }) {
    if (newAllocationAmount <= 0) {
      throw ArgumentError('Reimbursement allocation must be greater than zero');
    }
    final remainingUnreimbursed = originalAmount - alreadyReimbursed;
    if (newAllocationAmount > remainingUnreimbursed + 0.001) {
      throw ArgumentError(
        'Reimbursement of ${newAllocationAmount.toStringAsFixed(2)} ETB exceeds remaining unreimbursed amount of ${remainingUnreimbursed.toStringAsFixed(2)} ETB',
      );
    }
  }
}
