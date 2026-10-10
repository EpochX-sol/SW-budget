import 'dart:convert';
import 'models/bank.dart';
import 'models/sms_pattern.dart';
import 'normalizer/bank_sender_matcher.dart';

/// Evaluates SMS messages against Totals' 3,238-line production regex engine
/// utilizing named capture groups and fee breakdown extraction.
class PatternParser {
  final List<SmsPattern> patterns;
  final List<Bank> banks;

  PatternParser({
    required this.patterns,
    required this.banks,
  });

  /// Factory constructor to load from JSON strings
  factory PatternParser.fromJson({
    required String patternsJson,
    required String banksJson,
  }) {
    final rawPatterns = jsonDecode(patternsJson);
    final patternList = rawPatterns is Map && rawPatterns['patterns'] is List
        ? (rawPatterns['patterns'] as List)
        : (rawPatterns is List ? rawPatterns : []);

    final parsedPatterns = patternList
        .map((p) => SmsPattern.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();

    final rawBanks = jsonDecode(banksJson);
    final bankList = rawBanks is Map && rawBanks['banks'] is List
        ? (rawBanks['banks'] as List)
        : (rawBanks is List ? rawBanks : []);

    final parsedBanks = bankList
        .map((b) => Bank.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList();

    return PatternParser(
      patterns: parsedPatterns,
      banks: parsedBanks,
    );
  }

  /// Extracts transaction details using named regex capture groups.
  Map<String, dynamic>? extractTransactionDetails({
    required String messageBody,
    required String senderAddress,
    DateTime? messageDate,
  }) {
    final cleanBody = messageBody.trim();
    final senderBank = BankSenderMatcher.findBestBank(senderAddress, banks);
    if (senderBank == null) {
      return null;
    }

    final bankPatterns = patterns.where((p) => p.bankId == senderBank.id).toList();

    for (final pattern in bankPatterns) {
      try {
        final regExp = RegExp(
          pattern.regex,
          caseSensitive: false,
          multiLine: true,
          dotAll: true,
        );
        final match = regExp.firstMatch(cleanBody);

        if (match != null) {
          final extracted = <String, dynamic>{
            'bankId': pattern.bankId,
            'bankName': senderBank.name,
            'patternDescription': pattern.description,
            'sourceType': pattern.type, // CREDIT or DEBIT
            'type': pattern.type.toUpperCase().contains('CREDIT') ? 'income' : 'expense',
          };

          // 1. Amount
          if (match.groupNames.contains('amount')) {
            final cleanedAmount = _cleanNumber(match.namedGroup('amount'));
            if (cleanedAmount != null) {
              extracted['amount'] = double.tryParse(cleanedAmount);
            }
          }

          // 2. Balance
          if (match.groupNames.contains('balance')) {
            final cleanedBalance = _cleanNumber(match.namedGroup('balance'));
            if (cleanedBalance != null) {
              extracted['balanceAfter'] = double.tryParse(cleanedBalance);
            }
          }

          // 3. Account Mask
          if (match.groupNames.contains('account')) {
            final raw = match.namedGroup('account');
            if (raw != null && raw.trim().isNotEmpty) {
              extracted['accountMask'] = raw.trim();
            }
          }

          // 4. Reference
          if (match.groupNames.contains('reference')) {
            final rawRef = match.namedGroup('reference');
            if (rawRef != null && rawRef.trim().isNotEmpty) {
              extracted['reference'] = rawRef.trim();
            }
          }

          // 5. Counterparty (receiver / creditor / from / to)
          if (match.groupNames.contains('receiver')) {
            extracted['counterparty'] = match.namedGroup('receiver')?.trim();
          } else if (match.groupNames.contains('creditor')) {
            extracted['counterparty'] = match.namedGroup('creditor')?.trim();
          } else if (match.groupNames.contains('from')) {
            extracted['counterparty'] = match.namedGroup('from')?.trim();
          } else if (match.groupNames.contains('to')) {
            extracted['counterparty'] = match.namedGroup('to')?.trim();
          }

          // 6. Fee Breakdown (Service Charge, VAT, Disaster Recovery Fund)
          _assignOptionalAmount(extracted, 'serviceCharge', match, const [
            'serviceCharge',
            'ServiceCharge',
            'servicecharge',
            'service_charge'
          ]);

          _assignOptionalAmount(extracted, 'vat', match, const ['vat', 'VAT']);

          _assignOptionalAmount(extracted, 'disasterFund', match, const [
            'disasterFund',
            'DisasterFund',
            'disaster_fund'
          ]);

          // Compute total fee if service charge or VAT was extracted
          final sc = (extracted['serviceCharge'] as num?)?.toDouble() ?? 0.0;
          final vat = (extracted['vat'] as num?)?.toDouble() ?? 0.0;
          final df = (extracted['disasterFund'] as num?)?.toDouble() ?? 0.0;
          if (sc > 0 || vat > 0 || df > 0) {
            extracted['fee'] = sc + vat + df;
          }

          // Validation of required fields
          if (extracted['amount'] == null) {
            continue;
          }

          if (pattern.refRequired == true && extracted['reference'] == null) {
            continue;
          }

          return extracted;
        }
      } catch (_) {
        // Regex syntax error or unsupported group in engine; skip to next
        continue;
      }
    }

    return null;
  }

  static void _assignOptionalAmount(
    Map<String, dynamic> target,
    String key,
    RegExpMatch match,
    List<String> groupNames,
  ) {
    for (final name in groupNames) {
      if (!match.groupNames.contains(name)) continue;
      final raw = match.namedGroup(name);
      final cleaned = _cleanNumber(raw);
      if (cleaned != null) {
        final val = double.tryParse(cleaned);
        if (val != null) {
          target[key] = val;
          return;
        }
      }
    }
  }

  static String? _cleanNumber(String? input) {
    if (input == null) return null;
    String cleaned = input.replaceAll(',', '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9.]$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\.+$'), '');
    return cleaned;
  }
}
