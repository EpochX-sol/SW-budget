import 'dart:convert';
import 'package:intl/intl.dart';

/// Budget Zone based on Emergency Reserve consumption
enum PlanBudgetZone {
  withinBudget,
  usingReserve,
  overPlan,
}

/// Evaluation result for a single transaction against the 10 plan rules
class EvaluatedPlanTransaction {
  final Map<String, dynamic> rawTransaction;
  final bool countsInPlan;
  final String? exclusionReason;
  final double netImpact; // Positive for expense, negative for refund/reversal

  const EvaluatedPlanTransaction({
    required this.rawTransaction,
    required this.countsInPlan,
    this.exclusionReason,
    required this.netImpact,
  });

  String get id => rawTransaction['id'] as String? ?? '';
  String get accountId => rawTransaction['account_id'] as String? ?? '';
  String? get categoryId => rawTransaction['category_id'] as String?;
  String get type => rawTransaction['type'] as String? ?? 'expense';
  double get amount => (rawTransaction['amount'] as num?)?.toDouble() ?? 0.0;
  DateTime get occurredAt =>
      DateTime.tryParse(rawTransaction['occurred_at'] as String? ?? '') ?? DateTime.now();
  String? get counterparty => rawTransaction['counterparty'] as String?;
  String? get note => rawTransaction['note'] as String?;
}

/// Weekly chunk representation for the 7-day weekly view
class PlanWeekChunk {
  final int weekNumber;
  final String label;
  final DateTime startDate;
  final DateTime endDate;
  final double plannedTarget;
  final double spent;
  final String status; // 'Done', 'Now', 'Upcoming'

  const PlanWeekChunk({
    required this.weekNumber,
    required this.label,
    required this.startDate,
    required this.endDate,
    required this.plannedTarget,
    required this.spent,
    required this.status,
  });
}

/// Complete computed snapshot of the plan's daily state
class PlanEvaluationSnapshot {
  final Map<String, dynamic> plan;
  final List<Map<String, dynamic>> expectedExpenses;
  final List<EvaluatedPlanTransaction> allTransactionsInRange;
  final List<EvaluatedPlanTransaction> countedTransactions;
  final List<EvaluatedPlanTransaction> excludedTransactions;

  // Key money figures
  final double spendingLimit;
  final double emergencyReserve;
  final double spendableBudget;
  final double totalSpent;
  final double leftToSpend;
  final PlanBudgetZone zone;
  final double reserveUsed;
  final double overspendAmount;

  // Day tracking
  final int totalDays;
  final int daysElapsed;
  final int daysRemaining;
  final double dailyPlanBaseline;

  // Today & Tomorrow
  final double todaySpent;
  final double todayAllowance;
  final double todayRemaining;
  final double tomorrowAllowance;
  final double tomorrowPctOfNormal;

  // Pace & Runway
  final String paceStatus; // 'under', 'on_track', 'over'
  final DateTime? projectedRunwayDate;

  // Expected Expenses summary
  final double totalExpected;
  final double totalExpectedPaid;
  final double totalExpectedToPay;
  final Map<String, dynamic>? nextDueExpectedExpense;

  // Not Counted summary
  final double totalNotCountedAmount;
  final Map<String, double> notCountedByReason;

  // Breakdowns (Counted spending only)
  final Map<String, double> spendByCategory;
  final Map<String, double> spendByAccount;

  // Weekly view
  final List<PlanWeekChunk> weeklyChunks;

  const PlanEvaluationSnapshot({
    required this.plan,
    required this.expectedExpenses,
    required this.allTransactionsInRange,
    required this.countedTransactions,
    required this.excludedTransactions,
    required this.spendingLimit,
    required this.emergencyReserve,
    required this.spendableBudget,
    required this.totalSpent,
    required this.leftToSpend,
    required this.zone,
    required this.reserveUsed,
    required this.overspendAmount,
    required this.totalDays,
    required this.daysElapsed,
    required this.daysRemaining,
    required this.dailyPlanBaseline,
    required this.todaySpent,
    required this.todayAllowance,
    required this.todayRemaining,
    required this.tomorrowAllowance,
    required this.tomorrowPctOfNormal,
    required this.paceStatus,
    this.projectedRunwayDate,
    required this.totalExpected,
    required this.totalExpectedPaid,
    required this.totalExpectedToPay,
    this.nextDueExpectedExpense,
    required this.totalNotCountedAmount,
    required this.notCountedByReason,
    required this.spendByCategory,
    required this.spendByAccount,
    required this.weeklyChunks,
  });
}

/// Pure Dart calculation & rule evaluation engine for Plan Feature Definition v2
class PlanEvaluationEngine {
  /// Evaluates the active plan against all local transactions and expected expenses
  static PlanEvaluationSnapshot evaluate({
    required Map<String, dynamic> plan,
    required List<Map<String, dynamic>> expectedExpenses,
    required List<Map<String, dynamic>> rawTransactions,
    DateTime? nowOverride,
  }) {
    final now = nowOverride ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final startDateRaw = DateTime.parse(plan['start_date'] as String);
    final endDateRaw = DateTime.parse(plan['end_date'] as String);
    final startDate = DateTime(startDateRaw.year, startDateRaw.month, startDateRaw.day);
    final endDate = DateTime(endDateRaw.year, endDateRaw.month, endDateRaw.day, 23, 59, 59, 999);

    final spendingLimit = (plan['spending_limit'] as num?)?.toDouble() ?? 0.0;
    final reserveType = (plan['reserve_type'] as String? ?? 'none').toLowerCase();
    final reserveValue = (plan['reserve_value'] as num?)?.toDouble() ?? 0.0;

    double emergencyReserve = 0.0;
    if (reserveType == 'fixed') {
      emergencyReserve = reserveValue.clamp(0.0, spendingLimit);
    } else if (reserveType == 'percentage') {
      final pct = reserveValue.clamp(0.0, 90.0);
      emergencyReserve = spendingLimit * (pct / 100.0);
    }

    final spendableBudget = (spendingLimit - emergencyReserve).clamp(0.0, double.infinity);

    // Watched banks
    Set<String>? watchedBanks;
    final watchedBankIdsRaw = plan['watched_bank_ids'];
    if (watchedBankIdsRaw != null && watchedBankIdsRaw.toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(watchedBankIdsRaw.toString());
        if (decoded is List) {
          watchedBanks = decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {}
    }

    final countFees = (plan['count_fees'] as num?)?.toInt() == 1 || plan['count_fees'] == true;
    final countWithdrawals =
        (plan['count_withdrawals'] as num?)?.toInt() == 1 || plan['count_withdrawals'] == true;
    final reactionMode = (plan['reaction_mode'] as String? ?? 'adaptive').toLowerCase();

    // Map expected expenses and categories
    final Map<String, Map<String, dynamic>> expectedExpenseByLinkedCategory = {};
    final Set<String> paidTxnIds = {};
    double totalExpected = 0.0;
    double totalExpectedPaid = 0.0;
    Map<String, dynamic>? nextDueExpense;
    DateTime? earliestDue;

    for (final exp in expectedExpenses) {
      if (exp['deleted_at'] != null) continue;
      final amount = (exp['amount'] as num?)?.toDouble() ?? 0.0;
      final isPaid = (exp['status'] as String? ?? '').toLowerCase() == 'paid';
      totalExpected += amount;
      if (isPaid) {
        totalExpectedPaid += (exp['paid_amount'] as num?)?.toDouble() ?? amount;
      } else {
        final dueStr = exp['due_date'] as String?;
        if (dueStr != null) {
          final due = DateTime.tryParse(dueStr);
          if (due != null && (earliestDue == null || due.isBefore(earliestDue))) {
            earliestDue = due;
            nextDueExpense = exp;
          }
        }
      }

      final linkedCat = exp['linked_category_id'] as String?;
      if (linkedCat != null && linkedCat.isNotEmpty) {
        expectedExpenseByLinkedCategory[linkedCat] = exp;
      }
      final paidTxn = exp['paid_txn_id'] as String?;
      if (paidTxn != null && paidTxn.isNotEmpty) {
        paidTxnIds.add(paidTxn);
      }
    }

    final totalExpectedToPay = (totalExpected - totalExpectedPaid).clamp(0.0, double.infinity);

    // Evaluate all transactions against the 10 Rules
    final List<EvaluatedPlanTransaction> allEvaluated = [];
    final List<EvaluatedPlanTransaction> countedList = [];
    final List<EvaluatedPlanTransaction> excludedList = [];
    final Map<String, double> notCountedByReason = {};
    double totalNotCountedAmount = 0.0;
    double totalSpent = 0.0;
    double todaySpent = 0.0;
    final Map<String, double> spendByCategory = {};
    final Map<String, double> spendByAccount = {};

    for (final txn in rawTransactions) {
      final evaluated = _evaluateSingleTransaction(
        txn: txn,
        startDate: startDate,
        endDate: endDate,
        watchedBanks: watchedBanks,
        countFees: countFees,
        countWithdrawals: countWithdrawals,
        expectedExpenseByLinkedCategory: expectedExpenseByLinkedCategory,
        paidTxnIds: paidTxnIds,
      );

      // We only care about transactions occurring within or relevant to the plan for UI listing
      if (evaluated != null) {
        allEvaluated.add(evaluated);

        if (evaluated.countsInPlan) {
          countedList.add(evaluated);
          totalSpent += evaluated.netImpact;

          // Check if happened today
          if (evaluated.occurredAt.year == today.year &&
              evaluated.occurredAt.month == today.month &&
              evaluated.occurredAt.day == today.day) {
            todaySpent += evaluated.netImpact;
          }

          // Category & account breakdowns
          final cat = evaluated.categoryId ?? 'uncategorized';
          final acc = evaluated.accountId;
          spendByCategory[cat] = (spendByCategory[cat] ?? 0.0) + evaluated.netImpact;
          spendByAccount[acc] = (spendByAccount[acc] ?? 0.0) + evaluated.netImpact;
        } else {
          excludedList.add(evaluated);
          totalNotCountedAmount += evaluated.amount;
          final reason = evaluated.exclusionReason ?? 'Excluded';
          notCountedByReason[reason] = (notCountedByReason[reason] ?? 0.0) + evaluated.amount;
        }
      }
    }

    // Days elapsed & remaining
    final pausedDays = (plan['paused_days_count'] as num?)?.toInt() ?? 0;
    int totalDays = endDate.difference(startDate).inDays + 1;
    if (totalDays <= 0) totalDays = 1;

    int daysElapsed = 1;
    if (today.isBefore(startDate)) {
      daysElapsed = 0;
    } else if (today.isAfter(endDate)) {
      daysElapsed = totalDays;
    } else {
      daysElapsed = today.difference(startDate).inDays + 1 - pausedDays;
      if (daysElapsed < 1) daysElapsed = 1;
      if (daysElapsed > totalDays) daysElapsed = totalDays;
    }

    final int daysRemaining = (totalDays - daysElapsed + 1).clamp(1, totalDays);
    final double dailyPlanBaseline = totalDays > 0 ? spendableBudget / totalDays : spendableBudget;

    // Remaining money & Zone
    final double leftToSpend = spendableBudget - totalSpent;
    PlanBudgetZone zone;
    double reserveUsed = 0.0;
    double overspendAmount = 0.0;

    if (totalSpent <= spendableBudget) {
      zone = PlanBudgetZone.withinBudget;
    } else if (totalSpent <= spendingLimit) {
      zone = PlanBudgetZone.usingReserve;
      reserveUsed = totalSpent - spendableBudget;
    } else {
      zone = PlanBudgetZone.overPlan;
      reserveUsed = emergencyReserve;
      overspendAmount = totalSpent - spendingLimit;
    }

    // Daily Allowance (Adaptive vs Fixed)
    double todayAllowance = dailyPlanBaseline;
    double tomorrowAllowance = dailyPlanBaseline;

    if (reactionMode == 'adaptive') {
      if (zone == PlanBudgetZone.overPlan) {
        todayAllowance = 0.0;
        tomorrowAllowance = 0.0;
      } else {
        // Spendable budget remaining before today
        final spentBeforeToday = (totalSpent - todaySpent).clamp(0.0, double.infinity);
        final remainingForPeriod = (spendableBudget - spentBeforeToday).clamp(0.0, double.infinity);
        todayAllowance = daysRemaining > 0 ? remainingForPeriod / daysRemaining : remainingForPeriod;

        // Tomorrow allowance
        final remainingForTomorrow = (spendableBudget - totalSpent).clamp(0.0, double.infinity);
        final daysAfterToday = daysRemaining - 1;
        tomorrowAllowance = daysAfterToday > 0 ? remainingForTomorrow / daysAfterToday : 0.0;
      }
    } else {
      // Fixed daily mode: daily allowance stays baseline
      todayAllowance = dailyPlanBaseline;
      tomorrowAllowance = dailyPlanBaseline;
    }

    final double todayRemaining = todayAllowance - todaySpent;
    final double tomorrowPctOfNormal =
        dailyPlanBaseline > 0 ? (tomorrowAllowance / dailyPlanBaseline) * 100.0 : 100.0;

    // Pace & Runway prediction
    final double expectedSpendToDate = dailyPlanBaseline * daysElapsed;
    String paceStatus = 'on_track';
    if (totalSpent < expectedSpendToDate * 0.90) {
      paceStatus = 'under';
    } else if (totalSpent > expectedSpendToDate * 1.10) {
      paceStatus = 'over';
    }

    DateTime? runwayDate;
    if (daysElapsed > 0 && totalSpent > 0) {
      final double avgDailyActual = totalSpent / daysElapsed;
      if (avgDailyActual > 0) {
        final daysBudgetWillLast = (spendableBudget / avgDailyActual).round();
        runwayDate = startDate.add(Duration(days: daysBudgetWillLast));
      }
    }

    // Weekly chunk breakdown (7-day intervals)
    final weeklyChunks = _partitionWeeks(
      startDate: startDate,
      endDate: endDate,
      spendableBudget: spendableBudget,
      totalDays: totalDays,
      today: today,
      countedTransactions: countedList,
    );

    return PlanEvaluationSnapshot(
      plan: plan,
      expectedExpenses: expectedExpenses,
      allTransactionsInRange: allEvaluated,
      countedTransactions: countedList,
      excludedTransactions: excludedList,
      spendingLimit: spendingLimit,
      emergencyReserve: emergencyReserve,
      spendableBudget: spendableBudget,
      totalSpent: totalSpent,
      leftToSpend: leftToSpend,
      zone: zone,
      reserveUsed: reserveUsed,
      overspendAmount: overspendAmount,
      totalDays: totalDays,
      daysElapsed: daysElapsed,
      daysRemaining: daysRemaining,
      dailyPlanBaseline: dailyPlanBaseline,
      todaySpent: todaySpent,
      todayAllowance: todayAllowance,
      todayRemaining: todayRemaining,
      tomorrowAllowance: tomorrowAllowance,
      tomorrowPctOfNormal: tomorrowPctOfNormal,
      paceStatus: paceStatus,
      projectedRunwayDate: runwayDate,
      totalExpected: totalExpected,
      totalExpectedPaid: totalExpectedPaid,
      totalExpectedToPay: totalExpectedToPay,
      nextDueExpectedExpense: nextDueExpense,
      totalNotCountedAmount: totalNotCountedAmount,
      notCountedByReason: notCountedByReason,
      spendByCategory: spendByCategory,
      spendByAccount: spendByAccount,
      weeklyChunks: weeklyChunks,
    );
  }

  /// Evaluates a single transaction strictly against the 10 sequential rules
  static EvaluatedPlanTransaction? _evaluateSingleTransaction({
    required Map<String, dynamic> txn,
    required DateTime startDate,
    required DateTime endDate,
    required Set<String>? watchedBanks,
    required bool countFees,
    required bool countWithdrawals,
    required Map<String, Map<String, dynamic>> expectedExpenseByLinkedCategory,
    required Set<String> paidTxnIds,
  }) {
    // Rule 1: Not deleted
    if (txn['deleted_at'] != null) {
      return null;
    }

    final occurredAtStr = txn['occurred_at'] as String?;
    final occurredAt = occurredAtStr != null ? DateTime.tryParse(occurredAtStr) : null;
    if (occurredAt == null) return null;

    final amount = (txn['amount'] as num?)?.toDouble() ?? 0.0;
    final type = (txn['type'] as String? ?? '').toLowerCase();
    final accountId = txn['account_id'] as String? ?? '';
    final categoryId = txn['category_id'] as String?;
    final txnId = txn['id'] as String? ?? '';
    final isExcludedByFlag = txn['exclude_from_plan'] == 1 || txn['exclude_from_plan'] == true;
    final exclusionCustomReason = txn['plan_exclusion_reason'] as String?;

    // Rule 2: Date inside plan period
    if (occurredAt.isBefore(startDate) || occurredAt.isAfter(endDate)) {
      return EvaluatedPlanTransaction(
        rawTransaction: txn,
        countsInPlan: false,
        exclusionReason: 'Outside the plan period',
        netImpact: 0.0,
      );
    }

    // Rule 3: Not a transfer between own accounts
    final isInternalTransfer = txn['is_internal_transfer'] == 1 || txn['is_internal_transfer'] == true;
    if (type == 'transfer' || type == 'transfer_in' || isInternalTransfer) {
      return EvaluatedPlanTransaction(
        rawTransaction: txn,
        countsInPlan: false,
        exclusionReason: 'Transfer between your accounts',
        netImpact: 0.0,
      );
    }

    // Rule 4: Reviewed (items needing review are paused from counting)
    final needsReview = txn['needs_review'] == 1 || txn['needs_review'] == true;
    if (needsReview) {
      return EvaluatedPlanTransaction(
        rawTransaction: txn,
        countsInPlan: false,
        exclusionReason: 'Needs review',
        netImpact: 0.0,
      );
    }

    // Rule 5: Spending or refund
    final isRefund = type == 'reversal' || type == 'refund';
    final isSpending = type == 'expense' ||
        type == 'transfer_out' ||
        type == 'withdrawal' ||
        type == 'fee' ||
        isRefund;

    if (!isSpending || type == 'income') {
      return EvaluatedPlanTransaction(
        rawTransaction: txn,
        countsInPlan: false,
        exclusionReason: 'Not spending',
        netImpact: 0.0,
      );
    }

    // Rule 6: Bank is part of the plan
    if (watchedBanks != null && !watchedBanks.contains(accountId)) {
      return EvaluatedPlanTransaction(
        rawTransaction: txn,
        countsInPlan: false,
        exclusionReason: 'Bank not in this plan',
        netImpact: 0.0,
      );
    }

    // Rule 7: User marked it "Don't count in plan"
    if (isExcludedByFlag) {
      return EvaluatedPlanTransaction(
        rawTransaction: txn,
        countsInPlan: false,
        exclusionReason: exclusionCustomReason ?? 'You marked it not counted',
        netImpact: 0.0,
      );
    }

    // Rule 8: Not paying an expected expense
    if (paidTxnIds.contains(txnId)) {
      return EvaluatedPlanTransaction(
        rawTransaction: txn,
        countsInPlan: false,
        exclusionReason: 'Paid expected expense',
        netImpact: 0.0,
      );
    }
    if (categoryId != null && expectedExpenseByLinkedCategory.containsKey(categoryId)) {
      final exp = expectedExpenseByLinkedCategory[categoryId]!;
      final expName = exp['name'] as String? ?? 'Expected expense';
      return EvaluatedPlanTransaction(
        rawTransaction: txn,
        countsInPlan: false,
        exclusionReason: 'Paid expected expense: $expName',
        netImpact: 0.0,
      );
    }

    // Rule 9: Fees counted
    final isFee = type == 'fee' ||
        (txn['note'] as String? ?? '').toLowerCase().contains('service charge') ||
        (txn['counterparty'] as String? ?? '').toLowerCase().contains('service charge');
    if (isFee && !countFees) {
      return EvaluatedPlanTransaction(
        rawTransaction: txn,
        countsInPlan: false,
        exclusionReason: 'Fees are not counted',
        netImpact: 0.0,
      );
    }

    // Rule 10: Cash withdrawals counted
    final isWithdrawal = type == 'withdrawal' ||
        (txn['counterparty'] as String? ?? '').toLowerCase().contains('atm') ||
        (txn['raw_body'] as String? ?? '').toLowerCase().contains('withdrawn');
    if (isWithdrawal && !countWithdrawals) {
      return EvaluatedPlanTransaction(
        rawTransaction: txn,
        countsInPlan: false,
        exclusionReason: 'Cash withdrawals are not counted',
        netImpact: 0.0,
      );
    }

    // Qualifying counted transaction!
    final netImpact = isRefund ? -amount : amount;
    return EvaluatedPlanTransaction(
      rawTransaction: txn,
      countsInPlan: true,
      exclusionReason: null,
      netImpact: netImpact,
    );
  }

  /// Partitions the plan period into 7-day weekly chunks
  static List<PlanWeekChunk> _partitionWeeks({
    required DateTime startDate,
    required DateTime endDate,
    required double spendableBudget,
    required int totalDays,
    required DateTime today,
    required List<EvaluatedPlanTransaction> countedTransactions,
  }) {
    final List<PlanWeekChunk> chunks = [];
    final int numWeeks = (totalDays / 7.0).ceil();
    final double weeklyTarget = numWeeks > 0 ? spendableBudget / numWeeks : spendableBudget;

    DateTime curStart = startDate;
    for (int w = 1; w <= numWeeks; w++) {
      DateTime curEnd = curStart.add(const Duration(days: 6));
      if (curEnd.isAfter(endDate) || w == numWeeks) {
        curEnd = endDate;
      }

      double spentThisWeek = 0.0;
      for (final t in countedTransactions) {
        if (!t.occurredAt.isBefore(curStart) && !t.occurredAt.isAfter(curEnd)) {
          spentThisWeek += t.netImpact;
        }
      }

      String status = 'Upcoming';
      if (today.isAfter(curEnd)) {
        status = 'Done';
      } else if (!today.isBefore(curStart) && !today.isAfter(curEnd)) {
        status = 'Now';
      }

      final startLabel = DateFormat('d MMM').format(curStart);
      final endLabel = DateFormat('d MMM').format(curEnd);

      chunks.add(PlanWeekChunk(
        weekNumber: w,
        label: '$startLabel - $endLabel',
        startDate: curStart,
        endDate: curEnd,
        plannedTarget: weeklyTarget,
        spent: spentThisWeek,
        status: status,
      ));

      curStart = curEnd.add(const Duration(days: 1));
      if (curStart.isAfter(endDate)) break;
    }

    return chunks;
  }
}
