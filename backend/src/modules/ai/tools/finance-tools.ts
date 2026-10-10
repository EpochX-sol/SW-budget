import { prisma } from '../../../db/prisma.js';

export interface SpendingSummaryArgs {
  period: 'today' | 'this_week' | 'this_month' | 'last_month';
  category_id?: string;
}

export interface SimulateScenarioArgs {
  amount: number;
  category_id?: string;
}

export interface BudgetStatusArgs {}

export class FinanceTools {
  /**
   * Deterministically calculates exact spending summary from PostgreSQL.
   */
  async getSpendingSummary(userId: string, args: SpendingSummaryArgs) {
    const now = new Date();
    let startDate: Date;
    let endDate: Date = now;

    if (args.period === 'today') {
      startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    } else if (args.period === 'this_week') {
      const day = now.getDay();
      const diff = now.getDate() - day + (day === 0 ? -6 : 1); // Monday start
      startDate = new Date(now.getFullYear(), now.getMonth(), diff);
    } else if (args.period === 'this_month') {
      startDate = new Date(now.getFullYear(), now.getMonth(), 1);
    } else if (args.period === 'last_month') {
      startDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      endDate = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);
    } else {
      startDate = new Date(now.getFullYear(), now.getMonth(), 1);
    }

    const where: any = {
      userId,
      occurredAt: { gte: startDate, lte: endDate },
      deletedAt: null,
    };

    if (args.category_id) {
      where.categoryId = args.category_id;
    }

    const txns = await prisma.transaction.findMany({
      where,
      select: {
        type: true,
        amount: true,
      },
    });

    let totalExpense = 0;
    let totalIncome = 0;
    let count = 0;

    for (const t of txns) {
      const amt = Number(t.amount);
      if (t.type.toLowerCase() === 'expense') {
        totalExpense += amt;
      } else if (t.type.toLowerCase() === 'income') {
        totalIncome += amt;
      }
      count++;
    }

    return {
      period: args.period,
      start_date: startDate.toISOString().split('T')[0],
      end_date: endDate.toISOString().split('T')[0],
      total_expense: Math.round(totalExpense * 100) / 100,
      total_income: Math.round(totalIncome * 100) / 100,
      net_savings: Math.round((totalIncome - totalExpense) * 100) / 100,
      transaction_count: count,
      currency: 'ETB',
    };
  }

  /**
   * Deterministically evaluates the financial impact of a prospective purchase.
   */
  async simulateScenario(userId: string, args: SimulateScenarioArgs) {
    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    // 1. Find relevant limit (category limit or overall limit)
    const limitQuery: any = {
      userId,
      active: true,
      deletedAt: null,
    };

    if (args.category_id) {
      limitQuery.scopeType = 'category';
      limitQuery.scopeId = args.category_id;
    } else {
      limitQuery.scopeType = 'overall';
    }

    let limit = await prisma.limit.findFirst({ where: limitQuery });
    if (!limit && args.category_id) {
      // Fallback to overall limit
      limit = await prisma.limit.findFirst({
        where: { userId, scopeType: 'overall', active: true, deletedAt: null },
      });
    }

    // 2. Compute current month's expenditure
    const txWhere: any = {
      userId,
      type: 'expense',
      occurredAt: { gte: monthStart },
      deletedAt: null,
    };
    if (args.category_id && limit?.scopeType === 'category') {
      txWhere.categoryId = args.category_id;
    }

    const txns = await prisma.transaction.findMany({
      where: txWhere,
      select: { amount: true },
    });

    const currentSpent = txns.reduce((sum, t) => sum + Number(t.amount), 0);
    const simulatedTotal = currentSpent + args.amount;
    const limitAmount = limit ? Number(limit.amount) : 0;
    const hasLimit = limitAmount > 0;

    const remainingBefore = hasLimit ? limitAmount - currentSpent : null;
    const remainingAfter = hasLimit ? limitAmount - simulatedTotal : null;
    const limitBreached = hasLimit ? simulatedTotal > limitAmount : false;

    // Daily pace calculation
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const currentDay = now.getDate();
    const daysRemaining = Math.max(1, daysInMonth - currentDay);
    const safeDailyBudgetAfter = remainingAfter !== null ? Math.max(0, remainingAfter / daysRemaining) : null;

    let daysInDeficit = 0;
    if (limitBreached && limitAmount > 0) {
      const dailyAllowance = limitAmount / daysInMonth;
      const deficit = simulatedTotal - limitAmount;
      daysInDeficit = Math.ceil(deficit / Math.max(1, dailyAllowance));
    }

    return {
      proposed_amount: args.amount,
      current_spent: Math.round(currentSpent * 100) / 100,
      simulated_total: Math.round(simulatedTotal * 100) / 100,
      limit_amount: limitAmount,
      has_limit: hasLimit,
      remaining_before: remainingBefore !== null ? Math.round(remainingBefore * 100) / 100 : null,
      remaining_after: remainingAfter !== null ? Math.round(remainingAfter * 100) / 100 : null,
      limit_breached: limitBreached,
      days_remaining_in_month: daysRemaining,
      safe_daily_budget_after: safeDailyBudgetAfter !== null ? Math.round(safeDailyBudgetAfter * 100) / 100 : null,
      days_in_deficit: daysInDeficit,
      recommended_cap: remainingBefore !== null ? Math.max(0, Math.round(remainingBefore * 100) / 100) : args.amount,
      currency: 'ETB',
    };
  }

  /**
   * Deterministically returns the status of all active user limits.
   */
  async getBudgetStatus(userId: string) {
    const limits = await prisma.limit.findMany({
      where: { userId, active: true, deletedAt: null },
    });

    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    const categories = await prisma.category.findMany({
      where: {
        OR: [{ isSystem: true }, { userId }],
        deletedAt: null,
      },
    });
    const categoryMap = new Map(categories.map((c) => [c.id, c.name]));

    const results = [];
    for (const lim of limits) {
      const txWhere: any = {
        userId,
        type: 'expense',
        occurredAt: { gte: monthStart },
        deletedAt: null,
      };

      let scopeName = 'Overall Budget';
      if (lim.scopeType === 'category' && lim.scopeId) {
        txWhere.categoryId = lim.scopeId;
        scopeName = categoryMap.get(lim.scopeId) || 'Specific Category';
      }

      const txns = await prisma.transaction.findMany({
        where: txWhere,
        select: { amount: true },
      });

      const spent = txns.reduce((sum, t) => sum + Number(t.amount), 0);
      const limitAmount = Number(lim.amount);
      const percentageUsed = limitAmount > 0 ? (spent / limitAmount) * 100 : 0;
      const remaining = limitAmount - spent;

      let status = 'safe';
      if (percentageUsed >= 100) {
        status = 'breached';
      } else if (percentageUsed >= 80) {
        status = 'warning';
      }

      results.push({
        limit_id: lim.id,
        scope_type: lim.scopeType,
        scope_name: scopeName,
        limit_amount: limitAmount,
        spent: Math.round(spent * 100) / 100,
        remaining: Math.round(remaining * 100) / 100,
        percentage_used: Math.round(percentageUsed * 10) / 10,
        status,
        mode: lim.mode,
      });
    }

    return {
      active_limits: results,
      currency: 'ETB',
      month: `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`,
    };
  }

  /**
   * Retrieves active spending plan live snapshot.
   */
  async getActivePlanSnapshot(userId: string) {
    const { spendingPlanService } = await import('../../finance/spending-plan/spending-plan.service.js');
    const active = await spendingPlanService.getActivePlan(userId);
    if (!active) {
      return { has_active_plan: false };
    }
    const snap = active.snapshot;
    return {
      has_active_plan: true,
      plan_id: active.plan.id,
      plan_name: active.plan.name,
      as_of: snap.asOf,
      allowance_today: snap.today.allowance,
      spent_today: snap.today.spent,
      remaining_today: snap.today.remainingToday,
      tomorrow_allowance: snap.tomorrow?.allowance ?? snap.today.baseDaily,
      status: snap.status,
      projected_overspend: snap.pace.projectedOverspend,
      days_until_broke: snap.pace.daysUntilBroke,
      streak: snap.streak,
    };
  }

  /**
   * Simulates proposed daily spend scenario against active plan.
   */
  async simulatePlanSpending(userId: string, args: { proposed_spend_amount: number }) {
    const { spendingPlanService } = await import('../../finance/spending-plan/spending-plan.service.js');
    const active = await spendingPlanService.getActivePlan(userId);
    if (!active) {
      return { has_active_plan: false, error: 'No active spending plan found' };
    }
    const sim = await spendingPlanService.simulateSpend(userId, active.plan.id, {
      proposed_daily_spend: args.proposed_spend_amount,
    });
    return {
      has_active_plan: true,
      proposed_daily_spend: sim.dailySpend,
      projected_total: sim.projectedTotal,
      projected_diff: sim.projectedDiff,
      days_until_exhausted: sim.daysUntilExhausted,
      end_status: sim.status,
    };
  }

  /**
   * Queries debts and loans.
   */
  async queryLoansDebts(userId: string, args: { status?: string; person_name?: string } = {}) {
    const { debtsService } = await import('../../finance/debts/debts.service.js');
    return debtsService.queryDebts(userId, args);
  }

  /**
   * Queries reimbursements.
   */
  async queryReimbursements(userId: string, args: any = {}) {
    const { reimbursementService } = await import('../../finance/reimbursements/reimbursement.service.js');
    return reimbursementService.queryReimbursements(userId, args);
  }
}

export const financeTools = new FinanceTools();

/**
 * Gemini Tool Declarations for Function Calling
 */
export const GEMINI_TOOL_DECLARATIONS = [
  {
    name: 'get_spending_summary',
    description: 'Retrieve exact, computed spending and income totals for a specific time period. NEVER invent numbers; always use this tool.',
    parameters: {
      type: 'OBJECT',
      properties: {
        period: {
          type: 'STRING',
          enum: ['today', 'this_week', 'this_month', 'last_month'],
          description: 'The time horizon to aggregate expenses and income for',
        },
        category_id: {
          type: 'STRING',
          description: 'Optional UUID of the specific category to filter by',
        },
      },
      required: ['period'],
    },
  },
  {
    name: 'simulate_scenario',
    description: 'Simulate the impact of spending a specific amount of money against the user budget and limits. Returns deterministic safe-to-spend balance and deficit pace.',
    parameters: {
      type: 'OBJECT',
      properties: {
        amount: {
          type: 'NUMBER',
          description: 'The prospective amount in ETB the user wishes to spend',
        },
        category_id: {
          type: 'STRING',
          description: 'Optional category UUID of the item or dining occasion',
        },
      },
      required: ['amount'],
    },
  },
  {
    name: 'get_budget_status',
    description: 'Get the exact progress, utilization percentages, and remaining balances for all user budget limits for the current month.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
  },
  {
    name: 'get_active_plan_snapshot',
    description: 'Retrieve the live daily and weekly allowance, tomorrow allowance, pacing status, and streak for the active Adaptive Spending Plan.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
  },
  {
    name: 'simulate_plan_spending',
    description: 'Mathematically forecast if a proposed daily spend rate will keep the user within budget by the end of their spending plan period.',
    parameters: {
      type: 'OBJECT',
      properties: {
        proposed_spend_amount: {
          type: 'NUMBER',
          description: 'The proposed daily expenditure in ETB',
        },
      },
      required: ['proposed_spend_amount'],
    },
  },
  {
    name: 'query_loans_debts',
    description: 'Query who owes the user money (lent) and what debts the user owes others (borrowed), including remaining balances.',
    parameters: {
      type: 'OBJECT',
      properties: {
        status: {
          type: 'STRING',
          enum: ['active', 'settled', 'all'],
          description: 'Filter debts by status',
        },
        person_name: {
          type: 'STRING',
          description: 'Optional name of the contact person to filter by',
        },
      },
    },
  },
  {
    name: 'query_reimbursements',
    description: 'Query expenses that have been reimbursed by friends or counterparties.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
  },
];

