import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_provider.dart';
import '../../data/sync/sync_provider.dart';
import '../../domain/use_cases/budget_math_service.dart';
import '../../domain/use_cases/plan_evaluation_engine.dart';

/// Reactive stream of the single active budget plan
final activeBudgetPlanStreamProvider = StreamProvider<Map<String, dynamic>?>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield db.getActiveBudgetPlan();

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.budgetPlans) {
      yield db.getActiveBudgetPlan();
    }
  }
});

/// Reactive stream of expected expenses for the active plan
final expectedExpensesStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  final activePlan = ref.watch(activeBudgetPlanStreamProvider).value;
  if (activePlan == null) {
    yield const [];
    return;
  }

  final planId = activePlan['id'] as String;
  yield db.getExpectedExpensesForPlan(planId);

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.expectedExpenses || event == DatabaseTable.budgetPlans) {
      final curPlan = db.getActiveBudgetPlan();
      if (curPlan != null) {
        yield db.getExpectedExpensesForPlan(curPlan['id'] as String);
      } else {
        yield const [];
      }
    }
  }
});

/// Reactive stream of all local transactions
final allPlanTransactionsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield db.getTransactions(limit: 2000);

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.transactions) {
      yield db.getTransactions(limit: 2000);
    }
  }
});

/// Computed reactive snapshot of the plan under the v2 deterministic engine
final planEvaluationSnapshotProvider = Provider<PlanEvaluationSnapshot?>((ref) {
  final activePlanAsync = ref.watch(activeBudgetPlanStreamProvider);
  final expectedExpensesAsync = ref.watch(expectedExpensesStreamProvider);
  final transactionsAsync = ref.watch(allPlanTransactionsStreamProvider);

  final activePlan = activePlanAsync.value;
  if (activePlan == null) return null;

  final expectedExpenses = expectedExpensesAsync.value ?? const [];
  final rawTransactions = transactionsAsync.value ?? const [];

  return PlanEvaluationEngine.evaluate(
    plan: activePlan,
    expectedExpenses: expectedExpenses,
    rawTransactions: rawTransactions,
  );
});

// --- LEGACY COMPATIBILITY PROVIDERS ---

final limitsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield db.getLimits();

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.limits) {
      yield db.getLimits();
    }
  }
});

final savingPlansStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield db.getSavingPlans();

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.savingPlans) {
      yield db.getSavingPlans();
    }
  }
});

final currentMonthSpendSummaryProvider = StreamProvider<Map<String, double>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);

  Map<String, double> computeTotals() {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final txns = db.getTransactions(limit: 1000);

    final Map<String, double> totals = {'_total_expense': 0.0};
    for (final t in txns) {
      if ((t['type'] as String? ?? '').toLowerCase() != 'expense') continue;
      final occurred = DateTime.tryParse(t['occurred_at'] as String? ?? '');
      if (occurred == null || occurred.isBefore(firstDayOfMonth)) continue;
      final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
      totals['_total_expense'] = (totals['_total_expense'] ?? 0.0) + amount;
      final catId = t['category_id'] as String? ?? 'uncategorized';
      totals[catId] = (totals[catId] ?? 0.0) + amount;
    }
    return totals;
  }

  yield computeTotals();
  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.transactions) {
      yield computeTotals();
    }
  }
});

final currentMonthDailySpendProvider = StreamProvider<List<double>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);

  List<double> computeDaily() {
    final now = DateTime.now();
    final daily = List<double>.filled(now.day, 0.0);
    final txns = db.getTransactions(limit: 1000);
    for (final t in txns) {
      if ((t['type'] as String? ?? '').toLowerCase() != 'expense') continue;
      final occurred = DateTime.tryParse(t['occurred_at'] as String? ?? '');
      if (occurred == null || occurred.year != now.year || occurred.month != now.month) continue;
      final dayIdx = occurred.day - 1;
      if (dayIdx >= 0 && dayIdx < daily.length) {
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        daily[dayIdx] += amt;
      }
    }
    return daily;
  }

  yield computeDaily();
  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.transactions) {
      yield computeDaily();
    }
  }
});

final cycleWeeksSpendProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final snapshot = ref.watch(planEvaluationSnapshotProvider);
  if (snapshot != null) {
    yield snapshot.weeklyChunks.map((w) => {
      'title': 'Week ${w.weekNumber}',
      'range': w.label,
      'target': w.plannedTarget,
      'spent': w.spent,
      'status': w.status,
    }).toList();
    return;
  }

  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final monthName = DateFormat('MMM').format(now);
  yield [
    {'title': 'Week 1', 'range': '$monthName 1 - 7', 'target': 6250.0, 'spent': 0.0, 'status': 'Now'},
    {'title': 'Week 2', 'range': '$monthName 8 - 14', 'target': 6250.0, 'spent': 0.0, 'status': 'Upcoming'},
    {'title': 'Week 3', 'range': '$monthName 15 - 21', 'target': 6250.0, 'spent': 0.0, 'status': 'Upcoming'},
    {'title': 'Week 4', 'range': '$monthName 22 - $daysInMonth', 'target': 6250.0, 'spent': 0.0, 'status': 'Upcoming'},
  ];
});

final safeToSpendProvider = Provider<SafeToSpendSummary>((ref) {
  final snapshot = ref.watch(planEvaluationSnapshotProvider);
  if (snapshot != null) {
    SpendingPace pace = SpendingPace.onTrack;
    if (snapshot.paceStatus == 'under') pace = SpendingPace.ahead;
    if (snapshot.paceStatus == 'over') pace = SpendingPace.caution;
    if (snapshot.zone == PlanBudgetZone.overPlan) pace = SpendingPace.deficit;

    return SafeToSpendSummary(
      totalBudget: snapshot.spendableBudget,
      spentSoFar: snapshot.totalSpent,
      remainingBudget: snapshot.leftToSpend,
      safeToday: snapshot.todayAllowance,
      daysElapsed: snapshot.daysElapsed,
      daysRemaining: snapshot.daysRemaining,
      totalDaysInPeriod: snapshot.totalDays,
      burnRatio: snapshot.spendableBudget > 0 ? snapshot.totalSpent / snapshot.spendableBudget : 1.0,
      pace: pace,
    );
  }

  final limitsAsync = ref.watch(limitsStreamProvider);
  final spendAsync = ref.watch(currentMonthSpendSummaryProvider);
  final totalSpend = spendAsync.value?['_total_expense'] ?? 0.0;
  double totalBudget = 25000.0;
  final limits = limitsAsync.value ?? [];
  final overallLimit = limits.firstWhere(
    (l) => (l['scope_type'] as String? ?? '').toLowerCase() == 'overall',
    orElse: () => <String, dynamic>{},
  );
  if (overallLimit.isNotEmpty && overallLimit['amount'] != null) {
    totalBudget = (overallLimit['amount'] as num).toDouble();
  }
  return BudgetMathService.calculateSafeToSpend(
    totalBudget: totalBudget,
    spentSoFar: totalSpend,
  );
});

// --- PLAN CONTROLLER ---

final planControllerProvider = Provider<PlanController>((ref) => PlanController(ref));

class PlanController {
  final Ref _ref;

  PlanController(this._ref);

  /// Creates a new single budget plan and optional expected expenses
  Future<void> createPlan({
    required String name,
    required String periodType,
    required DateTime startDate,
    required DateTime endDate,
    int monthlyStartDay = 1,
    required double spendingLimit,
    String reserveType = 'none',
    double reserveValue = 0.0,
    List<String>? watchedBankIds,
    bool countFees = true,
    bool countWithdrawals = true,
    String reactionMode = 'adaptive',
    bool morningBriefEnabled = true,
    String morningBriefTime = '07:30',
    bool dailyReportEnabled = true,
    String dailyReportTime = '21:00',
    bool skipEmptyDays = false,
    List<Map<String, dynamic>> expectedExpenses = const [],
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final planId = const Uuid().v4();

    db.upsertBudgetPlan(
      id: planId,
      name: name,
      periodType: periodType,
      startDate: startDate,
      endDate: endDate,
      monthlyStartDay: monthlyStartDay,
      spendingLimit: spendingLimit,
      reserveType: reserveType,
      reserveValue: reserveValue,
      watchedBankIds: watchedBankIds != null ? jsonEncode(watchedBankIds) : null,
      countFees: countFees,
      countWithdrawals: countWithdrawals,
      reactionMode: reactionMode,
      status: 'active',
      morningBriefEnabled: morningBriefEnabled,
      morningBriefTime: morningBriefTime,
      dailyReportEnabled: dailyReportEnabled,
      dailyReportTime: dailyReportTime,
      skipEmptyDays: skipEmptyDays,
      changeSeq: 0,
      isDirty: true,
    );

    // Insert expected expenses
    for (final exp in expectedExpenses) {
      final expId = const Uuid().v4();
      final dueStr = exp['due_date'] as String?;
      DateTime? due;
      if (dueStr != null && dueStr.isNotEmpty) {
        due = DateTime.tryParse(dueStr);
      }
      db.upsertExpectedExpense(
        id: expId,
        planId: planId,
        name: exp['name'] as String? ?? exp['title'] as String? ?? 'Expected Expense',
        amount: (exp['amount'] as num?)?.toDouble() ?? 0.0,
        dueDate: due,
        linkedCategoryId: exp['linked_category_id'] as String?,
        reminderEnabled: exp['reminder_enabled'] as bool? ?? true,
        status: exp['status'] as String? ?? 'expected',
        changeSeq: 0,
        isDirty: true,
      );
    }

    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  /// Pauses the active plan
  Future<void> pausePlan(String planId) async {
    final db = await _ref.read(databaseProvider.future);
    db.pauseBudgetPlan(planId);
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  /// Resumes a paused plan
  Future<void> resumePlan(String planId) async {
    final db = await _ref.read(databaseProvider.future);
    db.resumeBudgetPlan(planId);
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  /// Deletes the active plan
  Future<void> deletePlan(String planId) async {
    final db = await _ref.read(databaseProvider.future);
    db.deleteBudgetPlan(planId);
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  /// Finishes the active plan with summary payload
  Future<void> finishPlan(String planId, Map<String, dynamic> finalSummary) async {
    final db = await _ref.read(databaseProvider.future);
    db.finishBudgetPlan(planId, jsonEncode(finalSummary));
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  /// Adds a new expected expense to the plan
  Future<void> addExpectedExpense({
    required String planId,
    required String name,
    required double amount,
    DateTime? dueDate,
    String? linkedCategoryId,
    bool reminderEnabled = true,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final id = const Uuid().v4();
    db.upsertExpectedExpense(
      id: id,
      planId: planId,
      name: name,
      amount: amount,
      dueDate: dueDate,
      linkedCategoryId: linkedCategoryId,
      reminderEnabled: reminderEnabled,
      status: 'expected',
      changeSeq: 0,
      isDirty: true,
    );
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  /// Updates an existing expected expense
  Future<void> updateExpectedExpense({
    required String id,
    required String planId,
    required String name,
    required double amount,
    DateTime? dueDate,
    String? linkedCategoryId,
    bool reminderEnabled = true,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    db.upsertExpectedExpense(
      id: id,
      planId: planId,
      name: name,
      amount: amount,
      dueDate: dueDate,
      linkedCategoryId: linkedCategoryId,
      reminderEnabled: reminderEnabled,
      changeSeq: 0,
      isDirty: true,
    );
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  /// Deletes an expected expense
  Future<void> deleteExpectedExpense(String id) async {
    final db = await _ref.read(databaseProvider.future);
    db.deleteExpectedExpense(id);
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  /// Marks an expected expense as paid or unpaid
  Future<void> toggleExpectedExpensePaid(String id, bool isCurrentlyPaid) async {
    final db = await _ref.read(databaseProvider.future);
    if (isCurrentlyPaid) {
      db.markExpectedExpenseUnpaid(id);
    } else {
      db.markExpectedExpensePaid(id);
    }
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  /// Sets a transaction's exclusion flag with reason
  Future<void> toggleTransactionPlanExclusion(String txnId, {required bool exclude, String? reason}) async {
    final db = await _ref.read(databaseProvider.future);
    db.setTransactionPlanExclusion(txnId, exclude: exclude, reason: reason);
  }

  // Legacy limit saving support
  Future<void> saveOverallBudget({
    required double budget,
    required double reservePct,
    required String rollover,
    String? id,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final limitId = id ?? 'overall_monthly_limit';
    db.upsertLimit(
      id: limitId,
      scopeType: 'overall',
      scopeId: null,
      periodType: 'monthly',
      amount: budget,
      mode: 'soft',
      rollover: rollover != 'SPREAD_EVENLY',
      alertThresholds: jsonEncode([50, 80, 100]),
      active: true,
      changeSeq: 0,
      isDirty: true,
    );
    _ref.read(syncStateProvider.notifier).triggerSync();
  }
}
