import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'notification_settings_service.dart';
import '../../data/local/app_database.dart';

enum BudgetAlertType {
  approaching,
  exceeded,
}

class BudgetAlert {
  final String budgetId;
  final String budgetName;
  final double spent;
  final double limitAmount;
  final double percentageUsed;
  final BudgetAlertType alertType;
  final String message;
  final DateTime periodStart;

  BudgetAlert({
    required this.budgetId,
    required this.budgetName,
    required this.spent,
    required this.limitAmount,
    required this.percentageUsed,
    required this.alertType,
    required this.message,
    required this.periodStart,
  });
}

class BudgetAlertService {
  BudgetAlertService._();

  static final BudgetAlertService instance = BudgetAlertService._();

  static const int _budgetNotificationIdBase = 10000;
  static const String _alertSentPrefix = 'budget_alert_sent';

  /// Evaluates all active local limits against current spending in the database
  Future<List<BudgetAlert>> checkBudgetAlerts(AppDatabase db) async {
    final limits = db.getLimits();
    final alerts = <BudgetAlert>[];
    final now = DateTime.now();

    for (final limit in limits) {
      if (limit['active'] == 0 || limit['active'] == false) continue;

      final budgetId = limit['id']?.toString() ?? '';
      final scopeType = limit['scope_type']?.toString() ?? 'global';
      final scopeId = limit['scope_id']?.toString();
      final periodType = limit['period_type']?.toString() ?? 'monthly';
      final limitAmount = (limit['amount'] as num?)?.toDouble() ?? 0.0;
      if (limitAmount <= 0) continue;

      final periodStart = _getPeriodStart(now, periodType);
      final spent = _getSpentForScope(db, scopeType, scopeId, periodStart);

      final percentage = (spent / limitAmount) * 100;
      final name = scopeType == 'category'
          ? (_getCategoryName(db, scopeId) ?? 'Category')
          : 'Total Budget';

      if (spent >= limitAmount) {
        final overAmount = spent - limitAmount;
        final formattedOver = NumberFormat('#,##0.00').format(overAmount);
        alerts.add(
          BudgetAlert(
            budgetId: budgetId,
            budgetName: name,
            spent: spent,
            limitAmount: limitAmount,
            percentageUsed: percentage,
            alertType: BudgetAlertType.exceeded,
            message: '$name budget exceeded by ETB $formattedOver',
            periodStart: periodStart,
          ),
        );
      } else if (percentage >= 80.0) {
        alerts.add(
          BudgetAlert(
            budgetId: budgetId,
            budgetName: name,
            spent: spent,
            limitAmount: limitAmount,
            percentageUsed: percentage,
            alertType: BudgetAlertType.approaching,
            message: '$name budget is ${percentage.toStringAsFixed(1)}% used',
            periodStart: periodStart,
          ),
        );
      }
    }

    return alerts;
  }

  /// Sends notification for a budget alert if enabled and not already sent in this period
  Future<void> sendBudgetAlertNotification(BudgetAlert alert) async {
    final enabled =
        await NotificationSettingsService.instance.isBudgetAlertsEnabled();
    if (!enabled) return;

    final alreadySent = await _hasSentAlert(alert);
    if (alreadySent) return;

    final title = alert.alertType == BudgetAlertType.exceeded
        ? 'Budget Exceeded'
        : 'Budget Warning';

    final id = _budgetNotificationIdBase + (alert.budgetId.hashCode & 0x7fffffff);

    await NotificationService.instance.showBudgetAlertNotification(
      id: id,
      title: title,
      body: alert.message,
    );

    await _markAlertSent(alert);
  }

  Future<void> checkAndNotifyBudgetAlerts(AppDatabase db) async {
    final alerts = await checkBudgetAlerts(db);
    for (final alert in alerts) {
      await sendBudgetAlertNotification(alert);
    }
  }

  Future<bool> _hasSentAlert(BudgetAlert alert) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_alertKey(alert)) ?? false;
  }

  Future<void> _markAlertSent(BudgetAlert alert) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alertKey(alert), true);
  }

  String _alertKey(BudgetAlert alert) {
    final budgetId = alert.budgetId;
    final periodStartMs = alert.periodStart.millisecondsSinceEpoch;
    final type = alert.alertType == BudgetAlertType.exceeded ? 'exceeded' : 'approaching';
    return '$_alertSentPrefix:$budgetId:$type:$periodStartMs';
  }

  DateTime _getPeriodStart(DateTime now, String periodType) {
    if (periodType == 'weekly') {
      final startOfDay = DateTime(now.year, now.month, now.day);
      return startOfDay.subtract(Duration(days: now.weekday - 1));
    }
    // Monthly default
    return DateTime(now.year, now.month, 1);
  }

  double _getSpentForScope(
    AppDatabase db,
    String scopeType,
    String? scopeId,
    DateTime periodStart,
  ) {
    try {
      final txns = db.getTransactions(limit: 1000);
      double total = 0.0;
      for (final tx in txns) {
        final occurredAt = DateTime.tryParse(tx['occurred_at']?.toString() ?? '');
        if (occurredAt == null || occurredAt.isBefore(periodStart)) continue;

        final type = tx['type']?.toString().toLowerCase() ?? '';
        if (type != 'expense' && type != 'debit') continue;

        if (scopeType == 'category' && scopeId != null) {
          if (tx['category_id']?.toString() != scopeId) continue;
        }

        total += (tx['amount'] as num?)?.toDouble() ?? 0.0;
      }
      return total;
    } catch (_) {
      return 0.0;
    }
  }

  String? _getCategoryName(AppDatabase db, String? categoryId) {
    if (categoryId == null) return null;
    try {
      final categories = db.getCategories();
      for (final cat in categories) {
        if (cat['id']?.toString() == categoryId) {
          return cat['name']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }
}
