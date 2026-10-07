import 'dart:async';
import 'package:flutter/services.dart';
import '../models/raw_financial_message.dart';
import 'transaction_source.dart';

/// Ingestion source capturing financial SMS via Android Telephony BroadcastReceiver
class SmsTransactionSource implements TransactionSource {
  static const MethodChannel _methodChannel = MethodChannel('com.swbudget/sms');
  static const EventChannel _eventChannel = EventChannel('com.swbudget/sms_stream');

  final StreamController<RawFinancialMessage> _streamController =
      StreamController<RawFinancialMessage>.broadcast();

  StreamSubscription? _platformSubscription;

  SmsTransactionSource() {
    _initializePlatformListener();
  }

  void _initializePlatformListener() {
    try {
      _platformSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            final rawMap = Map<String, dynamic>.from(event);
            final message = RawFinancialMessage(
              id: rawMap['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
              sender: rawMap['sender']?.toString() ?? '',
              body: rawMap['body']?.toString() ?? '',
              receivedAt: rawMap['timestamp'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(rawMap['timestamp'] as int)
                  : DateTime.now(),
              source: 'sms',
              extraMetadata: rawMap,
            );
            _streamController.add(message);
          }
        },
        onError: (dynamic error) {
          // Native channel might not be attached in desktop/test environments
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
    try {
      final List<dynamic>? result = await _methodChannel.invokeMethod<List<dynamic>>(
        'queryInbox',
        {
          'sinceTimestamp': since.millisecondsSinceEpoch,
          'senders': whitelistSenders,
        },
      );

      if (result == null) return [];

      return result.map((dynamic item) {
        final map = Map<String, dynamic>.from(item as Map);
        return RawFinancialMessage(
          id: map['id']?.toString() ?? '',
          sender: map['sender']?.toString() ?? '',
          body: map['body']?.toString() ?? '',
          receivedAt: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
          source: 'sms',
        );
      }).toList();
    } on MissingPluginException catch (_) {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Inject simulated message for testing and development
  void injectSimulatedMessage(RawFinancialMessage message) {
    _streamController.add(message);
  }

  @override
  void dispose() {
    _platformSubscription?.cancel();
    _streamController.close();
  }
}
