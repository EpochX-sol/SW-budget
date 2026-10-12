import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// On-device local notification service providing instant threshold alerts (<50ms)
/// following transaction ingestion without requiring cloud network connectivity.
class LocalNotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  final Set<String> _triggeredAlertsToday = {};

  // Default quiet hours: 22:00 to 07:00
  int quietHoursStart = 22;
  int quietHoursEnd = 7;
  bool showAmountsOnLockScreen = false;

  LocalNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _notificationsPlugin = plugin ?? FlutterLocalNotificationsPlugin() {
    _initialize();
  }

  Future<void> _initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    try {
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          debugPrint('Notification clicked: ${details.payload}');
        },
      );

      // Create Android Notification Channel
      const androidChannel = AndroidNotificationChannel(
        'budget_alerts',
        'Budget & Spending Alerts',
        description: 'Instant on-device alerts when spending approaches budget limits',
        importance: Importance.high,
      );

      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      await androidImplementation?.createNotificationChannel(androidChannel);
    } catch (e) {
      debugPrint('Notification initialization warning: $e');
    }
  }

  /// Checks if current time falls within user-configured quiet hours
  bool isQuietHours(DateTime now) {
    final hour = now.hour;
    if (quietHoursStart > quietHoursEnd) {
      // Overnight (e.g. 22:00 to 07:00)
      return hour >= quietHoursStart || hour < quietHoursEnd;
    } else {
      return hour >= quietHoursStart && hour < quietHoursEnd;
    }
  }

  /// Evaluates threshold crossing and displays local notification if appropriate
  Future<void> evaluateAndNotifyThreshold({
    required String scopeId,
    required String scopeName,
    required int threshold, // 50, 80, 100
    required double spent,
    required double limitAmount,
    DateTime? now,
  }) async {
    final currentDate = now ?? DateTime.now();

    // 1. Quiet Hours check
    if (isQuietHours(currentDate)) {
      debugPrint('Budget alert suppressed during quiet hours ($quietHoursStart:00 - $quietHoursEnd:00)');
      return;
    }

    // 2. Cooldown check: prevent duplicate notifications for same threshold today
    final alertKey = '${scopeId}_${threshold}_${currentDate.year}_${currentDate.month}_${currentDate.day}';
    if (_triggeredAlertsToday.contains(alertKey)) {
      return;
    }
    _triggeredAlertsToday.add(alertKey);

    // 3. Privacy Masking Formatter
    String title;
    String body;

    if (showAmountsOnLockScreen) {
      title = threshold >= 100
          ? 'Budget Exceeded: $scopeName'
          : 'Budget Alert: $scopeName ($threshold%)';
      body = threshold >= 100
          ? 'You have spent ${spent.toStringAsFixed(2)} ETB, exceeding your ${limitAmount.toStringAsFixed(2)} ETB limit.'
          : 'You have spent ${spent.toStringAsFixed(2)} ETB (${threshold}% of ${limitAmount.toStringAsFixed(2)} ETB limit).';
    } else {
      // Privacy-safe text (no exact financial sums visible on lock screen)
      title = threshold >= 100
          ? 'Budget Alert: $scopeName Limit Reached'
          : 'Spending Notice: $scopeName ($threshold%)';
      body = threshold >= 100
          ? 'Your spending in $scopeName has reached 100% of your planned budget.'
          : 'You have utilized $threshold% of your budget envelope for $scopeName.';
    }

    // 4. Trigger Instant Local Notification
    const androidDetails = AndroidNotificationDetails(
      'budget_alerts',
      'Budget & Spending Alerts',
      channelDescription: 'Instant on-device alerts when spending approaches budget limits',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      color: Color(0xFF0F766E), // Emerald brand color
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    final notificationId = alertKey.hashCode & 0x7FFFFFFF;

    try {
      await _notificationsPlugin.show(
        notificationId,
        title,
        body,
        notificationDetails,
        payload: 'limit:$scopeId',
      );
    } catch (e) {
      debugPrint('Failed to show local notification: $e');
    }
  }

  /// Sends morning brief at 07:30
  Future<void> sendMorningBrief({required double todayAllowance}) async {
    const androidDetails = AndroidNotificationDetails(
      'budget_alerts',
      'Daily Briefs & Reports',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFF0F766E),
    );
    try {
      await _notificationsPlugin.show(
        1001,
        'Morning Brief',
        showAmountsOnLockScreen
            ? 'Good morning. You can spend about ${todayAllowance.toStringAsFixed(0)} ETB today.'
            : 'Good morning. Your daily spending allowance is ready in SW-budget.',
        const NotificationDetails(android: androidDetails),
      );
    } catch (_) {}
  }

  /// Sends daily report at 21:00
  Future<void> sendDailyReport({
    required double todaySpent,
    required double todayAllowance,
    required double leftToSpend,
    required int daysRemaining,
    required double tomorrowAllowance,
    required double totalExpectedToPay,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'budget_alerts',
      'Daily Briefs & Reports',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFF0F766E),
    );
    try {
      await _notificationsPlugin.show(
        1002,
        'Daily Spending Report',
        showAmountsOnLockScreen
            ? 'Today: ${todaySpent.toStringAsFixed(0)} of ${todayAllowance.toStringAsFixed(0)} spent. ${leftToSpend.toStringAsFixed(0)} ETB left, $daysRemaining days to go. Tomorrow: ${tomorrowAllowance.toStringAsFixed(0)} ETB.'
            : 'Daily report ready: review today\'s spending and tomorrow\'s target in SW-budget.',
        const NotificationDetails(android: androidDetails),
      );
    } catch (_) {}
  }

  /// Sends alert when emergency reserve begins being used
  Future<void> sendReserveAlert({
    required double reserveUsed,
    required double totalReserve,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'budget_alerts',
      'Emergency Reserve Alerts',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFFF59E0B),
    );
    try {
      await _notificationsPlugin.show(
        1003,
        'Emergency Reserve Notice',
        showAmountsOnLockScreen
            ? 'You\'ve started using your emergency reserve (${reserveUsed.toStringAsFixed(0)} of ${totalReserve.toStringAsFixed(0)} ETB).'
            : 'You have entered your emergency reserve safety cushion.',
        const NotificationDetails(android: androidDetails),
      );
    } catch (_) {}
  }
}

final localNotificationServiceProvider = Provider<LocalNotificationService>((ref) {
  return LocalNotificationService();
});

