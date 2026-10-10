import '../../../data/parser/financial_parser.dart';

class ReparseResult {
  final int totalProcessed;
  final int repairedDirectionCount;
  final int duplicatesRemovedCount;
  final int updatedCount;

  const ReparseResult({
    required this.totalProcessed,
    required this.repairedDirectionCount,
    required this.duplicatesRemovedCount,
    required this.updatedCount,
  });

  Map<String, dynamic> toJson() => {
        'total_processed': totalProcessed,
        'repaired_directions': repairedDirectionCount,
        'duplicates_removed': duplicatesRemovedCount,
        'updated_count': updatedCount,
      };
}

class AccountReparseService {
  final FinancialParser parser;

  AccountReparseService({required this.parser});

  /// Reparses a collection of raw messages, identifying directional errors,
  /// missing fields, and duplicate entries.
  ReparseResult reparseMessages({
    required List<Map<String, dynamic>> rawRecords,
    bool repairDirections = true,
    bool deduplicate = true,
  }) {
    int repairedDirections = 0;
    int duplicatesRemoved = 0;
    int updatedCount = 0;

    final seenKeys = <String>{};

    for (final record in rawRecords) {
      final sender = record['sender']?.toString() ?? '';
      final body = record['body']?.toString() ?? '';
      final existingType = record['type']?.toString();
      final date = record['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(record['timestamp'] as int)
          : DateTime.now();

      final parsed = parser.parse(
        sender: sender,
        body: body,
        receivedAt: date,
      );

      if (parsed.isSuccess && parsed.transaction != null) {
        final txn = parsed.transaction!;

        // 1. Deduplication check
        if (deduplicate) {
          if (seenKeys.contains(txn.dedupeKey)) {
            duplicatesRemoved++;
            continue;
          }
          seenKeys.add(txn.dedupeKey);
        }

        // 2. Direction check
        if (repairDirections && existingType != null) {
          if (existingType.toLowerCase() != txn.type.toLowerCase()) {
            repairedDirections++;
          }
        }

        updatedCount++;
      }
    }

    return ReparseResult(
      totalProcessed: rawRecords.length,
      repairedDirectionCount: repairedDirections,
      duplicatesRemovedCount: duplicatesRemoved,
      updatedCount: updatedCount,
    );
  }
}
