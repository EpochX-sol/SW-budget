import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_provider.dart';
import '../../data/sms/ingestion_pipeline.dart';
import '../../data/sms/ingestion_provider.dart';
import '../../data/sms/sources/sms_transaction_source.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_provider.dart';
import 'device_health_service.dart';

/// Coordinates the 3-tier redundancy pipeline:
/// 1. Real-time: Native Kotlin BroadcastReceiver
/// 2. Scheduled: WorkManager periodic trigger (4 hours)
/// 3. Foreground catch-up: Automated scan for missed SMS whenever app resumes
class BackgroundSyncCoordinator {
  final AppDatabase _database;
  final IngestionPipeline _ingestionPipeline;
  final SmsTransactionSource _smsSource;
  final SyncEngine _syncEngine;
  final DeviceHealthService _deviceHealth;

  DateTime? _lastCatchUpTimestamp;

  BackgroundSyncCoordinator({
    required AppDatabase database,
    required IngestionPipeline ingestionPipeline,
    required SmsTransactionSource smsSource,
    required SyncEngine syncEngine,
    DeviceHealthService? deviceHealth,
  })  : _database = database,
        _ingestionPipeline = ingestionPipeline,
        _smsSource = smsSource,
        _syncEngine = syncEngine,
        _deviceHealth = deviceHealth ?? DeviceHealthService();

  /// Execute Phase 3 Foreground Catch-Up
  /// Scans telephony inbox for any bank SMS that arrived while the device was asleep
  Future<int> executeForegroundCatchUp() async {
    final now = DateTime.now();

    // Prevent hammering catch-up if app paused/resumed within 30 seconds
    if (_lastCatchUpTimestamp != null &&
        now.difference(_lastCatchUpTimestamp!).inSeconds < 30) {
      return 0;
    }
    _lastCatchUpTimestamp = now;

    // Scan messages received in the last 7 days or since last known transaction
    final since = now.subtract(const Duration(days: 7));
    final whitelistSenders = ['CBE', '127', 'Telebirr', 'BoA', 'Abyssinia'];

    int importedCount = 0;

    try {
      final historicalMessages = await _smsSource.queryHistorical(
        since: since,
        whitelistSenders: whitelistSenders,
      );

      if (historicalMessages.isEmpty) {
        return 0;
      }

      // If more than 50 messages, activate native foreground service to protect process
      if (historicalMessages.length > 50) {
        await _deviceHealth.startForegroundSync(totalCount: historicalMessages.length);
      }

      for (final msg in historicalMessages) {
        final processed = await _ingestionPipeline.processMessage(msg);
        if (processed != null) {
          importedCount++;
        }
      }

      // If new records were ingested, trigger offline sync push
      if (importedCount > 0) {
        await _syncEngine.pushChanges();
      }
    } catch (e) {
      debugPrint('Foreground catch-up notice: $e');
    } finally {
      await _deviceHealth.stopForegroundSync();
    }

    return importedCount;
  }
}

final backgroundSyncCoordinatorProvider = FutureProvider<BackgroundSyncCoordinator>((ref) async {
  final database = await ref.watch(databaseProvider.future);
  final ingestion = await ref.watch(ingestionPipelineProvider.future);
  final smsSource = ref.watch(smsSourceProvider);
  final syncEngine = await ref.watch(syncEngineProvider.future);
  final deviceHealth = ref.watch(deviceHealthServiceProvider);

  return BackgroundSyncCoordinator(
    database: database,
    ingestionPipeline: ingestion,
    smsSource: smsSource,
    syncEngine: syncEngine,
    deviceHealth: deviceHealth,
  );
});

