import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_intent_bus.dart';
import 'notification_settings_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _transactionChannelId = 'transactions';
  static const String _failedParseReviewChannelId = 'failed_parse_review';
  static const String _spendingSummaryChannelId = 'spending_summaries';
  static const String _accountSyncChannelId = 'account_sync';
  static const String _accountSyncCompleteChannelId = 'account_sync_complete';
  static const String _budgetChannelId = 'budgets';
  static const String _loanDebtRemindersChannelId = 'loan_debt_reminders';
  static const String _dataSyncChannelId = 'data_sync';
  static const String _historyPrefsKey = 'notification_history_v1';
  static const String _counterpartyActionPrefix = 'txname:';
  static const int _maxHistoryEntries = 200;

  static const int dailySpendingNotificationId = 9001;
  static const int dailySpendingTestNotificationId = 9002;
  static const int weeklySpendingNotificationId = 9003;
  static const int weeklySpendingTestNotificationId = 9004;
  static const int monthlySpendingNotificationId = 9005;
  static const int monthlySpendingTestNotificationId = 9006;
  static const int dataSyncResultNotificationId = 9008;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionRequestInProgress = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _transactionChannelId,
        'Transactions',
        description: 'Notifications when a new transaction is detected',
        importance: Importance.high,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _failedParseReviewChannelId,
        'Failed parse review',
        description: 'Prompts to confirm unparsed bank transactions',
        importance: Importance.high,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _spendingSummaryChannelId,
        'Spending summaries',
        description: 'Daily, weekly, and monthly spending summaries',
        importance: Importance.defaultImportance,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _accountSyncChannelId,
        'Account sync',
        description: 'Background sync of account transactions',
        importance: Importance.low,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _accountSyncCompleteChannelId,
        'Account sync results',
        description: 'Completion summaries for account transaction syncs',
        importance: Importance.defaultImportance,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _budgetChannelId,
        'Budget Alerts',
        description: 'Notifications for budget warnings and alerts',
        importance: Importance.defaultImportance,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _loanDebtRemindersChannelId,
        'Loan and debt reminders',
        description: 'Return date reminders for loans and debts',
        importance: Importance.high,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _dataSyncChannelId,
        'Data Sync',
        description: 'Results of syncing your data to your backend',
        importance: Importance.defaultImportance,
      ),
    );

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    _handleNotificationResponse(response);
  }

  Future<void> _handleNotificationResponse(NotificationResponse response) async {
    try {
      if (response.notificationResponseType ==
          NotificationResponseType.selectedNotificationAction) {
        final actionId = response.actionId;
        if (actionId != null && actionId.startsWith(_counterpartyActionPrefix)) {
          await _handleCounterpartyInputAction(
            actionId,
            response.input,
            response.id,
          );
          return;
        }
        if (actionId != null && actionId.contains('|cat:')) {
          await _handleQuickCategorizeAction(actionId, response.id);
          return;
        }
        if (actionId != null && actionId.startsWith('fp|')) {
          await _handleFailedParseReviewAction(actionId, response.id);
          return;
        }
      }

      final payload = response.notificationResponseType ==
              NotificationResponseType.selectedNotificationAction
          ? response.actionId
          : response.payload;

      final intent = _intentFromPayload(payload);
      if (intent != null) {
        NotificationIntentBus.instance.emit(intent);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('debug: Failed handling notification response: $e');
      }
    }
  }

  NotificationIntent? _intentFromPayload(String? payload) {
    final raw = payload?.trim();
    if (raw == null || raw.isEmpty) return null;

    if (raw.startsWith('tx:')) {
      final rest = raw.substring(3);
      final parts = rest.split('|cat:');
      final reference = Uri.decodeComponent(parts[0]);
      if (reference.trim().isEmpty) return null;

      if (parts.length > 1) {
        final categoryId = parts[1];
        return QuickCategorizeTransactionIntent(reference, categoryId);
      }
      return CategorizeTransactionIntent(reference);
    }

    if (raw.startsWith('fp:')) {
      final reviewId = Uri.decodeComponent(raw.substring(3));
      return OpenFailedParseReviewIntent(reviewId);
    }

    return null;
  }

  Future<void> _handleCounterpartyInputAction(
    String actionId,
    String? input,
    int? notificationId,
  ) async {
    final submittedName = input?.trim();
    if (submittedName == null || submittedName.isEmpty) return;

    final reference = Uri.decodeComponent(
      actionId.substring(_counterpartyActionPrefix.length),
    );
    if (reference.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_counterparty_update:$reference', submittedName);

    if (notificationId != null) {
      await _plugin.cancel(notificationId);
    }
  }

  Future<void> _handleQuickCategorizeAction(
    String actionId,
    int? notificationId,
  ) async {
    final parts = actionId.split('|cat:');
    if (parts.length != 2) return;

    final reference = Uri.decodeComponent(parts[0].substring(3));
    final categoryId = parts[1];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_categorize_update:$reference', categoryId);

    if (notificationId != null) {
      await _plugin.cancel(notificationId);
    }
  }

  Future<void> _handleFailedParseReviewAction(
    String actionId,
    int? notificationId,
  ) async {
    final parts = actionId.split('|');
    if (parts.length != 3 || parts[0] != 'fp') return;

    final decision = parts[1];
    final candidateId = parts[2];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_failed_parse_decision:$candidateId', decision);

    if (notificationId != null) {
      await _plugin.cancel(notificationId);
    }
  }

  Future<bool> requestPermissionsIfNeeded() async {
    if (_permissionRequestInProgress) return arePermissionsGranted();

    try {
      _permissionRequestInProgress = true;
      await ensureInitialized();

      if (kIsWeb) return true;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidPlugin?.requestNotificationsPermission();
        if (granted != null) return granted;
        final status = await Permission.notification.request();
        return status.isGranted;
      }
      return true;
    } catch (e) {
      return false;
    } finally {
      _permissionRequestInProgress = false;
    }
  }

  Future<bool> arePermissionsGranted() async {
    if (kIsWeb) return true;
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> showTransactionNotification({
    required String reference,
    required double amount,
    required String type, // 'income' / 'expense' or 'CREDIT' / 'DEBIT'
    String? counterparty,
    String? bankName,
    String? categoryName,
    List<Map<String, String>> quickCategories = const [],
    bool ignoreEnabledCheck = false,
    bool recordHistory = true,
  }) async {
    try {
      await ensureInitialized();

      if (!ignoreEnabledCheck) {
        final enabled = await NotificationSettingsService.instance
            .isTransactionNotificationsEnabled();
        if (!enabled) return;
      }

      final isCredit = type.toUpperCase() == 'CREDIT' || type.toLowerCase() == 'income';
      final kind = isCredit ? 'Money In' : 'Money Out';
      final bankLabel = (bankName != null && bankName.trim().isNotEmpty)
          ? bankName.trim()
          : 'SW Budget';
      final title = '$bankLabel • $kind';

      final sign = isCredit ? '+' : '-';
      final formattedAmount =
          '${sign}ETB ${NumberFormat('#,##0.00').format(amount)}';

      final hasCounterparty = counterparty != null && counterparty.trim().isNotEmpty;
      final role = isCredit ? 'sender' : 'receiver';

      final String body;
      if (!hasCounterparty) {
        body = '$formattedAmount • Expand notification to add $role';
      } else if (categoryName != null && categoryName.trim().isNotEmpty) {
        body = '$formattedAmount • ${counterparty.trim()} • Categorized as ${categoryName.trim()}';
      } else {
        body = '$formattedAmount • ${counterparty.trim()} • Tap to categorize';
      }

      final actions = <AndroidNotificationAction>[];

      // Inline text reply to add missing counterparty
      if (!hasCounterparty) {
        actions.add(
          AndroidNotificationAction(
            '$_counterpartyActionPrefix${Uri.encodeComponent(reference)}',
            'add $role',
            allowGeneratedReplies: true,
            showsUserInterface: false,
            cancelNotification: false,
            inputs: <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(label: 'Enter $role name'),
            ],
          ),
        );
      }

      // Quick categorization action buttons
      final maxQuickActions = hasCounterparty ? 3 : 2;
      for (final cat in quickCategories.take(maxQuickActions)) {
        final catId = cat['id'] ?? '';
        final catName = cat['name'] ?? '';
        if (catId.isNotEmpty && catName.isNotEmpty) {
          actions.add(
            AndroidNotificationAction(
              'tx:${Uri.encodeComponent(reference)}|cat:$catId',
              catName,
              showsUserInterface: false,
            ),
          );
        }
      }

      final id = reference.hashCode & 0x7fffffff;
      final payload = 'tx:${Uri.encodeComponent(reference)}';

      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _transactionChannelId,
            'Transactions',
            channelDescription:
                'Notifications when a new transaction is detected',
            importance: Importance.high,
            priority: Priority.high,
            actions: actions,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );

      if (recordHistory) {
        await _recordHistory(
          channel: _transactionChannelId,
          title: title,
          body: body,
          transactionReference: reference,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('debug: Failed to show transaction notification: $e');
      }
    }
  }

  Future<void> dismissTransactionNotification(String reference) async {
    try {
      await ensureInitialized();
      await _plugin.cancel(reference.hashCode & 0x7fffffff);
    } catch (_) {}
  }

  Future<bool> showTestTransactionNotification() async {
    await showTransactionNotification(
      reference: 'test_tx_${DateTime.now().millisecondsSinceEpoch}',
      amount: 150.00,
      type: 'expense',
      counterparty: 'Cafe Tomoca',
      bankName: 'Telebirr',
      categoryName: 'Food & Drinks',
      ignoreEnabledCheck: true,
    );
    return true;
  }

  Future<bool> showFailedParseReviewNotification({
    required String reviewId,
    required String bankName,
    required String messageBody,
  }) async {
    try {
      await ensureInitialized();

      final enabled = await NotificationSettingsService.instance
          .isFailedParseReviewNotificationsEnabled();
      if (!enabled) return false;

      final preview = messageBody.length > 120
          ? '${messageBody.substring(0, 117)}...'
          : messageBody;

      final id = 200000 + (reviewId.hashCode & 0x7fffffff);

      await _plugin.show(
        id,
        '$bankName transaction review',
        'Was this a transaction?\n$preview',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _failedParseReviewChannelId,
            'Failed parse review',
            channelDescription: 'Prompts to confirm unparsed bank transactions',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(
              'Was this a transaction?\n$preview',
            ),
            actions: [
              AndroidNotificationAction(
                'fp|yes|$reviewId',
                'Yes',
                showsUserInterface: false,
              ),
              AndroidNotificationAction(
                'fp|no|$reviewId',
                'No',
                showsUserInterface: false,
              ),
            ],
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: 'fp:${Uri.encodeComponent(reviewId)}',
      );

      await _recordHistory(
        channel: _failedParseReviewChannelId,
        title: '$bankName transaction review',
        body: 'Was this a transaction?\n$preview',
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> showBudgetAlertNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await ensureInitialized();

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _budgetChannelId,
            'Budget Alerts',
            channelDescription: 'Notifications for budget warnings and alerts',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );

      await _recordHistory(channel: _budgetChannelId, title: title, body: body);
    } catch (_) {}
  }

  Future<bool> showDailySpendingNotification({
    required double amount,
    int id = dailySpendingNotificationId,
    bool ignoreEnabledCheck = false,
  }) async {
    return _showSpendingSummaryNotification(
      title: "Today's spending",
      body: "You've spent ${NumberFormat('#,##0.00').format(amount)} ETB today.",
      id: id,
      ignoreEnabledCheck: ignoreEnabledCheck,
      isEnabled: NotificationSettingsService.instance.isDailySummaryEnabled,
    );
  }

  Future<bool> showDailySpendingTestNotification({required double amount}) async {
    return showDailySpendingNotification(
      amount: amount,
      id: dailySpendingTestNotificationId,
      ignoreEnabledCheck: true,
    );
  }

  Future<bool> showWeeklySpendingNotification({
    required double amount,
    int id = weeklySpendingNotificationId,
    bool ignoreEnabledCheck = false,
  }) async {
    return _showSpendingSummaryNotification(
      title: "This week's spending",
      body: "You've spent ${NumberFormat('#,##0.00').format(amount)} ETB this week.",
      id: id,
      ignoreEnabledCheck: ignoreEnabledCheck,
      isEnabled: NotificationSettingsService.instance.isWeeklySummaryEnabled,
    );
  }

  Future<bool> showWeeklySpendingTestNotification({required double amount}) async {
    return showWeeklySpendingNotification(
      amount: amount,
      id: weeklySpendingTestNotificationId,
      ignoreEnabledCheck: true,
    );
  }

  Future<bool> showMonthlySpendingNotification({
    required double amount,
    int id = monthlySpendingNotificationId,
    bool ignoreEnabledCheck = false,
  }) async {
    return _showSpendingSummaryNotification(
      title: "This month's spending",
      body: "You've spent ${NumberFormat('#,##0.00').format(amount)} ETB this month.",
      id: id,
      ignoreEnabledCheck: ignoreEnabledCheck,
      isEnabled: NotificationSettingsService.instance.isMonthlySummaryEnabled,
    );
  }

  Future<bool> showMonthlySpendingTestNotification({required double amount}) async {
    return showMonthlySpendingNotification(
      amount: amount,
      id: monthlySpendingTestNotificationId,
      ignoreEnabledCheck: true,
    );
  }

  Future<bool> _showSpendingSummaryNotification({
    required String title,
    required String body,
    required int id,
    required Future<bool> Function() isEnabled,
    bool ignoreEnabledCheck = false,
  }) async {
    try {
      await ensureInitialized();

      if (!ignoreEnabledCheck) {
        final enabled = await isEnabled();
        if (!enabled) return false;
      }

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _spendingSummaryChannelId,
            'Spending summaries',
            channelDescription: 'Daily, weekly, and monthly spending summaries',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );

      await _recordHistory(
        channel: _spendingSummaryChannelId,
        title: title,
        body: body,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<NotificationHistoryEntry>> getNotificationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawEntries = prefs.getStringList(_historyPrefsKey) ?? <String>[];
      final entries = <NotificationHistoryEntry>[];
      for (final raw in rawEntries) {
        try {
          final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
          entries.add(NotificationHistoryEntry.fromJson(jsonMap));
        } catch (_) {}
      }
      return entries;
    } catch (_) {
      return <NotificationHistoryEntry>[];
    }
  }

  Future<void> clearNotificationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyPrefsKey);
  }

  Future<void> _recordHistory({
    required String channel,
    required String title,
    required String body,
    String? transactionReference,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawEntries = prefs.getStringList(_historyPrefsKey) ?? <String>[];
      final entry = NotificationHistoryEntry(
        channel: channel,
        title: title,
        body: body,
        sentAt: DateTime.now(),
        transactionReference: transactionReference,
      );
      rawEntries.insert(0, jsonEncode(entry.toJson()));
      if (rawEntries.length > _maxHistoryEntries) {
        rawEntries.removeRange(_maxHistoryEntries, rawEntries.length);
      }
      await prefs.setStringList(_historyPrefsKey, rawEntries);
    } catch (_) {}
  }
}

class NotificationHistoryEntry {
  final String channel;
  final String title;
  final String body;
  final DateTime sentAt;
  final String? transactionReference;

  const NotificationHistoryEntry({
    required this.channel,
    required this.title,
    required this.body,
    required this.sentAt,
    this.transactionReference,
  });

  factory NotificationHistoryEntry.fromJson(Map<String, dynamic> json) {
    return NotificationHistoryEntry(
      channel: json['channel'] as String? ?? 'general',
      title: json['title'] as String? ?? 'Notification',
      body: json['body'] as String? ?? '',
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
      transactionReference: json['transactionReference'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'channel': channel,
      'title': title,
      'body': body,
      'sentAt': sentAt.toIso8601String(),
      if (transactionReference != null)
        'transactionReference': transactionReference,
    };
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (response.notificationResponseType !=
      NotificationResponseType.selectedNotificationAction) {
    return;
  }

  final actionId = response.actionId;
  if (actionId == null) return;

  if (actionId.startsWith(NotificationService._counterpartyActionPrefix)) {
    NotificationService.instance._handleCounterpartyInputAction(
      actionId,
      response.input,
      response.id,
    );
  } else if (actionId.contains('|cat:')) {
    NotificationService.instance._handleQuickCategorizeAction(
      actionId,
      response.id,
    );
  } else if (actionId.startsWith('fp|')) {
    NotificationService.instance._handleFailedParseReviewAction(
      actionId,
      response.id,
    );
  }
}
