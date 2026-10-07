import { Worker, Job } from 'bullmq';
import { prisma } from '../../db/prisma.js';
import { redisConnection } from '../redis.js';
import { outboxQueue } from '../queues.js';

export class OutboxRelayWorker {
  /**
   * Polls unprocessed outbox events from PostgreSQL and publishes them to Redis BullMQ.
   */
  async relayPendingEvents(): Promise<number> {
    const pending = await prisma.outboxEvent.findMany({
      where: { processedAt: null },
      orderBy: { id: 'asc' },
      take: 50,
    });

    if (pending.length === 0) return 0;

    for (const evt of pending) {
      await outboxQueue.add(
        evt.eventType,
        {
          userId: evt.userId,
          payload: evt.payload,
        },
        {
          jobId: `outbox_${evt.id.toString()}`,
        }
      );

      await prisma.outboxEvent.update({
        where: { id: evt.id },
        data: { processedAt: new Date() },
      });
    }

    return pending.length;
  }
}

export function createOutboxWorker(): Worker {
  return new Worker(
    'outbox',
    async (job: Job) => {
      // Process outbox dispatch
      console.log(`[Outbox Worker] Dispatched event ${job.name} for user ${job.data.userId}`);
    },
    {
      connection: redisConnection,
      concurrency: 5,
    }
  );
}

export const outboxRelay = new OutboxRelayWorker();
