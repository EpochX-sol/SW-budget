import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsService {
  NotificationSettingsService._();

  static final NotificationSettingsService instance =
      NotificationSettingsService._();

  static const _kTransactionEnabled = 'notifications_transaction_enabled';
  static const _kFailedParseReviewEnabled =
      'notifications_failed_parse_review_enabled';
  static const _kBudgetEnabled = 'notifications_budget_enabled';
  static const _kDailyEnabled = 'notifications_daily_enabled';
  static const _kDailyHour = 'notifications_daily_hour';
  static const _kDailyMinute = 'notifications_daily_minute';
  static const _kDailyLastSentEpochMs =
      'notifications_daily_last_sent_epoch_ms';
  static const _kWeeklyEnabled = 'notifications_weekly_enabled';
  static const _kWeeklyLastSentEpochMs =
      'notifications_weekly_last_sent_epoch_ms';
  static const _kMonthlyEnabled = 'notifications_monthly_enabled';
  static const _kMonthlyLastSentEpochMs =
      'notifications_monthly_last_sent_epoch_ms';
  static const _kQuickCategorizeIncomeIds = 'quick_categorize_income_ids';
  static const _kQuickCategorizeExpenseIds = 'quick_categorize_expense_ids';

  Future<bool> isTransactionNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kTransactionEnabled) ?? true;
  }

  Future<void> setTransactionNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTransactionEnabled, enabled);
  }

  Future<bool> isFailedParseReviewNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kFailedParseReviewEnabled) ?? true;
  }

  Future<void> setFailedParseReviewNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFailedParseReviewEnabled, enabled);
  }

  Future<bool> isBudgetAlertsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBudgetEnabled) ?? true;
  }

  Future<void> setBudgetAlertsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBudgetEnabled, enabled);
  }

  Future<bool> isDailySummaryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDailyEnabled) ?? true;
  }

  Future<void> setDailySummaryEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDailyEnabled, enabled);
  }

  Future<TimeOfDay> getDailySummaryTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_kDailyHour) ?? 20;
    final minute = prefs.getInt(_kDailyMinute) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> setDailySummaryTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDailyHour, time.hour);
    await prefs.setInt(_kDailyMinute, time.minute);
  }

  Future<DateTime?> getDailySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kDailyLastSentEpochMs);
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> setDailySummaryLastSentAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDailyLastSentEpochMs, time.millisecondsSinceEpoch);
  }

  Future<void> clearDailySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDailyLastSentEpochMs);
  }

  Future<bool> isWeeklySummaryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kWeeklyEnabled) ?? true;
  }

  Future<void> setWeeklySummaryEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWeeklyEnabled, enabled);
  }

  Future<DateTime?> getWeeklySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kWeeklyLastSentEpochMs);
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> setWeeklySummaryLastSentAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWeeklyLastSentEpochMs, time.millisecondsSinceEpoch);
  }

  Future<void> clearWeeklySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWeeklyLastSentEpochMs);
  }

  Future<bool> isMonthlySummaryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kMonthlyEnabled) ?? false;
  }

  Future<void> setMonthlySummaryEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMonthlyEnabled, enabled);
  }

  Future<DateTime?> getMonthlySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kMonthlyLastSentEpochMs);
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> setMonthlySummaryLastSentAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMonthlyLastSentEpochMs, time.millisecondsSinceEpoch);
  }

  Future<void> clearMonthlySummaryLastSentAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMonthlyLastSentEpochMs);
  }

  Future<bool> isAnySpendingSummaryEnabled() async {
    return await isDailySummaryEnabled() ||
        await isWeeklySummaryEnabled() ||
        await isMonthlySummaryEnabled();
  }

  Future<List<String>> getQuickCategorizeIncomeIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kQuickCategorizeIncomeIds) ?? <String>[];
  }

  Future<void> setQuickCategorizeIncomeIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kQuickCategorizeIncomeIds, ids.take(3).toList());
  }

  Future<List<String>> getQuickCategorizeExpenseIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kQuickCategorizeExpenseIds) ?? <String>[];
  }

  Future<void> setQuickCategorizeExpenseIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kQuickCategorizeExpenseIds, ids.take(3).toList());
  }
}
