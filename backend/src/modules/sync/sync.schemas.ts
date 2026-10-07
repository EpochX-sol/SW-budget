import { z } from 'zod';

export const syncChangeItemSchema = z.object({
  entity: z.enum(['account', 'category', 'transaction', 'limit', 'saving_plan']),
  op: z.enum(['upsert', 'delete']),
  id: z.string().uuid(),
  client_updated_at: z.string(),
  data: z.record(z.any()),
});

export const syncPushSchema = z.object({
  device_id: z.string().uuid(),
  batch_index: z.number().int().default(1),
  total_batches: z.number().int().default(1),
  changes: z.array(syncChangeItemSchema).max(100, 'Batch size must not exceed 100 items'),
});

export const syncPullSchema = z.object({
  cursor: z.coerce.number().int().default(0),
  limit: z.coerce.number().int().min(1).max(200).default(100),
});

export type SyncChangeItem = z.infer<typeof syncChangeItemSchema>;
export type SyncPushInput = z.infer<typeof syncPushSchema>;
export type SyncPullInput = z.infer<typeof syncPullSchema>;
