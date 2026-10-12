import { prisma } from '../../../db/prisma.js';
import { Prisma } from '@prisma/client';
import {
  CreatePlanInput,
  UpdatePlanInput,
  SimulatePlanInput,
  CreateFixedExpenseInput,
  UpdateFixedExpenseInput,
} from './spending-plan.schemas.js';
import {
  computeSnapshot,
  partitionWeeks,
  simulateScenario,
  toAddisAbabaDateString,
  round2,
  PlanSnapshot,
} from './spending-plan.math.js';

export class SpendingPlanService {
  /**
   * Creates a new spending plan, enforcing non-overlapping active plan dates.
   */
  async createPlan(userId: string, input: CreatePlanInput) {
    const startDate = new Date(input.start_date);
    const endDate = new Date(input.end_date);

    if (startDate > endDate) {
      const err: any = new Error('start_date must be on or before end_date');
      err.statusCode = 400;
      throw err;
    }

    // Allocate change_seq
    const syncState = await prisma.userSyncState.upsert({
      where: { userId },
      create: { userId, seq: 1n },
      update: { seq: { increment: 1n } },
    });
    const changeSeq = syncState.seq;

    // Enforce single active plan: archive any existing active or paused plan
    await prisma.budgetPlan.updateMany({
      where: {
        userId,
        status: { in: ['active', 'paused'] },
        deletedAt: null,
      },
      data: {
        active: false,
        status: 'archived',
      },
    });

    const spendingLimit = input.spending_limit ?? input.total_amount ?? 8000;
    const allExpenses = [
      ...(input.fixed_expenses || []),
      ...(input.expected_expenses || []),
    ];

    const plan = await prisma.budgetPlan.create({
      data: {
        userId,
        name: input.name,
        totalAmount: new Prisma.Decimal(spendingLimit),
        periodType: input.period_type ?? 'monthly',
        startDate,
        endDate,
        monthlyStartDay: input.monthly_start_day ?? 1,
        rolloverMode: input.rollover_mode,
        reserveType: input.reserve_type ?? 'none',
        reserveValue: new Prisma.Decimal(input.reserve_value ?? 0),
        reservePercent: new Prisma.Decimal(input.reserve_percent ?? 0),
        savingGoal: new Prisma.Decimal(input.saving_goal ?? 0),
        minDailyFloor: new Prisma.Decimal(input.min_daily_floor ?? 0),
        dayWeights: input.day_weights ? (input.day_weights as any) : Prisma.JsonNull,
        watchedBankIds: input.watched_bank_ids ? (input.watched_bank_ids as any) : Prisma.JsonNull,
        countFees: input.count_fees ?? true,
        countWithdrawals: input.count_withdrawals ?? true,
        reactionMode: input.reaction_mode ?? 'adaptive',
        status: 'active',
        morningBriefEnabled: input.morning_brief_enabled ?? true,
        morningBriefTime: input.morning_brief_time ?? '07:30',
        dailyReportEnabled: input.daily_report_enabled ?? true,
        dailyReportTime: input.daily_report_time ?? '21:00',
        skipEmptyDays: input.skip_empty_days ?? false,
        alertThresholds: (input.alert_thresholds as any) ?? [50, 80, 100],
        reserveAlertEnabled: input.reserve_alert_enabled ?? true,
        active: true,
        changeSeq,
        fixedExpenses: allExpenses.length
          ? {
              create: allExpenses.map((fe: any) => ({
                title: fe.title || fe.name || 'Expected Expense',
                amount: new Prisma.Decimal(fe.amount),
                dueDate: fe.due_date ? new Date(fe.due_date) : null,
                linkedCategoryId: fe.linked_category_id || null,
                status: fe.status || (fe.paid ? 'paid' : 'expected'),
                paid: Boolean(fe.paid || fe.status === 'paid'),
                reminderEnabled: fe.reminder_enabled ?? true,
                changeSeq,
              })),
            }
          : undefined,
        categoryLimits: input.category_limits?.length
          ? {
              create: input.category_limits.map((cl) => ({
                category: cl.category,
                amount: new Prisma.Decimal(cl.amount),
                changeSeq,
              })),
            }
          : undefined,
      },
      include: {
        fixedExpenses: true,
        categoryLimits: true,
      },
    });

    // Compute initial snapshot
    const snapshot = await this.recomputeSnapshot(plan.id, userId);

    return {
      plan,
      snapshot,
    };
  }

  /**
   * Retrieves the currently active spending plan and its snapshot.
   */
  async getActivePlan(userId: string) {
    const plan = await prisma.budgetPlan.findFirst({
      where: {
        userId,
        active: true,
        deletedAt: null,
      },
      include: {
        fixedExpenses: { where: { deletedAt: null } },
        categoryLimits: { where: { deletedAt: null } },
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!plan) {
      return null;
    }

    const todayStr = toAddisAbabaDateString(new Date());
    const cachedSnapshot = await prisma.planSnapshot.findUnique({
      where: {
        planId_snapshotDate: {
          planId: plan.id,
          snapshotDate: new Date(todayStr),
        },
      },
    });

    let snapshot: PlanSnapshot;
    if (cachedSnapshot) {
      snapshot = cachedSnapshot.payload as any;
    } else {
      snapshot = await this.recomputeSnapshot(plan.id, userId);
    }

    return {
      plan,
      snapshot,
    };
  }

  /**
   * Retrieves a plan by ID.
   */
  async getPlanById(userId: string, planId: string) {
    const plan = await prisma.budgetPlan.findFirst({
      where: { id: planId, userId, deletedAt: null },
      include: {
        fixedExpenses: { where: { deletedAt: null } },
        categoryLimits: { where: { deletedAt: null } },
      },
    });

    if (!plan) {
      const err: any = new Error('Spending plan not found');
      err.statusCode = 404;
      throw err;
    }

    return plan;
  }

  /**
   * Updates plan configuration.
   */
  async updatePlan(userId: string, planId: string, input: UpdatePlanInput) {
    await this.getPlanById(userId, planId);

    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });

    const data: any = {
      changeSeq: syncState.seq,
    };
    if (input.name !== undefined) data.name = input.name;
    if (input.total_amount !== undefined) data.totalAmount = new Prisma.Decimal(input.total_amount);
    if (input.start_date !== undefined) data.startDate = new Date(input.start_date);
    if (input.end_date !== undefined) data.endDate = new Date(input.end_date);
    if (input.rollover_mode !== undefined) data.rolloverMode = input.rollover_mode;
    if (input.reserve_percent !== undefined) data.reservePercent = new Prisma.Decimal(input.reserve_percent);
    if (input.saving_goal !== undefined) data.savingGoal = new Prisma.Decimal(input.saving_goal);
    if (input.min_daily_floor !== undefined) data.minDailyFloor = new Prisma.Decimal(input.min_daily_floor);
    if (input.day_weights !== undefined) data.dayWeights = input.day_weights ? (input.day_weights as any) : Prisma.JsonNull;
    if (input.active !== undefined) data.active = input.active;

    const updated = await prisma.budgetPlan.update({
      where: { id: planId },
      data,
      include: {
        fixedExpenses: { where: { deletedAt: null } },
        categoryLimits: { where: { deletedAt: null } },
      },
    });

    const snapshot = await this.recomputeSnapshot(planId, userId);

    return {
      plan: updated,
      snapshot,
    };
  }

  /**
   * Soft deletes a plan.
   */
  async deletePlan(userId: string, planId: string) {
    await this.getPlanById(userId, planId);

    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });

    await prisma.budgetPlan.update({
      where: { id: planId },
      data: {
        deletedAt: new Date(),
        active: false,
        changeSeq: syncState.seq,
      },
    });

    return { success: true };
  }

  /**
   * Pauses an active plan.
   */
  async pausePlan(userId: string, planId: string) {
    await this.getPlanById(userId, planId);
    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });
    const plan = await prisma.budgetPlan.update({
      where: { id: planId },
      data: {
        status: 'paused',
        pausedAt: new Date(),
        changeSeq: syncState.seq,
      },
    });
    return { plan };
  }

  /**
   * Resumes a paused plan.
   */
  async resumePlan(userId: string, planId: string) {
    const existing: any = await this.getPlanById(userId, planId);
    let extraDays = 0;
    if (existing.pausedAt) {
      extraDays = Math.max(0, Math.floor((Date.now() - new Date(existing.pausedAt).getTime()) / (1000 * 60 * 60 * 24)));
    }
    const totalPausedDays = (existing.pausedDaysCount || 0) + extraDays;

    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });
    const plan = await prisma.budgetPlan.update({
      where: { id: planId },
      data: {
        status: 'active',
        pausedAt: null,
        pausedDaysCount: totalPausedDays,
        changeSeq: syncState.seq,
      },
    });
    const snapshot = await this.recomputeSnapshot(planId, userId);
    return { plan, snapshot };
  }

  /**
   * Adds an expected expense (fixed commitment) to an existing plan.
   */
  async addFixedExpense(userId: string, planId: string, input: CreateFixedExpenseInput) {
    await this.getPlanById(userId, planId);

    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });

    const fe = await prisma.fixedExpense.create({
      data: {
        planId,
        title: input.title || input.name || 'Expected Expense',
        amount: new Prisma.Decimal(input.amount),
        dueDate: input.due_date ? new Date(input.due_date) : null,
        linkedCategoryId: input.linked_category_id || null,
        status: input.status || (input.paid ? 'paid' : 'expected'),
        paid: input.paid || input.status === 'paid',
        reminderEnabled: input.reminder_enabled ?? true,
        changeSeq: syncState.seq,
      },
    });

    const snapshot = await this.recomputeSnapshot(planId, userId);

    return {
      fixedExpense: fe,
      snapshot,
    };
  }

  /**
   * Updates an existing expected expense.
   */
  async updateFixedExpense(userId: string, planId: string, expenseId: string, input: UpdateFixedExpenseInput) {
    await this.getPlanById(userId, planId);
    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });

    const data: any = { changeSeq: syncState.seq };
    if (input.title || input.name) data.title = input.title || input.name;
    if (input.amount !== undefined) data.amount = new Prisma.Decimal(input.amount);
    if (input.due_date !== undefined) data.dueDate = input.due_date ? new Date(input.due_date) : null;
    if (input.linked_category_id !== undefined) data.linkedCategoryId = input.linked_category_id;
    if (input.reminder_enabled !== undefined) data.reminderEnabled = input.reminder_enabled;
    if (input.status !== undefined) {
      data.status = input.status;
      data.paid = input.status === 'paid';
    }
    if (input.paid !== undefined) {
      data.paid = input.paid;
      data.status = input.paid ? 'paid' : 'expected';
    }

    const fe = await prisma.fixedExpense.update({
      where: { id: expenseId },
      data,
    });
    const snapshot = await this.recomputeSnapshot(planId, userId);
    return { fixedExpense: fe, snapshot };
  }

  /**
   * Deletes an expected expense.
   */
  async deleteFixedExpense(userId: string, planId: string, expenseId: string) {
    await this.getPlanById(userId, planId);
    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });
    await prisma.fixedExpense.update({
      where: { id: expenseId },
      data: {
        deletedAt: new Date(),
        changeSeq: syncState.seq,
      },
    });
    const snapshot = await this.recomputeSnapshot(planId, userId);
    return { success: true, snapshot };
  }

  /**
   * Toggles paid status on an expected expense.
   */
  async markFixedExpensePaid(userId: string, planId: string, expenseId: string, paid: boolean, paidTxnId?: string) {
    await this.getPlanById(userId, planId);
    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });
    const fe = await prisma.fixedExpense.update({
      where: { id: expenseId },
      data: {
        paid,
        status: paid ? 'paid' : 'expected',
        paidTxnId: paid ? paidTxnId || null : null,
        changeSeq: syncState.seq,
      },
    });
    const snapshot = await this.recomputeSnapshot(planId, userId);
    return { fixedExpense: fe, snapshot };
  }

  /**
   * Simulates daily spend scenario against the plan.
   */
  async simulateSpend(userId: string, planId: string, input: SimulatePlanInput) {
    const activeData = await this.getActivePlan(userId);
    if (!activeData || activeData.plan.id !== planId) {
      await this.getPlanById(userId, planId);
    }

    const snapshot = activeData?.snapshot || (await this.recomputeSnapshot(planId, userId));

    const result = simulateScenario({
      flexibleBudget: snapshot.totals.flexible,
      totalDays: snapshot.days.total,
      currentDay: snapshot.days.elapsed,
      spentTotal: snapshot.totals.spent,
      proposedDailySpend: input.proposed_daily_spend,
    });

    return result;
  }

  /**
   * Recomputes and caches snapshot from raw PostgreSQL transactions and reimbursements.
   */
  async recomputeSnapshot(planId: string, userId: string): Promise<PlanSnapshot> {
    const plan = await prisma.budgetPlan.findUnique({
      where: { id: planId },
      include: {
        fixedExpenses: { where: { deletedAt: null } },
      },
    });

    if (!plan) {
      throw new Error(`Plan ${planId} not found`);
    }

    const startLocal = toAddisAbabaDateString(plan.startDate);
    const endLocal = toAddisAbabaDateString(plan.endDate);
    const todayLocal = toAddisAbabaDateString(new Date());

    // Calculate total days N
    const startDateObj = new Date(startLocal);
    const endDateObj = new Date(endLocal);
    const totalDays = Math.max(1, Math.round((endDateObj.getTime() - startDateObj.getTime()) / (1000 * 60 * 60 * 24)) + 1);

    // Current elapsed day d (1 <= d <= totalDays)
    const todayObj = new Date(todayLocal);
    const daysSinceStart = Math.round((todayObj.getTime() - startDateObj.getTime()) / (1000 * 60 * 60 * 24)) + 1;
    const dayIndex = Math.min(Math.max(1, daysSinceStart), totalDays);

    // Fetch transactions in plan window
    const rawTxns = await prisma.transaction.findMany({
      where: {
        userId,
        type: 'expense',
        isInternalTransfer: false,
        deletedAt: null,
        occurredAt: {
          gte: new Date(startLocal + 'T00:00:00.000Z'),
          lte: new Date(endLocal + 'T23:59:59.999Z'),
        },
      },
      include: {
        expenseReimbursements: {
          where: { deletedAt: null },
          select: { amount: true },
        },
      },
    });

    // Group net spending by Addis Ababa date
    const spendByDateMap = new Map<string, number>();
    for (const txn of rawTxns) {
      const dateKey = toAddisAbabaDateString(txn.occurredAt);
      const reimbursedSum = txn.expenseReimbursements.reduce(
        (sum, r) => sum + Number(r.amount),
        0
      );
      const netSpend = Math.max(0, Number(txn.amount) - reimbursedSum);
      spendByDateMap.set(dateKey, (spendByDateMap.get(dateKey) || 0) + netSpend);
    }

    // Build spentByDay array for days 1..d
    const spentByDay: number[] = [];
    for (let i = 0; i < dayIndex; i++) {
      const curDate = new Date(startDateObj.getTime() + i * (1000 * 60 * 60 * 24));
      const curKey = toAddisAbabaDateString(curDate);
      spentByDay.push(round2(spendByDateMap.get(curKey) || 0));
    }

    const fixedTotal = plan.fixedExpenses.reduce((sum, fe) => sum + Number(fe.amount), 0);

    const snapshot = computeSnapshot({
      planId: plan.id,
      asOfDate: todayLocal,
      budget: Number(plan.totalAmount),
      fixedTotal,
      reservePercent: Number(plan.reservePercent),
      savingGoal: Number(plan.savingGoal),
      minDailyFloor: Number(plan.minDailyFloor),
      totalDays,
      dayIndex,
      spentByDay,
      rolloverMode: plan.rolloverMode,
      dayWeights: (plan.dayWeights as any) || undefined,
    });

    // Cache snapshot in database
    await prisma.planSnapshot.upsert({
      where: {
        planId_snapshotDate: {
          planId: plan.id,
          snapshotDate: new Date(todayLocal),
        },
      },
      create: {
        planId: plan.id,
        snapshotDate: new Date(todayLocal),
        payload: snapshot as any,
      },
      update: {
        payload: snapshot as any,
        computedAt: new Date(),
      },
    });

    return snapshot;
  }
}

export const spendingPlanService = new SpendingPlanService();
