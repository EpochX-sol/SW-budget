import { prisma } from '../../../db/prisma.js';
import { Prisma } from '@prisma/client';
import {
  CreatePlanInput,
  UpdatePlanInput,
  SimulatePlanInput,
  CreateFixedExpenseInput,
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

    // Check for overlapping active plan
    const overlapping = await prisma.budgetPlan.findFirst({
      where: {
        userId,
        active: true,
        deletedAt: null,
        OR: [
          {
            startDate: { lte: endDate },
            endDate: { gte: startDate },
          },
        ],
      },
    });

    if (overlapping) {
      const err: any = new Error('An active spending plan already overlaps with this timeframe');
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

    const plan = await prisma.budgetPlan.create({
      data: {
        userId,
        name: input.name,
        totalAmount: new Prisma.Decimal(input.total_amount),
        startDate,
        endDate,
        rolloverMode: input.rollover_mode,
        reservePercent: new Prisma.Decimal(input.reserve_percent),
        savingGoal: new Prisma.Decimal(input.saving_goal),
        minDailyFloor: new Prisma.Decimal(input.min_daily_floor),
        dayWeights: input.day_weights ? (input.day_weights as any) : Prisma.JsonNull,
        active: true,
        changeSeq,
        fixedExpenses: input.fixed_expenses?.length
          ? {
              create: input.fixed_expenses.map((fe) => ({
                title: fe.title,
                amount: new Prisma.Decimal(fe.amount),
                dueDate: fe.due_date ? new Date(fe.due_date) : null,
                paid: fe.paid,
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
   * Adds a fixed expense to an existing plan.
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
        title: input.title,
        amount: new Prisma.Decimal(input.amount),
        dueDate: input.due_date ? new Date(input.due_date) : null,
        paid: input.paid,
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
