import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  Future<void> createLimit({
    required String scopeType, // 'overall' or 'category'
    String? scopeId,
    required String periodType, // 'monthly', 'weekly', 'daily'
    required double amount,
    String mode = 'soft',
    bool rollover = false,
    List<int> alertThresholds = const [50, 80, 100],
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final limitId = const Uuid().v4();

    // Insert locally with isDirty = true
    db.upsertLimit(
      id: limitId,
      scopeType: scopeType,
      scopeId: scopeId,
      periodType: periodType,
      amount: amount,
      mode: mode,
      rollover: rollover,
      alertThresholds: jsonEncode(alertThresholds),
      active: true,
      changeSeq: 0,
      isDirty: true,
    );

    // Trigger atomic sync push with single deterministic UUID
    _ref.read(syncStateProvider.notifier).triggerSync();
  }

  Future<void> createSavingPlan({
    required String name,
    required double targetAmount,
    required DateTime targetDate,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final planId = const Uuid().v4();

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
}

final planControllerProvider = Provider<PlanController>((ref) {
  return PlanController(ref);
});
