import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_provider.dart';
import '../../data/sync/sync_provider.dart';
import '../../domain/use_cases/budget_math_service.dart';

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

/// Computes monthly spending totals across categories from local transaction records
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

/// Daily spending array for the current month up to today (for PaceChart)
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

/// 4-week cycle spending provider
final cycleWeeksSpendProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);

  List<Map<String, dynamic>> computeWeeks() {
    final now = DateTime.now();
    final today = now.day;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final txns = db.getTransactions(limit: 1000);

    double w1Spent = 0.0;
    double w2Spent = 0.0;
    double w3Spent = 0.0;
    double w4Spent = 0.0;

    for (final t in txns) {
      if ((t['type'] as String? ?? '').toLowerCase() != 'expense') continue;
      final occurred = DateTime.tryParse(t['occurred_at'] as String? ?? '');
      if (occurred == null || occurred.year != now.year || occurred.month != now.month) continue;
      final day = occurred.day;
      final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;

      if (day <= 7) {
        w1Spent += amt;
      } else if (day <= 14) {
        w2Spent += amt;
      } else if (day <= 21) {
        w3Spent += amt;
      } else {
        w4Spent += amt;
      }
    }

    final monthName = DateFormat('MMM').format(now);
    return [
      {
        'title': 'Week 1',
        'range': '$monthName 1 - 7',
        'target': 6250.0,
        'spent': w1Spent,
        'status': today > 7 ? 'Done' : 'Now',
      },
      {
        'title': 'Week 2',
        'range': '$monthName 8 - 14',
        'target': 6250.0,
        'spent': w2Spent,
        'status': today > 14 ? 'Done' : (today >= 8 ? 'Now' : 'Upcoming'),
      },
      {
        'title': 'Week 3',
        'range': '$monthName 15 - 21',
        'target': 6250.0,
        'spent': w3Spent,
        'status': today > 21 ? 'Done' : (today >= 15 ? 'Now' : 'Upcoming'),
      },
      {
        'title': 'Week 4',
        'range': '$monthName 22 - $daysInMonth',
        'target': 6250.0,
        'spent': w4Spent,
        'status': today >= 22 ? 'Now' : 'Upcoming',
      },
    ];
  }

  yield computeWeeks();

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.transactions) {
      yield computeWeeks();
    }
  }
});

/// Safe-to-Spend reactive calculation provider
final safeToSpendProvider = Provider<SafeToSpendSummary>((ref) {
  final limitsAsync = ref.watch(limitsStreamProvider);
  final spendAsync = ref.watch(currentMonthSpendSummaryProvider);

  final totalSpend = spendAsync.when(
    data: (map) => map['_total_expense'] ?? 0.0,
    loading: () => 0.0,
    error: (_, __) => 0.0,
  );

  // Look for overall monthly limit or compute from categories
  double totalBudget = 25000.0; // Default baseline if not configured
  final limits = limitsAsync.asData?.value ?? [];

  final overallLimit = limits.firstWhere(
    (l) => (l['scope_type'] as String? ?? '').toLowerCase() == 'overall',
    orElse: () => <String, dynamic>{},
  );

  if (overallLimit.isNotEmpty && overallLimit['amount'] != null) {
    totalBudget = (overallLimit['amount'] as num).toDouble();
  } else if (limits.isNotEmpty) {
    // Sum of category limits
    double sum = 0.0;
    for (final l in limits) {
      if (l['scope_type'] == 'category') {
        sum += (l['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    if (sum > 0) totalBudget = sum;
  }

  return BudgetMathService.calculateSafeToSpend(
    totalBudget: totalBudget,
    spentSoFar: totalSpend,
  );
});

/// Action controller for limits & saving plans
class PlanController {
  final Ref _ref;

  PlanController(this._ref);

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

  Future<void> saveCategoryLimit({
    required String category,
    required double limit,
    required String mode,
    String? id,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final limitId = id ?? 'cat_limit_${category.toLowerCase().replaceAll(' ', '_')}';

    db.upsertLimit(
      id: limitId,
      scopeType: 'category',
      scopeId: category,
      periodType: 'monthly',
      amount: limit,
      mode: mode,
      rollover: false,
      alertThresholds: jsonEncode([50, 80, 100]),
      active: true,
      changeSeq: 0,
      isDirty: true,
    );

    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  Future<void> deleteLimit(String id) async {
    final db = await _ref.read(databaseProvider.future);
    db.deleteLimit(id);
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  Future<void> saveSavingPlan({
    required String name,
    required double targetAmount,
    required DateTime targetDate,
    String? id,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final planId = id ?? const Uuid().v4();

    db.upsertSavingPlan(
      id: planId,
      name: name,
      targetAmount: targetAmount,
      targetDate: targetDate,
      status: 'active',
      changeSeq: 0,
      isDirty: true,
    );

    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  Future<void> fundSavingPlan(String id, double amountAdded) async {
    final db = await _ref.read(databaseProvider.future);
    db.addSavingPlanFunding(id, amountAdded);
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  Future<void> deleteSavingPlan(String id) async {
    final db = await _ref.read(databaseProvider.future);
    db.deleteSavingPlan(id);
    _ref.read(syncStateProvider.notifier).triggerSync();
  }
}

final planControllerProvider = Provider<PlanController>((ref) {
  return PlanController(ref);
});
