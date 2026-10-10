import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sw_budget/data/parser/sms_message_classifier.dart';
import 'package:sw_budget/data/parser/financial_parser.dart';
import 'package:sw_budget/data/parser/pattern_parser.dart';
import 'package:sw_budget/data/local/app_database.dart';
import 'package:sw_budget/data/sms/ingestion_pipeline.dart';
import 'package:sw_budget/data/sms/models/raw_financial_message.dart';

void main() {
  group('Bugfix Verification: Balance Gap, Airtime Rejection, and Direction Alignment', () {
    late FinancialParser parser;
    late AppDatabase db;

    setUpAll(() async {
      parser = FinancialParser();
      String patternsJson;
      String banksJson;
      if (File('assets/templates/sms_patterns.json').existsSync()) {
        patternsJson = File('assets/templates/sms_patterns.json').readAsStringSync();
        banksJson = File('assets/templates/banks.json').readAsStringSync();
      } else {
        patternsJson = File('../assets/templates/sms_patterns.json').readAsStringSync();
        banksJson = File('../assets/templates/banks.json').readAsStringSync();
      }
      parser.loadNamedPatterns(patternsJson: patternsJson, banksJson: banksJson);
    });

    setUp(() {
      db = AppDatabase.openInMemory();
    });

    tearDown(() {
      db.close();
    });

    test('1. Non-ledger Telebirr airtime receipt is rejected and does not enter ledger', () {
      const airtimeReceiptAm = '100 ብር የአየር ሰዓት ተሞልቶሎታል:: የግብይት ቁጥርዎ 100000987654::';
      const airtimeReceiptEn = 'you have received ETB 100.00 airtime from 251911223344 transaction number is REF12345';
      const atmAuth = 'ATM withdraw secret code is 884192';

      expect(SmsMessageClassifier.isNonLedgerNotice(airtimeReceiptAm), isTrue);
      expect(SmsMessageClassifier.isNonLedgerNotice(airtimeReceiptEn), isTrue);
      expect(SmsMessageClassifier.isNonLedgerNotice(atmAuth), isTrue);

      final resAm = parser.parse(sender: 'telebirr', body: airtimeReceiptAm, receivedAt: DateTime.now());
      expect(resAm.isFinancial, isFalse);

      final resAtm = parser.parse(sender: 'telebirr', body: atmAuth, receivedAt: DateTime.now());
      expect(resAtm.isFinancial, isFalse);
    });

    test('2. Telebirr Airtime recharge is correctly classified as EXPENSE (DEBIT) with phone counterparty', () {
      const rechargeSms =
          'recharged ETB 5.00 airtime for 251910106422 on 10/10/2026 08:13:00. transaction number is TXN998811. balance is ETB 513.98';

      final res = parser.parse(sender: 'telebirr', body: rechargeSms, receivedAt: DateTime.parse('2026-10-10 08:13:00'));
      expect(res.isSuccess, isTrue);
      final txn = res.transaction!;

      expect(txn.type, equals('expense')); // DEBIT!
      expect(txn.amount, equals(5.0));
      expect(txn.balanceAfter, equals(513.98));
      expect(txn.counterparty, equals('251910106422'));
      expect(txn.reference, equals('TXN998811'));
    });

    test('3. Chronological ingestion correctly maintains running balance without false gap banners', () async {
      final pipeline = IngestionPipeline(
        database: db,
        parser: parser,
        sources: [],
      );

      // Event 1 (earlier): TSION KEDIR - 500 ETB, Bal 643.98
      final msg1 = RawFinancialMessage(
        id: 'msg_1',
        sender: 'telebirr',
        body: 'transferred ETB 500.00 to TSION KEDIR on 08/10/2026 19:38:00 transaction number is REF1 balance is ETB 643.98',
        receivedAt: DateTime.parse('2026-10-08 19:38:00'),
        source: 'sms',
      );

      // Event 2 (next): Voice Monthly - 100 ETB, Bal 543.98 (643.98 - 100 = 543.98 -> PERFECT CHAIN!)
      final msg2 = RawFinancialMessage(
        id: 'msg_2',
        sender: 'telebirr',
        body: 'transferred ETB 100.00 to Voice Monthly on 09/10/2026 08:43:00 transaction number is REF2 balance is ETB 543.98',
        receivedAt: DateTime.parse('2026-10-09 08:43:00'),
        source: 'sms',
      );

      // Event 3 (latest): Internet Package - 25 ETB, Bal 518.98
      final msg3 = RawFinancialMessage(
        id: 'msg_3',
        sender: 'telebirr',
        body: 'transferred ETB 25.00 to Internet Package on 10/10/2026 08:09:00 transaction number is REF3 balance is ETB 518.98',
        receivedAt: DateTime.parse('2026-10-10 08:09:00'),
        source: 'sms',
      );

      // Event 4 (most recent): Airtime Recharge - 5 ETB, Bal 513.98
      final msg4 = RawFinancialMessage(
        id: 'msg_4',
        sender: 'telebirr',
        body: 'recharged ETB 5.00 airtime for 251910106422 on 10/10/2026 08:13:00. transaction number is REF4. balance is ETB 513.98',
        receivedAt: DateTime.parse('2026-10-10 08:13:00'),
        source: 'sms',
      );

      // Ingest in chronological order
      await pipeline.processMessage(msg1);
      final r2 = await pipeline.processMessage(msg2);
      final r3 = await pipeline.processMessage(msg3);
      final r4 = await pipeline.processMessage(msg4);

      // Verified: NO false gaps!
      expect(r2?['balance_chain_ok'], equals(1));
      expect(r2?['gap_before_amount'], isNull);

      // Account's last known balance matches the latest event (513.98) exactly like Totals!
      final accounts = db.getAccounts();
      final telebirrAcc = accounts.firstWhere((a) => (a['provider'] as String).contains('TELEBIRR'));
      expect(telebirrAcc['last_known_balance'], equals(513.98));
    });

    test('4. repairCorruptedTransactionsAndBalances purges false 100k non-ledger rows', () {
      // Insert fake corrupted transaction like the one in screenshot
      final accId = 'acc_test_1';
      db.upsertAccount(id: accId, provider: 'TELEBIRR', name: 'Telebirr Wallet', lastKnownBalance: 0.0);

      db.upsertTransaction(
        id: 'corrupted_1',
        accountId: accId,
        type: 'expense',
        amount: 100000.0,
        balanceAfter: null,
        counterparty: 'ብር 100',
        reference: 'NON_LEDGER_RECEIPT',
        occurredAt: DateTime.parse('2026-10-09 09:35:00'),
        source: 'sms',
        rawBody: '100 ብር የአየር ሰዓት ተሞልቶሎታል:: ቁጥርዎ 100000000',
        balanceChainOk: false,
        gapBeforeAmount: 125.0,
      );

      expect(db.getTransactions().length, equals(1));

      // Run repair
      db.repairCorruptedTransactionsAndBalances();

      // Corrupted 100k row deleted!
      expect(db.getTransactions().length, equals(0));
    });
  });
}
