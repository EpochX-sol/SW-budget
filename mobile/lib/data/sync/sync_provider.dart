import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local/database_provider.dart';
import '../remote/api_client_provider.dart';
import 'sync_engine.dart';

class SyncState {
  final SyncStatus status;
  final DateTime? lastSyncTime;
  final int currentCursor;
  final String? errorMessage;
  final int unsyncedCount;

  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSyncTime,
    this.currentCursor = 0,
    this.errorMessage,
    this.unsyncedCount = 0,
  });

  bool get isSyncing => status == SyncStatus.syncing;
  bool get isSynced => status == SyncStatus.synced;
  bool get hasError => status == SyncStatus.error;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncTime,
    int? currentCursor,
    String? errorMessage,
    int? unsyncedCount,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      currentCursor: currentCursor ?? this.currentCursor,
      errorMessage: errorMessage,
      unsyncedCount: unsyncedCount ?? this.unsyncedCount,
    );
  }
}

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;

  SyncNotifier(this._ref) : super(const SyncState());

  Future<void> triggerSync() async {
    if (state.isSyncing) return;

    state = state.copyWith(status: SyncStatus.syncing, errorMessage: null);

    try {
      final engine = await _ref.read(syncEngineProvider.future);
      final result = await engine.syncAll();

      if (result.isSuccess) {
        state = state.copyWith(
          status: SyncStatus.synced,
          lastSyncTime: DateTime.now(),
          currentCursor: result.currentCursor,
        );
      } else {
        state = state.copyWith(
          status: SyncStatus.error,
          errorMessage: result.errorMessage,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  final database = await ref.watch(databaseProvider.future);
  final apiClient = ref.watch(apiClientProvider);
  return SyncEngine(database: database, apiClient: apiClient);
});

final syncStateProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref);
});
