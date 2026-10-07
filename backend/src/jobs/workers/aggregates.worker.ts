import { Worker, Job } from 'bullmq';
import { redisConnection } from '../redis.js';
import { prisma } from '../../db/prisma.js';

export interface AggregateJobData {
  userId: string;
  day: string; // YYYY-MM-DD
  categoryId: string;
  accountId: string;
}

export async function processAggregateJob(job: Job<AggregateJobData>) {
  const { userId, day, categoryId, accountId } = job.data;
  const targetDate = new Date(`${day}T00:00:00.000Z`);
  const nextDate = new Date(targetDate.getTime() + 24 * 60 * 60 * 1000);

  // Compute daily totals for this combination from the transactions table
  const txns = await prisma.transaction.findMany({
    where: {
      userId,
      accountId,
      categoryId,
      occurredAt: {
        gte: targetDate,
        lt: nextDate,
      },
      deletedAt: null,
      isInternalTransfer: false,
    },
  });

  let expense = 0;
  let income = 0;
  let fees = 0;

  for (const t of txns) {
    const amt = Number(t.amount);
    if (t.type === 'expense' || t.type === 'merchant_payment' || t.type === 'bill_payment') {
      expense += amt;
    } else if (t.type === 'income') {
      income += amt;
    } else if (t.type === 'fee') {
      fees += amt;
    }
  }

  await prisma.dailyCategoryTotal.upsert({
    where: {
      userId_day_categoryId_accountId: {
        userId,
        day: targetDate,
        categoryId,
        accountId,
      },
    },
    create: {
      userId,
      day: targetDate,
      categoryId,
      accountId,
      expense,
      income,
      fees,
      txnCount: txns.length,
    },
    update: {
      expense,
      income,
      fees,
      txnCount: txns.length,
    },
  });
}

export function createAggregatesWorker(): Worker<AggregateJobData> {
  return new Worker<AggregateJobData>(
    'aggregates',
    async (job) => {
      await processAggregateJob(job);
    },
    {
      connection: redisConnection,
      concurrency: 5,
    }
  );
}
