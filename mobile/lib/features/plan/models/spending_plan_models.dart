import '../../../domain/use_cases/adaptive_spending_engine.dart';

class BudgetPlan {
  final String id;
  final String userId;
  final String name;
  final double totalAmount;
  final DateTime startDate;
  final DateTime endDate;
  final RolloverMode rolloverMode;
  final double reservePercent;
  final double savingGoal;
  final double minDailyFloor;
  final bool active;
  final List<FixedExpense> fixedExpenses;
  final List<CategoryLimit> categoryLimits;

  const BudgetPlan({
    required this.id,
    required this.userId,
    required this.name,
    required this.totalAmount,
    required this.startDate,
    required this.endDate,
    this.rolloverMode = RolloverMode.spreadEvenly,
    this.reservePercent = 0.0,
    this.savingGoal = 0.0,
    this.minDailyFloor = 0.0,
    this.active = true,
    this.fixedExpenses = const [],
    this.categoryLimits = const [],
  });

  int get totalDays => endDate.difference(startDate).inDays + 1;

  double get fixedExpensesTotal {
    return fixedExpenses.fold(0.0, (sum, item) => sum + item.amount);
  }

  factory BudgetPlan.fromJson(Map<String, dynamic> json) {
    return BudgetPlan(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? 'My Spending Plan',
      totalAmount: (json['total_amount'] as num).toDouble(),
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      rolloverMode: RolloverMode.fromString(json['rollover_mode'] as String? ?? 'SPREAD_EVENLY'),
      reservePercent: (json['reserve_percent'] as num?)?.toDouble() ?? 0.0,
      savingGoal: (json['saving_goal'] as num?)?.toDouble() ?? 0.0,
      minDailyFloor: (json['min_daily_floor'] as num?)?.toDouble() ?? 0.0,
      active: json['active'] as bool? ?? true,
      fixedExpenses: (json['fixed_expenses'] as List?)
              ?.map((e) => FixedExpense.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      categoryLimits: (json['category_limits'] as List?)
              ?.map((e) => CategoryLimit.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
  }
}

class FixedExpense {
  final String id;
  final String planId;
  final String title;
  final double amount;
  final DateTime? dueDate;
  final bool paid;

  const FixedExpense({
    required this.id,
    required this.planId,
    required this.title,
    required this.amount,
    this.dueDate,
    this.paid = false,
  });

  factory FixedExpense.fromJson(Map<String, dynamic> json) {
    return FixedExpense(
      id: json['id'] as String,
      planId: json['plan_id'] as String? ?? '',
      title: json['title'] as String,
      amount: (json['amount'] as num).toDouble(),
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      paid: json['paid'] as bool? ?? false,
    );
  }
}

class CategoryLimit {
  final String id;
  final String planId;
  final String category;
  final double amount;

  const CategoryLimit({
    required this.id,
    required this.planId,
    required this.category,
    required this.amount,
  });

  factory CategoryLimit.fromJson(Map<String, dynamic> json) {
    return CategoryLimit(
      id: json['id'] as String,
      planId: json['plan_id'] as String? ?? '',
      category: json['category'] as String,
      amount: (json['amount'] as num).toDouble(),
    );
  }
}
