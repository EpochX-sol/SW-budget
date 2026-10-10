import { prisma } from '../../db/prisma.js';
import { notificationService } from '../../modules/notifications/notification.service.js';
import { financeTools } from '../../modules/ai/tools/finance-tools.js';

export class SchedulerWorker {
  /**
   * Executes a single scheduler tick cycle against user_schedules.
   */
  async runSchedulerCycle(testNow?: Date) {
    const now = testNow || new Date();

    // 1. Fetch all schedules ready to run
    const readySchedules = await prisma.userSchedule.findMany({
      where: {
        nextRunAt: { lte: now },
      },
      include: {
        user: true,
      },
      take: 100,
    });

    const processed = [];

    for (const sched of readySchedules) {
      const { userId, kind, user } = sched;

      try {
        if (kind === 'morning_allowance') {
          // Compute today's safe spending allowance
          const scenario = await financeTools.simulateScenario(userId, { amount: 0 });
          const safeDaily = scenario.safe_daily_budget_after || 500;

          await notificationService.dispatchNotification({
            userId,
            type: 'morning_allowance',
            channel: 'push',
            title: '☀️ Good Morning - Daily Budget Allowance',
            body: `Your safe spending allowance for today is ETB ${safeDaily.toLocaleString()}. Keep on track!`,
            amount: safeDaily,
            dedupeKey: `morning:${userId}:${now.toISOString().slice(0, 10)}`,
          });
        } else if (kind === 'evening_summary') {
          // Compute today's total spending
          const summary = await financeTools.getSpendingSummary(userId, { period: 'today' });

          await notificationService.dispatchNotification({
            userId,
            type: 'evening_summary',
            channel: 'push',
            title: '🌙 Daily Spending Summary',
            body: `You spent ETB ${summary.total_expense.toLocaleString()} across ${summary.transaction_count} transactions today.`,
            amount: summary.total_expense,
            dedupeKey: `evening:${userId}:${now.toISOString().slice(0, 10)}`,
          });
        }

        // Advance next_run_at to next day (24 hours later)
        const nextRun = new Date(now.getTime() + 24 * 60 * 60 * 1000);
        await prisma.userSchedule.update({
          where: {
            userId_kind: { userId, kind },
          },
          data: {
            nextRunAt: nextRun,
          },
        });

        processed.push({ userId, kind, status: 'completed' });
      } catch (err: any) {
        console.error(`Error processing schedule for user ${userId} (${kind}):`, err);
        processed.push({ userId, kind, status: 'error', error: err.message });
      }
    }

    return {
      executed_at: now.toISOString(),
      tasks_processed: processed.length,
      tasks: processed,
    };
  }

  /**
   * Executes Addis Ababa Midnight Tick (00:00 EAT / 21:00 UTC).
   * Advances Day d and recalculates snapshots for all active plans.
   */
  async runAddisMidnightTick() {
    const activePlans = await prisma.budgetPlan.findMany({
      where: { active: true, deletedAt: null },
    });

    const { spendingPlanService } = await import('../../modules/finance/spending-plan/spending-plan.service.js');
    const { planNotificationsQueue } = await import('../queues.js');

    const results = [];
    for (const plan of activePlans) {
      try {
        const snap = await spendingPlanService.recomputeSnapshot(plan.id, plan.userId);
        // Enqueue morning allowance notification
        await planNotificationsQueue.add('dispatch_notification', {
          userId: plan.userId,
          planId: plan.id,
          type: 'morning_allowance',
          allowance: snap.today.allowance,
        });
        results.push({ planId: plan.id, status: 'ok', dayIndex: snap.days.elapsed });
      } catch (err: any) {
        results.push({ planId: plan.id, status: 'error', error: err.message });
      }
    }

    return {
      plans_ticked: activePlans.length,
      results,
    };
  }
}

export const schedulerWorker = new SchedulerWorker();

