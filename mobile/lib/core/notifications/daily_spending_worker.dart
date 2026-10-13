import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'notification_service.dart';
import 'notification_settings_service.dart';

const String dailySpendingSummaryTask = 'dailySpendingSummary';
const String dailySpendingSummaryUniqueName = 'dailySpendingSummaryUnique';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();

      if (task != dailySpendingSummaryTask) return true;

      final settings = NotificationSettingsService.instance;
      final scheduledTime = await settings.getDailySummaryTime();
      final now = DateTime.now();

      if (!_isAfterOrEqualTimeOfDay(now, scheduledTime)) return true;

      final prefs = await SharedPreferences.getInstance();
      final todaySpent = prefs.getDouble('today_spending_cache') ?? 0.0;

      final dailyEnabled = await settings.isDailySummaryEnabled();
      if (dailyEnabled) {
        final lastDailySent = await settings.getDailySummaryLastSentAt();
        if (lastDailySent == null || !_isSameDay(lastDailySent, now)) {
          final shown = await NotificationService.instance
              .showDailySpendingNotification(amount: todaySpent);
          if (shown) {
            await settings.setDailySummaryLastSentAt(now);
          }
        }
      }

      final weeklyEnabled = await settings.isWeeklySummaryEnabled();
      if (weeklyEnabled && isWeeklySummarySendDay(now)) {
        final currentWeekStart = _startOfWeek(now);
        final lastWeeklySent = await settings.getWeeklySummaryLastSentAt();
        final alreadySentThisWeek = lastWeeklySent != null &&
            !lastWeeklySent.isBefore(currentWeekStart);
        if (!alreadySentThisWeek) {
          final weekSpent = prefs.getDouble('week_spending_cache') ?? todaySpent;
          final shown = await NotificationService.instance
              .showWeeklySpendingNotification(amount: weekSpent);
          if (shown) {
            await settings.setWeeklySummaryLastSentAt(now);
          }
        }
      }

      final monthlyEnabled = await settings.isMonthlySummaryEnabled();
      if (monthlyEnabled && isMonthlySummarySendDay(now)) {
        final currentMonthStart = DateTime(now.year, now.month, 1);
        final lastMonthlySent = await settings.getMonthlySummaryLastSentAt();
        final alreadySentThisMonth = lastMonthlySent != null &&
            !lastMonthlySent.isBefore(currentMonthStart);
        if (!alreadySentThisMonth) {
          final monthSpent = prefs.getDouble('month_spending_cache') ?? todaySpent;
          final shown = await NotificationService.instance
              .showMonthlySpendingNotification(amount: monthSpent);
          if (shown) {
            await settings.setMonthlySummaryLastSentAt(now);
          }
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('debug: Daily spending worker failed: $e');
      }
      return true;
    }
  });
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isAfterOrEqualTimeOfDay(DateTime now, TimeOfDay time) {
  if (now.hour > time.hour) return true;
  if (now.hour < time.hour) return false;
  return now.minute >= time.minute;
}

bool isWeeklySummarySendDay(DateTime date) {
  return date.weekday == DateTime.sunday;
}

bool isMonthlySummarySendDay(DateTime date) {
  return date.day == _lastDayOfMonth(date).day;
}

DateTime _startOfWeek(DateTime date) {
  final startOfDay = DateTime(date.year, date.month, date.day);
  return startOfDay.subtract(Duration(days: date.weekday - DateTime.monday));
}

DateTime _lastDayOfMonth(DateTime date) {
  return DateTime(date.year, date.month + 1, 0);
}
