import { syncRepository, SyncRepository } from './sync.repository.js';
import { SyncPushInput, SyncPullInput } from './sync.schemas.js';
import { safeRedisGet, safeRedisSetex } from '../../jobs/redis.js';
import { aggregatesQueue } from '../../jobs/queues.js';

export class SyncService {
  constructor(private repo: SyncRepository = syncRepository) {}

  async pushChanges(userId: string, input: SyncPushInput, idempotencyKey?: string) {
    // 1. Check idempotency in Redis if header provided (fail-safe and non-blocking)
    if (idempotencyKey) {
      const cacheKey = `idempotency:sync:${userId}:${idempotencyKey}`;
      try {
        const cached = await safeRedisGet(cacheKey, 1000);
        if (cached) {
          return JSON.parse(cached);
        }
      } catch {
        // Fallback: continue to DB if Redis is unreachable
      }
    }

    // 2. Apply batch atomically with row-level locked sequence counter
    const { acceptedIds, newCursor, aggregateUpdates } = await this.repo.applyPushBatch(
      userId,
      input.changes
    );

    // 3. Dispatch aggregate jobs to BullMQ queue (safe, non-blocking fallback if Redis offline)
    for (const update of aggregateUpdates) {
      try {
        await aggregatesQueue.add(
          'update-aggregate',
          {
            userId,
            day: update.day,
            categoryId: update.categoryId,
            accountId: update.accountId,
          },
          {
            jobId: `agg_${userId}_${update.day}_${update.categoryId}_${update.accountId}`,
            delay: 500, // Small debounce
          }
        );
      } catch {
        // Redis/BullMQ worker is optional in cloud/dev; aggregate updates proceed gracefully
      }
    }

    const result = {
      accepted_ids: acceptedIds,
      conflicts: [],
      new_cursor: Number(newCursor),
    };

    // 4. Cache idempotency result for 24 hours (fail-safe)
    if (idempotencyKey) {
      const cacheKey = `idempotency:sync:${userId}:${idempotencyKey}`;
      safeRedisSetex(cacheKey, 86400, JSON.stringify(result), 1000).catch(() => {});
    }

    return result;
  }

  async pullChanges(userId: string, input: SyncPullInput) {
    const cursor = BigInt(input.cursor);
    const { cursor: newCursor, hasMore, changes } = await this.repo.pullChanges(
      userId,
      cursor,
      input.limit
    );

    return {
      cursor: Number(newCursor),
      has_more: hasMore,
      changes,
    };
  }

  async getStatus(userId: string) {
    const currentSeq = await this.repo.getUserSeq(userId);
    return {
      current_seq: Number(currentSeq),
      pending_count: 0,
      status: 'synced',
    };
  }
}

export const syncService = new SyncService();
