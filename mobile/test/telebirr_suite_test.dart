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

  group('Telebirr Real-World SMS Suite', () {
    test('1. Transfer received from CBE to telebirr', () {
      final text = 'Dear Samuel,\n'
          'You have received  ETB 450.00 by transaction number DID4OT91LA on 2026-09-13 13:57:50 from Commercial Bank of Ethiopia to your telebirr Account 251910106422 - Samuel Wubalem Melese. Your current balance is ETB 450.00.\n'
          'Thank you for using telebirr\n'
          'Ethio telecom';
      final res = parser.parse(sender: '127', body: text, receivedAt: DateTime.now());
      expect(res.isSuccess, isTrue, reason: res.failureReason);
      expect(res.transaction!.amount, 450.00);
      expect(res.transaction!.type, 'income');
      expect(res.transaction!.balanceAfter, 450.00);
      expect(res.transaction!.reference, 'DID4OT91LA');
      expect(res.transaction!.counterparty, 'Commercial Bank of Ethiopia');
    });

    test('2. Repaid credit amount', () {
      final text = 'Dear Samuel\n'
          'You have successfully paid a credit amount of  ETB 17.17 on 2026-09-13 13:57:51. Your current outstanding credit amount ETB 0.00  \n'
          'Thank you for using telebirr \n'
          'Ethio telecom';
      final res = parser.parse(sender: '127', body: text, receivedAt: DateTime.now());
      expect(res.isSuccess, isTrue, reason: res.failureReason);
      expect(res.transaction!.amount, 17.17);
      expect(res.transaction!.type, 'expense');
      expect(res.transaction!.balanceAfter, 0.00);
    });

    test('3. Transferred to person (Hilina Desta)', () {
      final text = 'Dear Samuel \n'
          'You have transferred ETB 400.00 to Hilina Desta (2519****6516) on 13/09/2026 13:59:34. Your transaction number is DID5OTARUP. The service fee is  ETB 1.74 and  15% VAT on the service fee is ETB 0.26. Your current E-Money Account  balance is ETB 30.83. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/DID5OTARUP.\n\n'
          'Thank you for using telebirr\n'
          'Ethio telecom';
      final res = parser.parse(sender: 'telebirr', body: text, receivedAt: DateTime.now());
      expect(res.isSuccess, isTrue, reason: res.failureReason);
      expect(res.transaction!.amount, 400.00);
      expect(res.transaction!.type, 'expense');
      expect(res.transaction!.balanceAfter, 30.83);
      expect(res.transaction!.reference, 'DID5OTARUP');
      expect(res.transaction!.counterparty, 'Hilina Desta');
    });

    test('4. Paid for internet package', () {
      final text = 'Dear Samuel\n'
          'You have paid ETB 25.00 for package Daily Internet Package 720 MB purchase made for 910106422 on 13/09/2026 19:23:35. Your transaction number is  DID8P4P5OK. Your current balance is ETB 5.83.To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/DID8P4P5OK\n'
          'Thank you for using telebirr\n'
          'Ethio telecom';
      final res = parser.parse(sender: '127', body: text, receivedAt: DateTime.now());
      expect(res.isSuccess, isTrue, reason: res.failureReason);
      expect(res.transaction!.amount, 25.00);
      expect(res.transaction!.type, 'expense');
      expect(res.transaction!.balanceAfter, 5.83);
      expect(res.transaction!.reference, 'DID8P4P5OK');
      expect(res.transaction!.counterparty, 'Daily Internet Package 720 MB');
    });

    test('5. Recharged airtime for phone number', () {
      final text = 'Dear Samuel \n'
          'You have recharged ETB 15.00 airtime for 910106422 on 15/09/2026 09:05:54. Your transaction number is DIF6QIMYQK. Your current  balance is  ETB 0.00. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/DIF6QIMYQK\n'
          'Thank you for using telebirr\n'
          'Ethio telecom';
      final res = parser.parse(sender: '127', body: text, receivedAt: DateTime.now());
      expect(res.isSuccess, isTrue, reason: res.failureReason);
      expect(res.transaction!.amount, 15.00);
      expect(res.transaction!.type, 'expense');
      expect(res.transaction!.balanceAfter, 0.00);
      expect(res.transaction!.reference, 'DIF6QIMYQK');
    });

    test('6. Transferred to Bank of Abyssinia account', () {
      final text = 'Dear Samuel\n'
          'You have transferred ETB 3,630.00 successfully from your telebirr account 251910106422 to Bank of Abyssinia account number 188204422 on 03/10/2026 05:12:20. Your telebirr transaction number is DJ37D4C517 and your bank transaction number is . The service fee is  ETB 7.83 and  15% VAT on the service fee is ETB 1.17. Your current balance is ETB 36.48. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/DJ37D4C517\n'
          'Thank you for using telebirr\n'
          'Ethio telecom';
      final res = parser.parse(sender: '127', body: text, receivedAt: DateTime.now());
      expect(res.isSuccess, isTrue, reason: res.failureReason);
      expect(res.transaction!.amount, 3630.00);
      expect(res.transaction!.type, 'expense');
      expect(res.transaction!.balanceAfter, 36.48);
      expect(res.transaction!.reference, 'DJ37D4C517');
      expect(res.transaction!.counterparty, 'Bank of Abyssinia');
    });

    test('7. Paid for merchant Service Fee', () {
      final text = 'Dear Samuel\n'
          'You have paid ETB 480.00 for Service Fee from 953590 - FUNZI TRADING PLC on 23/09/2026 19:07:08. Your transaction number is  DIN82UAHUO. Your current balance is ETB 0.00. To download your payment information please click this link: https://transactioninfo.ethiotelecom.et/receipt/DIN82UAHUO\n'
          'Thank you for using telebirr\n'
          'Ethio telecom';
      final res = parser.parse(sender: '127', body: text, receivedAt: DateTime.now());
      expect(res.isSuccess, isTrue, reason: res.failureReason);
      expect(res.transaction!.amount, 480.00);
      expect(res.transaction!.type, 'expense');
      expect(res.transaction!.balanceAfter, 0.00);
      expect(res.transaction!.reference, 'DIN82UAHUO');
      expect(res.transaction!.counterparty, 'FUNZI TRADING PLC');
    });

    test('8. Insufficient balance should be recognized as non-financial', () {
      final text = 'Sorry, You have insufficient balance for the requested transaction. Your account balance is ETB 4,185.38. Please deposit additional amount and try again.\n'
          'Thank you for using telebirr\n'
          'Ethio telecom';
      final res = parser.parse(sender: '127', body: text, receivedAt: DateTime.now());
      expect(res.isSuccess, isFalse);
      expect(res.isFinancial, isFalse);
    });

    test('9. Credit request disbursement (loan)', () {
      final text = 'Dear Samuel,   \n'
          'Your credit request with DJ33D4BNLV contract number is successful. The credit amount is ETB 4,000.00 and facilitation fee ETB 120.00 with due date 02/11/2026 and the daily fee will be from 0.30% to 0.80% depending on your credit limit. Your current available credit limit ETB 1,027.52.\n'
          'Thank you for using telebirr \n'
          'Ethio telecom in partnership with Dashen Bank';
      final res = parser.parse(sender: '127', body: text, receivedAt: DateTime.now());
      expect(res.isSuccess, isTrue, reason: res.failureReason);
      expect(res.transaction!.amount, 4000.00);
      expect(res.transaction!.type, 'income');
      expect(res.transaction!.reference, 'DJ33D4BNLV');
    });
  });
}
