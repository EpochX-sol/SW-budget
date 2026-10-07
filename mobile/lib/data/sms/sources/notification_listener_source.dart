import 'dart:async';
import 'package:flutter/services.dart';
import '../models/raw_financial_message.dart';
import 'transaction_source.dart';

/// Ingestion source capturing financial push notifications via Android NotificationListenerService
class NotificationListenerSource implements TransactionSource {
  static const EventChannel _eventChannel = EventChannel('com.swbudget/notification_stream');

  final StreamController<RawFinancialMessage> _streamController =
      StreamController<RawFinancialMessage>.broadcast();

  StreamSubscription? _platformSubscription;

  // Recognized Ethiopian financial app package names
  static const Set<String> _whitelistedPackages = {
    'cn.tydic.ethiopay', // Telebirr
    'com.combanketh.cbe_mobile_banking', // CBE
    'et.com.abyssinia.mobile', // Bank of Abyssinia
  };

  NotificationListenerSource() {
    _initializePlatformListener();
  }

  void _initializePlatformListener() {
    try {
      _platformSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            final rawMap = Map<String, dynamic>.from(event);
            final packageName = rawMap['package']?.toString() ?? '';

            // Map package to friendly sender name
            String sender = 'NOTIFICATION';
            if (packageName.contains('ethiopay')) {
              sender = 'Telebirr';
            } else if (packageName.contains('cbe')) {
              sender = 'CBE';
            } else if (packageName.contains('abyssinia')) {
              sender = 'Bank of Abyssinia';
            }

            final title = rawMap['title']?.toString() ?? '';
            final text = rawMap['text']?.toString() ?? '';
            final fullBody = title.isNotEmpty ? '$title: $text' : text;

            final message = RawFinancialMessage(
              id: rawMap['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
              sender: sender,
              body: fullBody,
              receivedAt: rawMap['timestamp'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(rawMap['timestamp'] as int)
                  : DateTime.now(),
              source: 'notification',
              extraMetadata: rawMap,
            );
            _streamController.add(message);
          }
        },
        onError: (dynamic error) {
          // Native channel might not be attached
        },
      );
    } catch (_) {
      // Ignored if platform channel is unavailable in test harness
    }
  }

  @override
  Stream<RawFinancialMessage> get messageStream => _streamController.stream;

  @override
  Future<List<RawFinancialMessage>> queryHistorical({
    required DateTime since,
    required List<String> whitelistSenders,
  }) async {
    // NotificationListenerService in Android does not store historical notification database
    return [];
  }

  /// Inject simulated notification for testing and development
  void injectSimulatedMessage(RawFinancialMessage message) {
    _streamController.add(message);
  }

  @override
  void dispose() {
    _platformSubscription?.cancel();
    _streamController.close();
  }
}
