import { syncRepository, SyncRepository } from './sync.repository.js';
import { SyncPushInput, SyncPullInput } from './sync.schemas.js';

export class SyncService {
  constructor(private repo: SyncRepository = syncRepository) {}

  async pushChanges(userId: string, input: SyncPushInput, _idempotencyKey?: string) {
    // Apply batch atomically with row-level locked sequence counter directly in PostgreSQL
    const { acceptedIds, newCursor } = await this.repo.applyPushBatch(
      userId,
      input.changes
    );

    return {
      accepted_ids: acceptedIds,
      conflicts: [],
      new_cursor: Number(newCursor),
    };
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
      changes: changes.map((c: any) => ({
        id: c.id,
        entity: c.entity,
        op: c.op,
        data: c.data,
        timestamp: c.timestamp ? new Date(c.timestamp).toISOString() : new Date().toISOString(),
      })),
    };
  }

  async getStatus(userId: string) {
    const seq = await this.repo.getUserSeq(userId);
    return {
      cursor: Number(seq),
      last_synced_at: new Date().toISOString(),
    };
  }
}

export const syncService = new SyncService();
