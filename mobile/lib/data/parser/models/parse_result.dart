import 'parsed_transaction.dart';

/// The result returned by FinancialParser.
class ParseResult {
  final bool isSuccess;
  final ParsedTransaction? transaction;
  final String? failureReason;
  final bool isFinancial;

  const ParseResult._({
    required this.isSuccess,
    this.transaction,
    this.failureReason,
    required this.isFinancial,
  });

  factory ParseResult.success(ParsedTransaction transaction) => ParseResult._(
        isSuccess: true,
        transaction: transaction,
        isFinancial: true,
      );

  factory ParseResult.unparsed(String reason, {bool isFinancial = true}) =>
      ParseResult._(
        isSuccess: false,
        failureReason: reason,
        isFinancial: isFinancial,
      );

  factory ParseResult.nonFinancial() => const ParseResult._(
        isSuccess: false,
        failureReason: 'Non-financial message',
        isFinancial: false,
      );

  @override
  String toString() => isSuccess
      ? 'ParseResult.success(${transaction?.provider} ${transaction?.amount})'
      : 'ParseResult.unparsed($failureReason)';
}
