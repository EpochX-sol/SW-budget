import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sw_budget/data/parser/financial_parser.dart';

void main() {
  late FinancialParser parser;

  setUpAll(() {
    final bundleFile = File('assets/templates/default_bundle.json');
    final bundleJson = bundleFile.readAsStringSync();
    parser = FinancialParser();
    parser.loadTemplatesFromJson(bundleJson);
  });

  final boaMessages = [
    {
      'raw': 'Dear Samuel, your account 1*22 was credited with ETB 600.00 by  Samuel Wubalem Melesse . Available Balance: ETB 30,164.47.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26195H5ZW910104\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=CFT26195H5ZW9\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 600.00,
      'expectedBalance': 30164.47,
      'expectedType': 'income',
      'expectedRef': 'FT26195H5ZW910104',
      'expectedCounterparty': 'Samuel Wubalem Melesse',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 18,118.00. Available Balance: ETB 12,046.47.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26201V11CF04422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26201V11CF\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 18118.00,
      'expectedBalance': 12046.47,
      'expectedType': 'expense',
      'expectedRef': 'FT26201V11CF04422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 1,012.00. Available Balance: ETB 11,034.47.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26202BBN5604422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26202BBN56\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 1012.00,
      'expectedBalance': 11034.47,
      'expectedType': 'expense',
      'expectedRef': 'FT26202BBN5604422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 10,998.00. Available Balance: ETB 36.47.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26209FNVGZ04422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26209FNVGZ\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 10998.00,
      'expectedBalance': 36.47,
      'expectedType': 'expense',
      'expectedRef': 'FT26209FNVGZ04422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was credited with ETB 11,293.00 by Afework Ameya Alemu. Available Balance: ETB 11,329.47.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26212XQJCQ69965\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=CFT26212XQJCQ\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 11293.00,
      'expectedBalance': 11329.47,
      'expectedType': 'income',
      'expectedRef': 'FT26212XQJCQ69965',
      'expectedCounterparty': 'Afework Ameya Alemu',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 11,303.00. Available Balance: ETB 26.47.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26212D0ZR404422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26212D0ZR4\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 11303.00,
      'expectedBalance': 26.47,
      'expectedType': 'expense',
      'expectedRef': 'FT26212D0ZR404422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was credited with ETB 30,000.00 from Telebirr by Reference DH95N3QDKZ. Available Balance: ETB 30,026.61.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26222GWDVT10104\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=CFT26222GWDVT\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 30000.00,
      'expectedBalance': 30026.61,
      'expectedType': 'income',
      'expectedRef': 'FT26222GWDVT10104',
      'expectedCounterparty': 'Telebirr',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 8,012.00. Available Balance: ETB 22,014.61.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26225YKP2004422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26225YKP20\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 8012.00,
      'expectedBalance': 22014.61,
      'expectedType': 'expense',
      'expectedRef': 'FT26225YKP2004422',
    },
    {
      'raw': 'Dear Samuel, your account 1**22 was debited with ETB 3.01 for the Mobile Banking Monthly Maintenance Fee, including 15% VAT and 5% Disaster Fund. Available balance: ETB 22011.6. \nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26236XRVGC04422 \nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397. Bank of Abyssinia.',
      'expectedAmount': 3.01,
      'expectedBalance': 22011.6,
      'expectedType': 'expense',
      'expectedRef': 'FT26236XRVGC04422',
      'expectedCounterparty': 'Mobile Banking Monthly Maintenance Fee',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 1,912.00. Available Balance: ETB 20,099.60.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26238JPN0K04422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26238JPN0K\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 1912.00,
      'expectedBalance': 20099.60,
      'expectedType': 'expense',
      'expectedRef': 'FT26238JPN0K04422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 1,912.00. Available Balance: ETB 18,187.60.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT262432YF2H04422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT262432YF2H\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 1912.00,
      'expectedBalance': 18187.60,
      'expectedType': 'expense',
      'expectedRef': 'FT262432YF2H04422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 4,021.61. Available Balance: ETB 14,166.13.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26244PV9CP04422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26244PV9CP\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 4021.61,
      'expectedBalance': 14166.13,
      'expectedType': 'expense',
      'expectedRef': 'FT26244PV9CP04422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 2,010.80. Available Balance: ETB 12,155.33.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26244CDXJQ04422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26244CDXJQ\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 2010.80,
      'expectedBalance': 12155.33,
      'expectedType': 'expense',
      'expectedRef': 'FT26244CDXJQ04422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was credited with ETB 6,000.00 by  Abrehamzegeyemulata . Available Balance: ETB 18,155.33.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26244YX9DB10104\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=CFT26244YX9DB\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 6000.00,
      'expectedBalance': 18155.33,
      'expectedType': 'income',
      'expectedRef': 'FT26244YX9DB10104',
      'expectedCounterparty': 'Abrehamzegeyemulata',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 1,007.20. Available Balance: ETB 17,148.13.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26245S056804422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26245S0568\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 1007.20,
      'expectedBalance': 17148.13,
      'expectedType': 'expense',
      'expectedRef': 'FT26245S056804422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 503.01. Available Balance: ETB 16,645.12.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26247XGH6K04422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26247XGH6K\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 503.01,
      'expectedBalance': 16645.12,
      'expectedType': 'expense',
      'expectedRef': 'FT26247XGH6K04422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was credited with ETB 40,700.00 from Telebirr by Reference DI50HBG2U4. Available Balance: ETB 57,345.12.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26250365TQ10104\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=CFT26250365TQ\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 40700.00,
      'expectedBalance': 57345.12,
      'expectedType': 'income',
      'expectedRef': 'FT26250365TQ10104',
      'expectedCounterparty': 'Telebirr',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 312.00. Available Balance: ETB 57,033.12.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26252Q2HND04422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26252Q2HND\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 312.00,
      'expectedBalance': 57033.12,
      'expectedType': 'expense',
      'expectedRef': 'FT26252Q2HND04422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 4,024.00. Available Balance: ETB 53,006.11.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT262579FKDK04422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT262579FKDK\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 4024.00,
      'expectedBalance': 53006.11,
      'expectedType': 'expense',
      'expectedRef': 'FT262579FKDK04422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 4,024.00. Available Balance: ETB 48,982.11.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT262575J3P404422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT262575J3P4\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 4024.00,
      'expectedBalance': 48982.11,
      'expectedType': 'expense',
      'expectedRef': 'FT262575J3P404422',
    },
    {
      'raw': 'Dear Samuel, your account 1*22 was debited with ETB 2,012.00. Available Balance: ETB 46,970.11.\nReceipt: https://cs.bankofabyssinia.com/slip/?trx=FT26257VGDFF04422\nFeedback: https://cs.bankofabyssinia.com/cs/?trx=DFT26257VGDFF\nLink your Fayda: https://cs.bankofabyssinia.com/fayda_connect \nFor help, call 8397 (24/7 Toll-Free). Bank of Abyssinia.',
      'expectedAmount': 2012.00,
      'expectedBalance': 46970.11,
      'expectedType': 'expense',
      'expectedRef': 'FT26257VGDFF04422',
    },
  ];

  test('All 21 BoA sample messages must parse successfully', () {
    int passed = 0;
    for (int i = 0; i < boaMessages.length; i++) {
      final msg = boaMessages[i];
      final res = parser.parse(
        sender: 'BoA',
        body: msg['raw'] as String,
        receivedAt: DateTime(2026, 10, 8, 2, 12),
      );

      expect(res.isSuccess, isTrue, reason: 'Message #$i failed to parse: ${res.failureReason}');
      final tx = res.transaction!;
      expect(tx.amount, equals(msg['expectedAmount']), reason: 'Message #$i amount mismatch');
      expect(tx.type, equals(msg['expectedType']), reason: 'Message #$i type mismatch');
      expect(tx.balanceAfter, equals(msg['expectedBalance']), reason: 'Message #$i balance mismatch');
      expect(tx.reference, equals(msg['expectedRef']), reason: 'Message #$i reference mismatch');

      if (msg.containsKey('expectedCounterparty')) {
        expect(tx.counterparty, equals(msg['expectedCounterparty']), reason: 'Message #$i counterparty mismatch');
      }
      passed++;
    }
    print('All $passed / ${boaMessages.length} BoA messages parsed successfully!');
  });
}
