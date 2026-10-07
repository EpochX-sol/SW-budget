import '../models/raw_financial_message.dart';

/// Abstract contract for incoming financial transaction sources
/// Allows swapping between Telephony SMS BroadcastReceiver and NotificationListenerService
abstract class TransactionSource {
  /// Continuous real-time stream of incoming messages
  Stream<RawFinancialMessage> get messageStream;

  /// Queries historical stored messages (e.g. scanning SMS inbox on initial setup)
  Future<List<RawFinancialMessage>> queryHistorical({
    required DateTime since,
    required List<String> whitelistSenders,
  });

  /// Dispose any active streams or listeners
  void dispose();
}
