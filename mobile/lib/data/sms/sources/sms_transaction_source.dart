import 'dart:async';
import 'dart:ui';
import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../models/raw_financial_message.dart';
import 'transaction_source.dart';
import '../../parser/normalizer/bank_sender_matcher.dart';

/// Top-level background entrypoint required by Android OS for headless isolate
@pragma('vm:entry-point')
void onBackgroundSmsMessage(SmsMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    final address = message.address;
    final body = message.body;
    if (address == null || body == null) return;

    if (!BankSenderMatcher.isRelevantSender(address)) return;

    debugPrint('Headless background SMS received from $address');
  } catch (e) {
    debugPrint('Background SMS handler error: $e');
  }
}

/// Ingestion source capturing real-time bank SMS and querying inbox history via `another_telephony`.
class SmsTransactionSource implements TransactionSource {
  final Telephony _telephony = Telephony.instance;
  final StreamController<RawFinancialMessage> _streamController =
      StreamController<RawFinancialMessage>.broadcast();

  SmsTransactionSource() {
    _initializePlatformListener();
  }

  void _initializePlatformListener() {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        _telephony.listenIncomingSms(
          onNewMessage: (SmsMessage message) {
            final address = message.address ?? '';
            final body = message.body ?? '';
            if (address.isEmpty || body.isEmpty) return;

            final raw = RawFinancialMessage(
              id: message.id?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
              sender: address,
              body: body,
              receivedAt: message.date != null
                  ? DateTime.fromMillisecondsSinceEpoch(message.date!)
                  : DateTime.now(),
              source: 'sms',
            );
            _streamController.add(raw);
          },
          onBackgroundMessage: onBackgroundSmsMessage,
        );
      }
    } catch (_) {
      // Ignored if platform channel is unavailable in desktop or test environment
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
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        return [];
      }

      final List<SmsMessage> messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ID, SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.DATE).greaterThanOrEqualTo(since.millisecondsSinceEpoch.toString()),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.ASC)],
      );

      final results = <RawFinancialMessage>[];
      for (final m in messages) {
        final address = m.address ?? '';
        final body = m.body ?? '';
        if (address.isEmpty || body.isEmpty) continue;

        if (BankSenderMatcher.matchesWhitelist(address, whitelistSenders)) {
          results.add(
            RawFinancialMessage(
              id: m.id?.toString() ?? '',
              sender: address,
              body: body,
              receivedAt: m.date != null
                  ? DateTime.fromMillisecondsSinceEpoch(m.date!)
                  : DateTime.now(),
              source: 'sms',
            ),
          );
        }
      }

      return results;
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
    _streamController.close();
  }
}
