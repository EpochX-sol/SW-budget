import { Worker, Job } from 'bullmq';
import { redisConnection } from '../redis.js';
import { spendingPlanService } from '../../modules/finance/spending-plan/spending-plan.service.js';
import { planNotificationsQueue } from '../queues.js';

export interface RebuildSnapshotJobPayload {
  planId: string;
  userId: string;
  trigger: 'transaction_created' | 'transaction_updated' | 'reimbursement_linked' | 'midnight_tick';
}

export async function processSnapshotRebuildJob(data: RebuildSnapshotJobPayload) {
  const { planId, userId, trigger } = data;

  const snapshot = await spendingPlanService.recomputeSnapshot(planId, userId);

  // Check alert triggers
  if (snapshot.today.allowance > 0) {
    const spent = snapshot.today.spent;
    const allowance = snapshot.today.allowance;

    if (spent >= allowance * 0.8 && spent <= allowance) {
      // 80% threshold reached
      await planNotificationsQueue.add('dispatch_notification', {
        userId,
        planId,
        type: 'threshold_80',
        amount: spent,
        allowance,
      });
    } else if (spent > allowance) {
      // Allowance exceeded
      await planNotificationsQueue.add('dispatch_notification', {
        userId,
        planId,
        type: 'allowance_exceeded',
        amount: spent,
        allowance,
        variancePct: snapshot.today.varianceVsAllowancePct,
        tomorrowAllowance: snapshot.tomorrow?.allowance,
      });
    }
  }

  if (
    snapshot.pace.daysUntilBroke !== null &&
    snapshot.pace.daysUntilBroke <= 3 &&
    snapshot.totals.remaining > 0
  ) {
    await planNotificationsQueue.add('dispatch_notification', {
      userId,
      planId,
      type: 'burn_rate',
      daysUntilBroke: snapshot.pace.daysUntilBroke,
    });
  }

  return {
    planId,
    asOf: snapshot.asOf,
    status: snapshot.status,
    trigger,
  };
}

export const planSnapshotsWorker = new Worker(
  'plan-snapshots',
  async (job: Job<RebuildSnapshotJobPayload>) => {
    return processSnapshotRebuildJob(job.data);
  },
  {
    connection: redisConnection,
    concurrency: 5,
  }
);
