import { syncRepository, SyncRepository } from './sync.repository.js';
import { SyncPushInput, SyncPullInput } from './sync.schemas.js';
import { redisConnection } from '../../jobs/redis.js';
import { aggregatesQueue } from '../../jobs/queues.js';

export class SyncService {
  constructor(private repo: SyncRepository = syncRepository) {}

  async pushChanges(userId: string, input: SyncPushInput, idempotencyKey?: string) {
    // 1. Check idempotency in Redis if header provided
    if (idempotencyKey) {
      const cacheKey = `idempotency:sync:${userId}:${idempotencyKey}`;
      const cached = await redisConnection.get(cacheKey);
      if (cached) {
        return JSON.parse(cached);
      }
    }

    // 2. Apply batch atomically with row-level locked sequence counter
    const { acceptedIds, newCursor, aggregateUpdates } = await this.repo.applyPushBatch(
      userId,
      input.changes
    );

    // 3. Dispatch aggregate jobs to BullMQ queue
    for (const update of aggregateUpdates) {
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
    }

    const result = {
      accepted_ids: acceptedIds,
      conflicts: [],
      new_cursor: Number(newCursor),
    };

    // 4. Cache idempotency result for 24 hours
    if (idempotencyKey) {
      const cacheKey = `idempotency:sync:${userId}:${idempotencyKey}`;
      await redisConnection.setex(cacheKey, 86400, JSON.stringify(result));
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
