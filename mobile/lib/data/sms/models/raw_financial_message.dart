/// Standardized raw incoming financial message from SMS or Notification channels
class RawFinancialMessage {
  final String id;
  final String sender; // e.g. "CBE", "127", "Telebirr", "Bank of Abyssinia"
  final String body;
  final DateTime receivedAt;
  final String source; // 'sms' or 'notification'
  final Map<String, dynamic>? extraMetadata;

  const RawFinancialMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.source,
    this.extraMetadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender': sender,
      'body': body,
      'received_at': receivedAt.toIso8601String(),
      'source': source,
      'metadata': extraMetadata,
    };
  }

  factory RawFinancialMessage.fromMap(Map<String, dynamic> map) {
    return RawFinancialMessage(
      id: map['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      sender: map['sender'] as String? ?? 'UNKNOWN',
      body: map['body'] as String? ?? '',
      receivedAt: map['received_at'] != null
          ? DateTime.parse(map['received_at'] as String)
          : DateTime.now(),
      source: map['source'] as String? ?? 'sms',
      extraMetadata: map['metadata'] as Map<String, dynamic>?,
    );
  }
}
