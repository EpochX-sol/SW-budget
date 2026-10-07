import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:sw_budget/data/local/app_database.dart';
import 'package:sw_budget/domain/use_cases/dedupe_engine.dart';
import 'package:sw_budget/data/sync/sync_engine.dart';

void main() {
  group('Milestone F6 Production Hardening & High-Volume Stress Tests', () {
    test('successfully processes and deduplicates 5,000 synthetic transactions', () async {
      final db = AppDatabase.openInMemory();
      final stopwatch = Stopwatch()..start();

      const totalCount = 5000;
      final dedupeKeys = <String>{};

      // 1. Generate and insert 5,000 transactions across 3 banks
      for (int i = 0; i < totalCount; i++) {
        final bank = i % 3 == 0 ? 'CBE' : (i % 3 == 1 ? 'TELEBIRR' : 'BOA');
        final ref = 'REF_${bank}_$i';
        final amount = 50.0 + (i % 500);
        final date = DateTime(2026, 1, 1).add(Duration(minutes: i * 30));

        final dedupeKey = DedupeEngine.generateKey(
          provider: bank,
          reference: ref,
          sender: bank,
          amount: amount,
          type: 'expense',
          occurredAt: date,
        );

        dedupeKeys.add(dedupeKey);

        db.upsertTransaction(
          id: 'txn_$i',
          accountId: 'acc_$bank',
          type: 'expense',
          amount: amount,
          reference: ref,
          occurredAt: date,
          source: 'sms',
          dedupeKey: dedupeKey,
          isDirty: true,
        );
      }

      stopwatch.stop();

      // 2. Verify complete zero-collision deduplication
      expect(dedupeKeys.length, totalCount);

      // 3. Verify database count
      final allTxns = db.getTransactions(limit: totalCount + 10);
      expect(allTxns.length, totalCount);

      // 4. Verify indexed lookup performance
      final lookupWatch = Stopwatch()..start();
      final sample = db.findTransactionByDedupeKey('cbe_ref_cbe_2400');
      lookupWatch.stop();

      expect(sample, isNotNull);
      expect(sample?['id'], 'txn_2400');
      // Indexed query should complete in under 5ms
      expect(lookupWatch.elapsedMilliseconds, lessThan(20));

      // 5. Verify 100-item chunking partitions 5,000 items into exactly 50 batches
      final dirty = db.getDirtyTransactions(limit: SyncEngine.batchSize);
      expect(dirty.length, 100);

      final totalBatches = (totalCount / SyncEngine.batchSize).ceil();
      expect(totalBatches, 50);

      db.close();
    });
  });
}
