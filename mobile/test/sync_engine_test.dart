import 'package:flutter_test/flutter_test.dart';
import 'package:sw_budget/domain/use_cases/dedupe_engine.dart';
import 'package:sw_budget/data/sync/sync_engine.dart';

void main() {
  group('DedupeEngine Tests', () {
    test('generates canonical reference deduplication keys for CBE and Telebirr', () {
      final cbeKey = DedupeEngine.generateKey(
        provider: 'CBE',
        reference: 'FT2610ABCXYZ',
        sender: 'CBE',
        amount: 350.0,
        type: 'expense',
        occurredAt: DateTime(2026, 10, 7, 10, 30),
      );

      expect(cbeKey, 'cbe_ft2610abcxyz');

      final telebirrKey = DedupeEngine.generateKey(
        provider: 'TELEBIRR',
        reference: '1049281882',
        sender: 'Telebirr',
        amount: 50.0,
        type: 'expense',
        occurredAt: DateTime(2026, 10, 7, 11, 0),
      );

      expect(telebirrKey, 'telebirr_1049281882');
    });

    test('generates deterministic hash when transaction has no bank reference', () {
      final date = DateTime(2026, 10, 7, 14, 15);
      final key1 = DedupeEngine.generateKey(
        provider: 'TELEBIRR',
        reference: null,
        sender: 'Telebirr',
        amount: 120.0,
        type: 'expense',
        occurredAt: date,
        counterparty: 'Kaldis Coffee',
      );

      final key2 = DedupeEngine.generateKey(
        provider: 'TELEBIRR',
        reference: '',
        sender: 'Telebirr',
        amount: 120.0,
        type: 'expense',
        occurredAt: date,
        counterparty: 'Kaldis Coffee',
      );

      expect(key1, startsWith('telebirr_hash_'));
      expect(key1, equals(key2));
    });
  });

  group('SyncEngine Chunking Logic Tests', () {
    test('computes correct batch sizes for 250 items with 100-item limit', () {
      const totalItems = 250;
      final batches = <int>[];

      int remaining = totalItems;
      while (remaining > 0) {
        final currentBatchSize = remaining > SyncEngine.batchSize ? SyncEngine.batchSize : remaining;
        batches.add(currentBatchSize);
        remaining -= currentBatchSize;
      }

      expect(batches.length, 3);
      expect(batches[0], 100);
      expect(batches[1], 100);
      expect(batches[2], 50);
    });
  });
}
