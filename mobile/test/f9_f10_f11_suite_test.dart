import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// F9 imports
import 'package:sw_budget/domain/use_cases/adaptive_spending_engine.dart';
import 'package:sw_budget/features/plan/models/spending_plan_models.dart';

// F10 imports
import 'package:sw_budget/features/reimbursements/models/reimbursement.dart';
import 'package:sw_budget/features/reimbursements/services/reimbursement_service.dart';
import 'package:sw_budget/features/debts/models/loan_debt_models.dart';
import 'package:sw_budget/features/debts/services/debts_service.dart';
import 'package:sw_budget/features/settings/reparse/account_reparse_service.dart';
import 'package:sw_budget/data/parser/financial_parser.dart';

// F11 imports
import 'package:sw_budget/core/services/bank_statement_pdf_service.dart';
import 'package:sw_budget/core/services/local_web_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F9: Adaptive Spending Plan Engine & Models', () {
    late DateTime planStart;
    late DateTime planEnd;
    late BudgetPlan plan;

    setUp(() {
      planStart = DateTime(2026, 10, 1);
      planEnd = DateTime(2026, 10, 31);
      plan = BudgetPlan(
        id: 'plan-oct-2026',
        userId: 'user-samuel',
        name: 'October 2026 Budget',
        totalAmount: 50000.0,
        startDate: planStart,
        endDate: planEnd,
        reservePercent: 10.0, // 5,000 ETB
        fixedExpenses: const [
          FixedExpense(id: 'fe-1', planId: 'plan-oct-2026', title: 'Rent', amount: 12000.0),
          FixedExpense(id: 'fe-2', planId: 'plan-oct-2026', title: 'Internet', amount: 1500.0),
        ],
        rolloverMode: RolloverMode.spreadEvenly,
      );
    });

    test('BudgetPlan calculates days and fixed expenses total correctly', () {
      expect(plan.totalDays, equals(31));
      expect(plan.fixedExpensesTotal, equals(13500.0));
    });

    test('AdaptiveSpendingEngine computes snapshot with correct discretionary pool & daily allowance', () {
      // 50,000 - 13,500 (fixed) - 5,000 (10% reserve) = 31,500 flexible pool
      // Base daily = 31,500 / 31 days = 1016.13
      final spentByDay = List<double>.filled(10, 800.0); // 10 days of 800 spend = 8,000
      final snapshot = AdaptiveSpendingEngine.computeSnapshot(
        planId: plan.id,
        asOfDate: '2026-10-10',
        budget: plan.totalAmount,
        fixedTotal: plan.fixedExpensesTotal,
        reservePercent: plan.reservePercent,
        totalDays: plan.totalDays,
        dayIndex: 10,
        spentByDay: spentByDay,
        rolloverMode: RolloverMode.spreadEvenly,
      );

      expect(snapshot.totals['budget'], equals(50000.0));
      expect(snapshot.totals['fixed'], equals(13500.0));
      expect(snapshot.totals['reserve'], equals(5000.0));
      expect(snapshot.totals['flexible'], equals(31500.0));
      expect(snapshot.totals['spent'], equals(8000.0));
      expect(snapshot.totals['remaining'], equals(23500.0));

      expect(snapshot.days['total'], equals(31));
      expect(snapshot.days['elapsed'], equals(10));
      expect(snapshot.days['left'], equals(21));

      expect(snapshot.today['baseDaily'], equals(1016.13));
      expect(snapshot.today['spent'], equals(800.0));
      expect(snapshot.status, equals('GREEN'));
    });

    test('AdaptiveSpendingEngine handles rollover modes (nextDay vs weekOnly)', () {
      final spentByDay = [1500.0, 500.0]; // Day 1 overspent (1500 vs 1016), Day 2 underspent (500)
      final snapNextDay = AdaptiveSpendingEngine.computeSnapshot(
        planId: plan.id,
        asOfDate: '2026-10-02',
        budget: plan.totalAmount,
        fixedTotal: plan.fixedExpensesTotal,
        reservePercent: plan.reservePercent,
        totalDays: plan.totalDays,
        dayIndex: 2,
        spentByDay: spentByDay,
        rolloverMode: RolloverMode.nextDay,
      );

      // On Day 2, yesterday spent was 1500 (> base 1016.13), so today allowance reduced
      expect(snapNextDay.today['allowance'], lessThan(snapNextDay.today['baseDaily'] as num));

      // Week only mode
      final snapWeekOnly = AdaptiveSpendingEngine.computeSnapshot(
        planId: plan.id,
        asOfDate: '2026-10-02',
        budget: plan.totalAmount,
        fixedTotal: plan.fixedExpensesTotal,
        reservePercent: plan.reservePercent,
        totalDays: plan.totalDays,
        dayIndex: 2,
        spentByDay: spentByDay,
        rolloverMode: RolloverMode.weekOnly,
      );
      expect(snapWeekOnly.today['allowance'], isNotNull);
    });

    test('AdaptiveSpendingEngine partitions into weekly budget blocks', () {
      final spentByDay = List<double>.filled(14, 900.0);
      final weeks = AdaptiveSpendingEngine.partitionWeeks(
        totalDays: 31,
        currentDay: 14,
        baseDaily: 1000.0,
        tomorrowAllowance: 1000.0,
        spentByDay: spentByDay,
      );

      expect(weeks.length, equals(5)); // ceil(31/7) = 5
      expect(weeks[0].days, equals(7));
      expect(weeks[0].baseTarget, equals(7000.0));
      expect(weeks[0].spent, equals(6300.0)); // 7 * 900
      expect(weeks[0].pctUsed, equals(90.0));
    });

    test('AdaptiveSpendingEngine simulates scenario forecasting', () {
      final sim = AdaptiveSpendingEngine.simulateScenario(
        flexibleBudget: 30000.0,
        totalDays: 30,
        currentDay: 10,
        spentTotal: 10000.0,
        proposedDailySpend: 800.0,
      );

      // Remaining days = 20. Future spend = 20 * 800 = 16,000.
      // Projected total = 10,000 + 16,000 = 26,000.
      // Surplus = 30,000 - 26,000 = -4,000 (projectedDiff = -4000)
      expect(sim.projectedTotal, equals(26000.0));
      expect(sim.projectedDiff, equals(-4000.0));
      expect(sim.status, equals('SAFE'));
    });
  });

  group('F10: Reimbursements, Loans & Reparse Service', () {
    test('ReimbursementService computes net spend and validates allocation limits', () {
      final reimbursements = <Reimbursement>[
        Reimbursement(
          id: 'r-1',
          userId: 'u-1',
          expenseTxnId: 'exp-dinner',
          creditTxnId: 'cr-friend-1',
          amount: 500.0,
          createdAt: DateTime(2026, 10, 5),
        ),
        Reimbursement(
          id: 'r-2',
          userId: 'u-1',
          expenseTxnId: 'exp-dinner',
          creditTxnId: 'cr-friend-2',
          amount: 600.0,
          createdAt: DateTime(2026, 10, 6),
        ),
      ];

      // Original dinner expense: 2000 ETB
      final netSpend = ReimbursementService.calculateNetSpend(2000.0, reimbursements);
      expect(netSpend, equals(900.0)); // 2000 - 1100 = 900

      // Validation success for 400 ETB
      expect(
        () => ReimbursementService.validateReimbursementAllocation(
          originalAmount: 2000.0,
          alreadyReimbursed: 1100.0,
          newAllocationAmount: 400.0,
        ),
        returnsNormally,
      );

      // Validation throws if new allocation exceeds remaining unreimbursed 900 ETB
      expect(
        () => ReimbursementService.validateReimbursementAllocation(
          originalAmount: 2000.0,
          alreadyReimbursed: 1100.0,
          newAllocationAmount: 1000.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('DebtsService tracks repayments, auto-settles, and computes summary', () {
      final loan = LoanDebt(
        id: 'loan-1',
        userId: 'user-1',
        personId: 'person-dawit',
        type: 'lent',
        initialAmount: 5000.0,
        currentBalance: 5000.0,
      );

      // Partial repayment 2000
      final partial = DebtsService.recordRepayment(debt: loan, repaymentAmount: 2000.0);
      expect(partial.currentBalance, equals(3000.0));
      expect(partial.status, equals('active'));
      expect(partial.isSettled, isFalse);

      // Full payoff of remaining 3000 -> auto settles
      final settled = DebtsService.recordRepayment(debt: partial, repaymentAmount: 3000.0);
      expect(settled.currentBalance, equals(0.0));
      expect(settled.status, equals('settled'));
      expect(settled.isSettled, isTrue);

      // Summary
      final borrowed = LoanDebt(
        id: 'borrowed-1',
        userId: 'user-1',
        personId: 'person-bank',
        type: 'borrowed',
        initialAmount: 1500.0,
        currentBalance: 1500.0,
      );
      final summary = DebtsService.calculateSummary([partial, borrowed]);
      expect(summary['totalLent'], equals(3000.0));
      expect(summary['totalBorrowed'], equals(1500.0));
      expect(summary['netBalance'], equals(1500.0));
    });

    test('AccountReparseService detects directional repairs and deduplicates records', () {
      final banksJson = File('assets/templates/banks.json').readAsStringSync();
      final patternsJson = File('assets/templates/sms_patterns.json').readAsStringSync();

      final parser = FinancialParser();
      parser.loadNamedPatterns(patternsJson: patternsJson, banksJson: banksJson);

      final reparseService = AccountReparseService(parser: parser);

      // Raw records: One CBE debit message incorrectly stored as 'CREDIT', plus a duplicate
      final rawRecords = [
        {
          'sender': 'CBE',
          'body': 'Dear Samuel, your account 100012345678 has been debited with ETB 750.00. Ref: CBE-TX-001. Bal: 4250.00 ETB.',
          'type': 'CREDIT', // Intentionally wrong direction
          'timestamp': DateTime(2026, 10, 5).millisecondsSinceEpoch,
        },
        // Exact duplicate
        {
          'sender': 'CBE',
          'body': 'Dear Samuel, your account 100012345678 has been debited with ETB 750.00. Ref: CBE-TX-001. Bal: 4250.00 ETB.',
          'type': 'CREDIT',
          'timestamp': DateTime(2026, 10, 5).millisecondsSinceEpoch,
        },
      ];

      final result = reparseService.reparseMessages(
        rawRecords: rawRecords,
        repairDirections: true,
        deduplicate: true,
      );

      expect(result.totalProcessed, equals(2));
      expect(result.duplicatesRemovedCount, equals(1));
      expect(result.repairedDirectionCount, equals(1));
      expect(result.updatedCount, equals(1));
    });
  });

  group('F11: Bank Statement PDF & Local Web Server', () {
    test('BankStatementPdfService generates valid PDF bytes with Ethiopian bank branding', () async {
      final items = [
        StatementTransactionItem(
          date: DateTime(2026, 10, 1),
          description: 'October Salary Transfer',
          reference: 'FT26100199',
          type: 'income',
          amount: 35000.0,
          runningBalance: 45000.0,
        ),
        StatementTransactionItem(
          date: DateTime(2026, 10, 3),
          description: 'Condominium HOA Fee',
          reference: 'FT26100342',
          type: 'expense',
          amount: 1500.0,
          runningBalance: 43500.0,
        ),
      ];

      final pdfBytes = await BankStatementPdfService.generateStatementBytes(
        bankName: 'Commercial Bank of Ethiopia',
        accountHolderName: 'Samuel Tesfaye',
        accountNumber: '100012345678',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
        openingBalance: 10000.0,
        items: items,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);

      // Verify PDF file magic header (%PDF-)
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('LocalWebServer starts, serves endpoints, and terminates cleanly', () async {
      final sampleTxJson = [
        {
          'referenceNumber': 'REF-WEB-1',
          'amount': 1200.0,
          'type': 'DEBIT',
          'date': '2026-10-10T12:00:00Z',
        }
      ];

      final server = LocalWebServer();
      // Allow loopback HTTP requests in flutter_test
      HttpOverrides.global = null;

      // Use port 8089 for clean testing
      final runningUrl = await server.start(
        port: 8089,
        initialTransactions: sampleTxJson,
      );
      expect(server.isRunning, isTrue);
      expect(runningUrl, contains('8089'));

      final client = HttpClient();
      try {
        // 1. Test /api/status endpoint
        final statusReq = await client.getUrl(Uri.parse('http://127.0.0.1:8089/api/status'));
        final statusResp = await statusReq.close();
        expect(statusResp.statusCode, equals(200));
        final statusBody = await statusResp.transform(utf8.decoder).join();
        final statusJson = jsonDecode(statusBody);
        expect(statusJson['status'], equals('online'));
        expect(statusJson['server'], contains('SW-budget'));

        // 2. Test /api/transactions endpoint
        final txReq = await client.getUrl(Uri.parse('http://127.0.0.1:8089/api/transactions'));
        final txResp = await txReq.close();
        expect(txResp.statusCode, equals(200));
        final txBody = await txResp.transform(utf8.decoder).join();
        final txJson = jsonDecode(txBody);
        expect(txJson['count'], equals(1));
        expect((txJson['transactions'] as List).first['referenceNumber'], equals('REF-WEB-1'));
      } finally {
        client.close();
        await server.stop();
        expect(server.isRunning, isFalse);
      }
    });
  });
}
