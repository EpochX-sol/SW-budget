import 'dart:math';
import 'package:uuid/uuid.dart';
import '../local/app_database.dart';
import '../remote/api_client.dart';
import '../remote/api_exception.dart';

enum SyncStatus { idle, syncing, synced, error }

class SyncResult {
  final bool isSuccess;
  final int pushedCount;
  final int pulledCount;
  final int currentCursor;
  final String? errorMessage;

  const SyncResult({
    required this.isSuccess,
    this.pushedCount = 0,
    this.pulledCount = 0,
    this.currentCursor = 0,
    this.errorMessage,
  });
}

/// Offline-first synchronization engine using monotonic sequence cursors (change_seq)
/// with chunked 100-item batching and idempotent upload retries.
class SyncEngine {
  final AppDatabase _database;
  final ApiClient _apiClient;

  static const int batchSize = 100;

  SyncEngine({
    required AppDatabase database,
    required ApiClient apiClient,
  })  : _database = database,
        _apiClient = apiClient;

  /// Runs complete bidirectional sync: Push local changes -> Pull remote changes
  Future<SyncResult> syncAll() async {
    _database.updateSyncCursor(
      lastSyncSeq: _database.getLastSyncCursor(),
      status: 'syncing',
    );

    try {
      // 1. Push local dirty transactions
      final pushedCount = await pushChanges();

      // 2. Pull remote changes since cursor
      final pullResult = await pullChanges();

      final currentCursor = _database.getLastSyncCursor();

      _database.updateSyncCursor(
        lastSyncSeq: currentCursor,
        status: 'synced',
      );

      return SyncResult(
        isSuccess: true,
        pushedCount: pushedCount,
        pulledCount: pullResult,
        currentCursor: currentCursor,
      );
    } on ApiException catch (e) {
      _database.updateSyncCursor(
        lastSyncSeq: _database.getLastSyncCursor(),
        status: 'error',
      );
      return SyncResult(
        isSuccess: false,
        errorMessage: e.detail,
        currentCursor: _database.getLastSyncCursor(),
      );
    } catch (e) {
      _database.updateSyncCursor(
        lastSyncSeq: _database.getLastSyncCursor(),
        status: 'error',
      );
      return SyncResult(
        isSuccess: false,
        errorMessage: e.toString(),
        currentCursor: _database.getLastSyncCursor(),
      );
    }
  }

  /// Pushes dirty local records in 100-item batches
  Future<int> pushChanges() async {
    int totalPushed = 0;

    // 1. Push dirty Accounts first (guarantees foreign key exists in PostgreSQL)
    final dirtyAccounts = _database.getDirtyAccounts(limit: batchSize);
    if (dirtyAccounts.isNotEmpty) {
      final accountChanges = dirtyAccounts.map((row) {
        return {
          'entity': 'account',
          'op': row['deleted_at'] != null ? 'delete' : 'upsert',
          'id': row['id'],
          'client_updated_at': row['updated_at'] ?? row['created_at'],
          'data': {
            'provider': row['provider'],
            'name': row['name'],
            'account_mask': row['account_mask'],
            'last_known_balance': row['last_known_balance'],
            'is_savings': row['is_savings'] == 1,
          },
        };
      }).toList();

      final response = await _apiClient.pushSync(
        batchIndex: 1,
        totalBatches: 1,
        changes: accountChanges,
        idempotencyKey: const Uuid().v4(),
      );

      final acceptedIds = (response['accepted_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final newCursor = (response['new_cursor'] as num?)?.toInt() ?? 0;
      _database.markAccountsSynced(acceptedIds, newCursor);
      totalPushed += acceptedIds.length;
    }

    // 2. Push dirty Limits
    final dirtyLimits = _database.getDirtyLimits(limit: batchSize);
    if (dirtyLimits.isNotEmpty) {
      final limitChanges = dirtyLimits.map((row) {
        return {
          'entity': 'limit',
          'op': row['deleted_at'] != null ? 'delete' : 'upsert',
          'id': row['id'],
          'client_updated_at': row['updated_at'] ?? row['created_at'],
          'data': {
            'scope_type': row['scope_type'],
            'scope_id': row['scope_id'],
            'period_type': row['period_type'],
            'amount': row['amount'],
            'mode': row['mode'],
            'rollover': row['rollover'] == 1,
          },
        };
      }).toList();

      final response = await _apiClient.pushSync(
        batchIndex: 1,
        totalBatches: 1,
        changes: limitChanges,
        idempotencyKey: const Uuid().v4(),
      );

      final acceptedIds = (response['accepted_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final newCursor = (response['new_cursor'] as num?)?.toInt() ?? 0;
      _database.markLimitsSynced(acceptedIds, newCursor);
      totalPushed += acceptedIds.length;
    }

    // 3. Push dirty Saving Plans
    final dirtyPlans = _database.getDirtySavingPlans(limit: batchSize);
    if (dirtyPlans.isNotEmpty) {
      final planChanges = dirtyPlans.map((row) {
        return {
          'entity': 'saving_plan',
          'op': row['deleted_at'] != null ? 'delete' : 'upsert',
          'id': row['id'],
          'client_updated_at': row['updated_at'] ?? row['created_at'],
          'data': {
            'name': row['name'],
            'target_amount': row['target_amount'],
            'current_amount': row['current_amount'],
            'target_date': row['target_date'],
            'status': row['status'],
          },
        };
      }).toList();

      final response = await _apiClient.pushSync(
        batchIndex: 1,
        totalBatches: 1,
        changes: planChanges,
        idempotencyKey: const Uuid().v4(),
      );

      final acceptedIds = (response['accepted_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final newCursor = (response['new_cursor'] as num?)?.toInt() ?? 0;
      _database.markSavingPlansSynced(acceptedIds, newCursor);
      totalPushed += acceptedIds.length;
    }

    // 4. Push dirty Transactions with progressive batchIndex
    int currentBatchIndex = 1;
    while (true) {
      final dirtyTransactions = _database.getDirtyTransactions(limit: batchSize);
      if (dirtyTransactions.isEmpty) {
        break;
      }

      final changes = dirtyTransactions.map((row) {
        return {
          'entity': 'transaction',
          'op': row['deleted_at'] != null ? 'delete' : 'upsert',
          'id': row['id'],
          'client_updated_at': row['updated_at'] ?? row['created_at'],
          'data': {
            'account_id': row['account_id'],
            'category_id': row['category_id'],
            'type': row['type'],
            'amount': row['amount'],
            'balance_after': row['balance_after'],
            'counterparty': row['counterparty'],
            'reference': row['reference'],
            'occurred_at': row['occurred_at'],
            'source': row['source'],
            'parse_confidence': row['parse_confidence'],
            'dedupe_key': row['dedupe_key'],
          },
        };
      }).toList();

      final idempotencyKey = const Uuid().v4();

      final response = await _apiClient.pushSync(
        batchIndex: currentBatchIndex,
        totalBatches: max(currentBatchIndex, 1),
        changes: changes,
        idempotencyKey: idempotencyKey,
      );

      final acceptedIds = (response['accepted_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final newCursor = (response['new_cursor'] as num?)?.toInt() ?? 0;

      _database.markTransactionsSynced(acceptedIds, newCursor);
      totalPushed += acceptedIds.length;
      currentBatchIndex++;

      final currentCursor = _database.getLastSyncCursor();
      if (newCursor > currentCursor) {
        _database.updateSyncCursor(lastSyncSeq: newCursor);
      }

      if (dirtyTransactions.length < batchSize) {
        break;
      }
    }

    return totalPushed;
  }

  /// Pulls remote changes monotonically in 100-item pages
  Future<int> pullChanges() async {
    int totalPulled = 0;
    bool hasMore = true;

    while (hasMore) {
      final cursor = _database.getLastSyncCursor();
      final response = await _apiClient.pullSync(
        cursor: cursor,
        limit: batchSize,
      );

      final newCursor = (response['cursor'] as num?)?.toInt() ?? cursor;
      hasMore = response['has_more'] as bool? ?? false;
      final changes = response['changes'] as List<dynamic>? ?? [];

      for (final change in changes) {
        if (change is! Map<String, dynamic>) continue;
        final entityType = change['entity'] as String? ?? '';
        final op = change['op'] as String? ?? 'upsert';
        final entityId = change['id'] as String? ?? '';
        final changeSeq = (change['change_seq'] as num?)?.toInt() ?? newCursor;
        final data = change['data'] as Map<String, dynamic>? ?? {};

        if (entityType == 'transaction') {
          if (op == 'delete') {
            _database.deleteTransaction(entityId);
          } else {
            _database.upsertTransaction(
              id: entityId,
              accountId: data['account_id'] as String? ?? '',
              categoryId: data['category_id'] as String?,
              type: data['type'] as String? ?? 'expense',
              amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
              balanceAfter: (data['balance_after'] as num?)?.toDouble(),
              counterparty: data['counterparty'] as String?,
              reference: data['reference'] as String?,
              occurredAt: data['occurred_at'] != null
                  ? DateTime.parse(data['occurred_at'] as String)
                  : DateTime.now(),
              source: data['source'] as String? ?? 'server',
              parseConfidence: (data['parse_confidence'] as num?)?.toDouble(),
              dedupeKey: data['dedupe_key'] as String?,
              changeSeq: changeSeq,
              isDirty: false, // Pulled from server, not dirty
            );
          }
        } else if (entityType == 'account') {
          if (op == 'delete') {
            _database.deleteAccount(entityId);
          } else {
            _database.upsertAccount(
              id: entityId,
              provider: data['provider'] as String? ?? 'CBE',
              name: data['name'] as String? ?? 'Account',
              accountMask: data['account_mask'] as String?,
              lastKnownBalance: (data['last_known_balance'] as num?)?.toDouble(),
              isSavings: data['is_savings'] == true || data['is_savings'] == 1,
              changeSeq: changeSeq,
            );
          }
        } else if (entityType == 'category') {
          _database.upsertCategory(
            id: entityId,
            name: data['name'] as String? ?? 'Category',
            icon: data['icon'] as String? ?? 'category',
            colorHex: data['color_hex'] as String? ?? '#10B981',
            isSystem: data['is_system'] == true || data['is_system'] == 1,
            changeSeq: changeSeq,
          );
        } else if (entityType == 'limit') {
          _database.upsertLimit(
            id: entityId,
            scopeType: data['scope_type'] as String? ?? 'category',
            scopeId: data['scope_id'] as String?,
            periodType: data['period_type'] as String? ?? 'monthly',
            amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
            mode: data['mode'] as String? ?? 'soft',
            rollover: data['rollover'] == true || data['rollover'] == 1,
            changeSeq: changeSeq,
          );
        } else if (entityType == 'saving_plan') {
          _database.upsertSavingPlan(
            id: entityId,
            name: data['name'] as String? ?? 'Plan',
            targetAmount: (data['target_amount'] as num?)?.toDouble() ?? 0.0,
            currentAmount: (data['current_amount'] as num?)?.toDouble() ?? 0.0,
            targetDate: data['target_date'] != null
                ? DateTime.parse(data['target_date'] as String)
                : DateTime.now().add(const Duration(days: 30)),
            status: data['status'] as String? ?? 'active',
            changeSeq: changeSeq,
          );
        }
        totalPulled++;
      }

      // Persist cursor progression
      _database.updateSyncCursor(lastSyncSeq: newCursor);
    }

    return totalPulled;
  }
}
