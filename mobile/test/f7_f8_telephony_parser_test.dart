import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sw_budget/data/parser/financial_parser.dart';
import 'package:sw_budget/data/parser/pattern_parser.dart';
import 'package:sw_budget/data/parser/fallback_sms_parser.dart';
import 'package:sw_budget/data/parser/normalizer/bank_sender_matcher.dart';
import 'package:sw_budget/data/sms/models/raw_financial_message.dart';
import 'package:sw_budget/data/sms/sources/sms_transaction_source.dart';
import 'package:sw_budget/domain/use_cases/account_ownership_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestones F7 & F8: Headless Telephony, 8-Bank Integration & Named Regex Parser', () {
    late String patternsJson;
    late String banksJson;
    late PatternParser patternParser;

    setUpAll(() async {
      final patternsFile = File('assets/templates/sms_patterns.json');
      if (await patternsFile.exists()) {
        patternsJson = await patternsFile.readAsString();
        banksJson = await File('assets/templates/banks.json').readAsString();
      } else {
        patternsJson = await File('../assets/templates/sms_patterns.json').readAsString();
        banksJson = await File('../assets/templates/banks.json').readAsString();
      }

      patternParser = PatternParser.fromJson(
        patternsJson: patternsJson,
        banksJson: banksJson,
      );
    });

    // ─────────────────────────────────────────────────────────────
    // Milestone F7: Telephony & 8-Bank Sender Matcher
    // ─────────────────────────────────────────────────────────────
    group('Milestone F7: 8-Bank Sender Whitelist & Ingestion', () {
      test('identifies all 8 Ethiopian banking sender identifiers and shortcodes', () {
        expect(BankSenderMatcher.isRelevantSender('CBE'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('cbe_birr'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('889'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('telebirr'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('127'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('BOA'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('Abyssinia'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('AwashBank'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('DashenBank'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('AmharaBank'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('NibBank'), isTrue);
        expect(BankSenderMatcher.isRelevantSender('ZemenBank'), isTrue);

        // Rejects non-financial spam
        expect(BankSenderMatcher.isRelevantSender('EthioTelecomPromo'), isFalse);
        expect(BankSenderMatcher.isRelevantSender('TikTok'), isFalse);
        expect(BankSenderMatcher.isRelevantSender('Google'), isFalse);
      });

      test('filters messages using whitelist senders with bank code resolution', () {
        final whitelist = ['CBE', 'telebirr'];
        expect(BankSenderMatcher.matchesWhitelist('CBE', whitelist, patternParser.banks), isTrue);
        expect(BankSenderMatcher.matchesWhitelist('127', whitelist, patternParser.banks), isTrue);
        expect(BankSenderMatcher.matchesWhitelist('telebirr', whitelist, patternParser.banks), isTrue);
        expect(BankSenderMatcher.matchesWhitelist('BOA', whitelist, patternParser.banks), isFalse);
      });

      test('SmsTransactionSource streams simulated messages without crashing', () async {
        final source = SmsTransactionSource();
        final rawMsg = RawFinancialMessage(
          id: 'test_sms_101',
          sender: 'CBE',
          body: 'Dear customer, you have transferred ETB 450.00 to Abebe. Bal is ETB 12,500.00. Ref: FT2601938.',
          receivedAt: DateTime(2026, 10, 10, 10, 30),
          source: 'sms',
        );

        final futureMessage = source.messageStream.first;
        source.injectSimulatedMessage(rawMsg);
        final received = await futureMessage;

        expect(received.id, 'test_sms_101');
        expect(received.sender, 'CBE');
        expect(received.body, contains('ETB 450.00'));
        source.dispose();
      });
    });

    // ─────────────────────────────────────────────────────────────
    // Milestone F8: Totals 3,238-Line Named Regex Parser
    // ─────────────────────────────────────────────────────────────
    group('Milestone F8: PatternParser & Named Capture Groups', () {
      test('successfully loads 215 patterns and 14 Ethiopian banks from Totals JSON bundle', () {
        expect(patternParser.patterns.length, 215);
        expect(patternParser.banks.length, 14);
      });

      test('parses CBE debit transaction with named groups (amount, balance, reference, counterparty, fees)', () {
        const cbeSms = 'You have transferred ETB 1,250.00 to Aster Bedilu on 10/10/2026 at 10:30:00 from your account 1000****1234. Service charge of ETB 10.00 and VAT(15%) of ETB 1.50 and Disaster Fund (5%) of ETB 0.50, with a total of ETB 1,262.00. Current Balance is ETB 8,750.50. https://apps.cbe.com.et:100/?id=FT2610109988';

        final result = patternParser.extractTransactionDetails(
          messageBody: cbeSms,
          senderAddress: 'CBE',
          messageDate: DateTime.now(),
        );

        expect(result, isNotNull);
        expect(result!['amount'], 1250.00);
        expect(result['balanceAfter'], 8750.50);
        expect(result['type'], 'expense');
        expect(result['reference'], 'FT2610109988');
        expect(result['counterparty'], 'Aster Bedilu');
        expect(result['accountMask'], contains('1234'));
        expect(result['serviceCharge'], 10.00);
        expect(result['vat'], 1.50);
        expect(result['disasterFund'], 0.50);
        expect(result['fee'], 12.00);
      });

      test('parses Telebirr P2P transfer with service fee, VAT, reference and balance', () {
        const telebirrSms = 'transferred ETB 350.00 to Kaldis Coffee (0911223344). The transaction number is CR26101088. The service fee is ETB 2.00 and 15% VAT on the service fee is ETB 0.30. Your balance is ETB 2,150.00.';

        final result = patternParser.extractTransactionDetails(
          messageBody: telebirrSms,
          senderAddress: 'telebirr',
          messageDate: DateTime.now(),
        );

        expect(result, isNotNull);
        expect(result!['amount'], 350.00);
        expect(result['balanceAfter'], 2150.00);
        expect(result['reference'], 'CR26101088');
        expect(result['serviceCharge'], 2.00);
        expect(result['vat'], 0.30);
      });

      test('FallbackSmsParser extracts financial details when all regex patterns fail', () {
        const novelSms = 'Special bank update: A transfer of ETB 780.25 was credited to your account from Almaz Tesfaye. Bal is ETB 15,300.00. Ref no: TXN-UNKNOWN-99.';

        final fallback = FallbackSmsParser.extract(
          messageBody: novelSms,
          senderAddress: 'UnknownBank',
        );

        expect(fallback, isNotNull);
        expect(fallback!['amount'], 780.25);
        expect(fallback['balanceAfter'], 15300.00);
        expect(fallback['type'], 'income');
        expect(fallback['isFallback'], isTrue);
        expect(fallback['reference'], 'TXN-UNKNOWN-99');
      });

      test('FinancialParser integrates both Named Patterns and Fallback Scanner cleanly', () {
        final parser = FinancialParser();
        parser.loadNamedPatterns(
          patternsJson: patternsJson,
          banksJson: banksJson,
        );

        // 1. Matched by Named Regex (CBE)
        const cbeSms = 'You have transferred ETB 500.00 to Solomon on 10/10/2026 at 11:00:00 from your account 1000****5555. Service charge of ETB 5.00 and VAT(15%) of ETB 0.75 and Disaster Fund (5%) of ETB 0.25, with a total of ETB 506.00. Current Balance is ETB 5,000.00. https://apps.cbe.com.et:100/?id=FT2610101111';
        final r1 = parser.parse(
          sender: 'CBE',
          body: cbeSms,
          receivedAt: DateTime.now(),
        );
        expect(r1.isSuccess, isTrue);
        expect(r1.transaction!.amount, 500.00);
        expect(r1.transaction!.fee, 6.00);

        // 2. Novel format recovered by Fallback Scanner
        final r2 = parser.parse(
          sender: 'NewCoop',
          body: 'Notice: ETB 1,400.00 was paid to Rent Manager. Bal is ETB 9,000.00. ID: RENT-101.',
          receivedAt: DateTime.now(),
        );
        expect(r2.isSuccess, isTrue);
        expect(r2.transaction!.amount, 1400.00);
        expect(r2.transaction!.needsReview, isTrue);
      });
    });

    // ─────────────────────────────────────────────────────────────
    // Milestone F8: Account Ownership Solver & Quarantine Logic
    // ─────────────────────────────────────────────────────────────
    group('Milestone F8: AccountOwnershipService', () {
      test('matchesMask validates exact, prefix, suffix, and wildcard patterns', () {
        expect(AccountOwnershipService.matchesMask('100012345678', '1000****5678'), isTrue);
        expect(AccountOwnershipService.matchesMask('100012345678', '...5678'), isTrue);
        expect(AccountOwnershipService.matchesMask('100012345678', '1000...'), isTrue);
        expect(AccountOwnershipService.matchesMask('100012345678', '100012345678'), isTrue);
        expect(AccountOwnershipService.matchesMask('100012345678', '1000****9999'), isFalse);
      });

      test('resolves unambiguously when user has only one account for that bank', () {
        final accounts = [
          {'id': 'acc_cbe_1', 'provider': 'CBE', 'account_number': '100012345678'},
          {'id': 'acc_tele_1', 'provider': 'TELEBIRR', 'account_number': '0911223344'},
        ];

        final resolved = AccountOwnershipService.resolveAccountId(
          userAccounts: accounts,
          accountMask: '1000****5678',
          bankNameOrProvider: 'CBE',
        );

        expect(resolved, 'acc_cbe_1');
      });

      test('resolves unambiguously when user has multiple accounts and mask matches only one', () {
        final accounts = [
          {'id': 'acc_cbe_personal', 'provider': 'CBE', 'account_number': '100011112222'},
          {'id': 'acc_cbe_business', 'provider': 'CBE', 'account_number': '100099998888'},
        ];

        final resolved = AccountOwnershipService.resolveAccountId(
          userAccounts: accounts,
          accountMask: '1000****2222',
          bankNameOrProvider: 'CBE',
        );

        expect(resolved, 'acc_cbe_personal');
      });

      test('quarantines (returns null) when mask is ambiguous or matches zero accounts', () {
        final accounts = [
          {'id': 'acc_cbe_1', 'provider': 'CBE', 'account_number': '100012345678'},
          {'id': 'acc_cbe_2', 'provider': 'CBE', 'account_number': '100099995678'},
        ];

        // Both end with 5678 -> ambiguous -> quarantine
        final ambiguousResult = AccountOwnershipService.resolveAccountId(
          userAccounts: accounts,
          accountMask: '...5678',
          bankNameOrProvider: 'CBE',
        );
        expect(ambiguousResult, isNull);

        // Missing mask with multiple accounts -> quarantine
        final missingMaskResult = AccountOwnershipService.resolveAccountId(
          userAccounts: accounts,
          accountMask: null,
          bankNameOrProvider: 'CBE',
        );
        expect(missingMaskResult, isNull);
      });
    });
  });
}
