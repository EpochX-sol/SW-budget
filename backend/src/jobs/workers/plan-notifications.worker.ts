import { Worker, Job } from 'bullmq';
import { redisConnection } from '../redis.js';
import { notificationService } from '../../modules/notifications/notification.service.js';
import { toAddisAbabaDateString } from '../../modules/finance/spending-plan/spending-plan.math.js';

export interface PlanNotificationJobPayload {
  userId: string;
  planId: string;
  type:
    | 'morning_allowance'
    | 'threshold_80'
    | 'allowance_exceeded'
    | 'evening_summary'
    | 'burn_rate'
    | 'weekly_report'
    | 'plan_ending_soon'
    | 'plan_finished';
  amount?: number;
  allowance?: number;
  tomorrowAllowance?: number;
  variancePct?: number;
  daysUntilBroke?: number;
  summaryText?: string;
}

export async function processPlanNotificationJob(data: PlanNotificationJobPayload) {
  const { userId, planId, type, amount, allowance, tomorrowAllowance, variancePct, daysUntilBroke } = data;
  const todayStr = toAddisAbabaDateString(new Date());
  const dedupeKey = `plan_alert:${type}:${userId}:${todayStr}`;

  let title = '';
  let body = '';

  switch (type) {
    case 'morning_allowance':
      title = '☀️ Morning Allowance';
      body = `Today's spending allowance: ${allowance?.toLocaleString() || '0'} ETB. Stay on track!`;
      break;
    case 'threshold_80':
      title = '⚠️ 80% Daily Limit Warning';
      body = `You have used 80% of today's limit (${amount?.toLocaleString()} ETB of ${allowance?.toLocaleString()} ETB).`;
      break;
    case 'allowance_exceeded':
      title = '🚨 Daily Allowance Exceeded';
      body = `You are ${variancePct ? Math.abs(Math.round(variancePct)) : 0}% over today's plan. Tomorrow's allowance adjusted to ${tomorrowAllowance?.toLocaleString() || '0'} ETB.`;
      break;
    case 'evening_summary':
      title = '🌙 Evening Spending Summary';
      body = `Today's total spend: ${amount?.toLocaleString() || '0'} ETB. Tomorrow's allowance: ${tomorrowAllowance?.toLocaleString() || '0'} ETB.`;
      break;
    case 'burn_rate':
      title = '🔥 High Burn-Rate Alert';
      body = `At your current spending pace, your budget will run out in ${daysUntilBroke || 2} days.`;
      break;
    case 'weekly_report':
      title = '📊 Weekly Budget Report';
      body = data.summaryText || 'Your weekly spending report is ready to review.';
      break;
    case 'plan_ending_soon':
      title = '⏳ Spending Plan Ending Soon';
      body = 'Only 2 days remaining in your spending plan. Check your remaining balance.';
      break;
    case 'plan_finished':
      title = '🏁 Spending Plan Completed';
      body = data.summaryText || 'Your spending plan period has ended. See your final outcome.';
      break;
  }

  // Dispatch via notificationService
  const notif = await notificationService.dispatchNotification({
    userId,
    type,
    channel: 'push',
    title,
    body,
    amount: amount || allowance || 0,
    dedupeKey,
  });

  return {
    notification_id: notif.notification?.id || null,
    dispatched: notif.dispatched,
    type,
    userId,
    planId,
  };
}

export const planNotificationsWorker = new Worker(
  'plan-notifications',
  async (job: Job<PlanNotificationJobPayload>) => {
    return processPlanNotificationJob(job.data);
  },
  {
    connection: redisConnection,
    concurrency: 5,
  }
);
