import 'package:flutter_test/flutter_test.dart';
import 'package:sw_budget/domain/use_cases/balance_chain_verifier.dart';

void main() {
  group('BalanceChainVerifier Mathematical Trust Tests', () {
    test('correctly verifies continuous expense deduction', () {
      final result = BalanceChainVerifier.verify(
        amount: 350.50,
        type: 'expense',
        currentBalanceAfter: 9649.50,
        previousBalanceAfter: 10000.00,
      );

      expect(result.isVerified, isTrue);
      expect(result.isChainOk, isTrue);
      expect(result.gapAmount, isNull);
      expect(result.needsReview, isFalse);
    });

    test('correctly verifies continuous income addition', () {
      final result = BalanceChainVerifier.verify(
        amount: 2500.00,
        type: 'income',
        currentBalanceAfter: 12149.50,
        previousBalanceAfter: 9649.50,
      );

      expect(result.isVerified, isTrue);
      expect(result.isChainOk, isTrue);
      expect(result.gapAmount, isNull);
      expect(result.needsReview, isFalse);
    });

    test('detects missing ATM withdrawal gap discrepancy', () {
      // User had 10,000 ETB. Withdrew 1,000 ETB cash at ATM (no SMS received).
      // Then spent 200 ETB on groceries via Telebirr/CBE (reported balance 8,800 ETB).
      final result = BalanceChainVerifier.verify(
        amount: 200.00,
        type: 'expense',
        currentBalanceAfter: 8800.00,
        previousBalanceAfter: 10000.00,
      );

      expect(result.isDiscrepancy, isTrue);
      expect(result.isChainOk, isFalse);
      expect(result.gapAmount, 1000.00);
      expect(result.needsReview, isTrue);
      expect(result.debugReason, contains('Gap: 1000.0 ETB'));
    });

    test('tolerates sub-cent floating-point precision error within 0.01 tolerance', () {
      // 0.005 difference due to floating point IEEE arithmetic
      final result = BalanceChainVerifier.verify(
        amount: 100.00,
        type: 'expense',
        currentBalanceAfter: 899.995,
        previousBalanceAfter: 1000.00,
      );

      expect(result.isVerified, isTrue);
      expect(result.gapAmount, isNull);
    });

    test('sets anchor state when no preceding balance is available', () {
      final result = BalanceChainVerifier.verify(
        amount: 500.00,
        type: 'expense',
        currentBalanceAfter: 4500.00,
        previousBalanceAfter: null,
      );

      expect(result.isUnchecked, isTrue);
      expect(result.gapAmount, isNull);
      expect(result.needsReview, isFalse);
    });

    test('sets unchecked state when current transaction does not report balance', () {
      final result = BalanceChainVerifier.verify(
        amount: 50.00,
        type: 'expense',
        currentBalanceAfter: null,
        previousBalanceAfter: 4500.00,
      );

      expect(result.isUnchecked, isTrue);
      expect(result.gapAmount, isNull);
      expect(result.needsReview, isFalse);
    });
  });
}
