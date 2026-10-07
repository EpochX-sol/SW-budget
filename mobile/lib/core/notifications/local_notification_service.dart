import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
}
