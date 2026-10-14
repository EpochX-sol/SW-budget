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

    // Also include active budget plan if exists
    let activePlanSummary: any = null;
    try {
      const { spendingPlanService } = await import('../../finance/spending-plan/spending-plan.service.js');
      const activePlan = await spendingPlanService.getActivePlan(userId);
      if (activePlan) {
        const snap = activePlan.snapshot;
        activePlanSummary = {
          plan_id: activePlan.plan.id,
          name: activePlan.plan.name,
          period_type: activePlan.plan.periodType,
          total_budget: Number(activePlan.plan.totalAmount),
          start_date: activePlan.plan.startDate.toISOString().slice(0, 10),
          end_date: activePlan.plan.endDate.toISOString().slice(0, 10),
          allowance_today: snap.today.allowance,
          spent_today: snap.today.spent,
          remaining_today: snap.today.remainingToday,
          total_spent_in_plan: snap.totals.spent,
          left_to_spend: snap.totals.remaining,
          status: snap.status,
          projected_overspend: snap.pace.projectedOverspend,
          days_until_broke: snap.pace.daysUntilBroke,
        };
      }
    } catch {
      // Ignore if spending plan calculation not available
    }

    return {
      active_limits: results,
      active_budget_plan: activePlanSummary,
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
      total_budget: snap.totals.budget,
      total_spent: snap.totals.spent,
      remaining_budget: snap.totals.remaining,
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

  /**
   * Retrieves current bank and wallet balances (CBE, Telebirr, Abyssinia, Cash) and all-time net savings.
   */
  async getAccountBalances(userId: string) {
    const accounts = await prisma.account.findMany({
      where: { userId, deletedAt: null },
      select: {
        id: true,
        provider: true,
        name: true,
        accountMask: true,
        lastKnownBalance: true,
        balanceUpdatedAt: true,
        isSavings: true,
      },
      orderBy: { updatedAt: 'desc' },
    });

    let totalLiquidBalance = 0;
    let totalSavingsBalance = 0;

    const accountList = accounts.map((acc) => {
      const bal = acc.lastKnownBalance ? Number(acc.lastKnownBalance) : 0;
      if (acc.isSavings) {
        totalSavingsBalance += bal;
      } else {
        totalLiquidBalance += bal;
      }
      return {
        id: acc.id,
        name: acc.name,
        provider: acc.provider,
        account_mask: acc.accountMask,
        balance: Math.round(bal * 100) / 100,
        is_savings: acc.isSavings,
        last_updated: acc.balanceUpdatedAt?.toISOString() || null,
      };
    });

    // Also get all-time transaction net balance
    const allTxns = await prisma.transaction.findMany({
      where: { userId, deletedAt: null },
      select: { type: true, amount: true },
    });

    let allTimeIncome = 0;
    let allTimeExpense = 0;
    for (const t of allTxns) {
      const amt = Number(t.amount);
      if (t.type.toLowerCase() === 'income') allTimeIncome += amt;
      else if (t.type.toLowerCase() === 'expense') allTimeExpense += amt;
    }
    const allTimeNetSavings = Math.round((allTimeIncome - allTimeExpense) * 100) / 100;

    const totalBalance = totalLiquidBalance + totalSavingsBalance;
    const effectiveTotal = accounts.length > 0 ? totalBalance : allTimeNetSavings;

    return {
      total_balance: effectiveTotal,
      total_liquid_balance: totalLiquidBalance,
      total_savings_balance: totalSavingsBalance,
      all_time_net_savings: allTimeNetSavings,
      total_recorded_income: Math.round(allTimeIncome * 100) / 100,
      total_recorded_expense: Math.round(allTimeExpense * 100) / 100,
      accounts: accountList,
      has_accounts: accounts.length > 0,
      has_transactions: allTxns.length > 0,
      currency: 'ETB',
    };
  }

  /**
   * Granular search and filtering of transactions by keyword, date range, period, category, account, or amount.
   */
  async queryTransactions(userId: string, args: {
    query?: string;
    period?: 'today' | 'this_week' | 'this_month' | 'last_month' | 'last_30_days' | 'year_to_date';
    start_date?: string;
    end_date?: string;
    category_name?: string;
    type?: 'EXPENSE' | 'INCOME' | 'TRANSFER';
    min_amount?: number;
    max_amount?: number;
    limit?: number;
  } = {}) {
    const now = new Date();
    let startDate: Date | undefined;
    let endDate: Date | undefined;

    if (args.start_date) {
      startDate = new Date(args.start_date);
    }
    if (args.end_date) {
      endDate = new Date(args.end_date);
    }

    if (!startDate && args.period) {
      if (args.period === 'today') {
        startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      } else if (args.period === 'this_week') {
        const day = now.getDay();
        const diff = now.getDate() - day + (day === 0 ? -6 : 1);
        startDate = new Date(now.getFullYear(), now.getMonth(), diff);
      } else if (args.period === 'this_month') {
        startDate = new Date(now.getFullYear(), now.getMonth(), 1);
      } else if (args.period === 'last_month') {
        startDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        endDate = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);
      } else if (args.period === 'last_30_days') {
        startDate = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      } else if (args.period === 'year_to_date') {
        startDate = new Date(now.getFullYear(), 0, 1);
      }
    }

    const where: any = {
      userId,
      deletedAt: null,
    };

    if (startDate || endDate) {
      where.occurredAt = {};
      if (startDate) where.occurredAt.gte = startDate;
      if (endDate) where.occurredAt.lte = endDate;
    }

    if (args.type) {
      where.type = { equals: args.type.toLowerCase(), mode: 'insensitive' };
    }

    if (args.min_amount !== undefined || args.max_amount !== undefined) {
      where.amount = {};
      if (args.min_amount !== undefined) where.amount.gte = args.min_amount;
      if (args.max_amount !== undefined) where.amount.lte = args.max_amount;
    }

    if (args.query && args.query.trim()) {
      const q = args.query.trim();
      where.OR = [
        { counterparty: { contains: q, mode: 'insensitive' } },
        { note: { contains: q, mode: 'insensitive' } },
      ];
    }

    if (args.category_name && args.category_name.trim()) {
      where.category = {
        name: { contains: args.category_name.trim(), mode: 'insensitive' },
      };
    }

    const takeLimit = Math.min(args.limit || 10, 25);

    const [txns, totalAggregate] = await Promise.all([
      prisma.transaction.findMany({
        where,
        orderBy: { occurredAt: 'desc' },
        take: takeLimit,
        include: {
          category: { select: { name: true } },
          account: { select: { name: true, provider: true } },
        },
      }),
      prisma.transaction.aggregate({
        where,
        _sum: { amount: true },
        _count: { id: true },
      }),
    ]);

    const formattedTxns = txns.map((t) => ({
      id: t.id,
      date: t.occurredAt.toISOString().split('T')[0],
      amount: Number(t.amount),
      type: t.type,
      merchant: t.counterparty || 'Unknown',
      category: t.category?.name || 'Uncategorized',
      account: t.account ? `${t.account.name} (${t.account.provider})` : 'Unknown Account',
      note: t.note || null,
    }));

    return {
      total_matches: totalAggregate._count.id || 0,
      total_sum: Math.round(Number(totalAggregate._sum.amount || 0) * 100) / 100,
      currency: 'ETB',
      returned_count: formattedTxns.length,
      transactions: formattedTxns,
    };
  }

  async getRecentTransactions(userId: string, args: any = {}) {
    return this.queryTransactions(userId, {
      limit: args.limit || args.count || 10,
      period: args.period || 'this_month',
    });
  }

  /**
   * Analyzes spend frequency, totals, and line items with a specific merchant or counterparty.
   */
  async searchMerchantSpending(userId: string, args: { merchant_name: string; period?: string }) {
    const q = args.merchant_name.trim();
    const now = new Date();
    let startDate: Date | undefined;

    if (args.period === 'this_month') {
      startDate = new Date(now.getFullYear(), now.getMonth(), 1);
    } else if (args.period === 'last_month') {
      startDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    } else if (args.period === 'this_year') {
      startDate = new Date(now.getFullYear(), 0, 1);
    }

    const where: any = {
      userId,
      deletedAt: null,
      counterparty: { contains: q, mode: 'insensitive' },
    };

    if (startDate) {
      where.occurredAt = { gte: startDate };
    }

    const txns = await prisma.transaction.findMany({
      where,
      orderBy: { occurredAt: 'desc' },
      take: 15,
      select: {
        occurredAt: true,
        amount: true,
        counterparty: true,
        type: true,
      },
    });

    let totalExpense = 0;
    let totalIncome = 0;
    for (const t of txns) {
      const amt = Number(t.amount);
      if (t.type.toLowerCase() === 'expense') totalExpense += amt;
      else if (t.type.toLowerCase() === 'income') totalIncome += amt;
    }

    const avgSpend = txns.length > 0 ? totalExpense / txns.length : 0;

    return {
      merchant_query: q,
      transaction_count: txns.length,
      total_spent: Math.round(totalExpense * 100) / 100,
      total_income_from_merchant: Math.round(totalIncome * 100) / 100,
      average_spend: Math.round(avgSpend * 100) / 100,
      currency: 'ETB',
      recent_transactions: txns.slice(0, 5).map((t) => ({
        date: t.occurredAt.toISOString().split('T')[0],
        amount: Number(t.amount),
        type: t.type,
      })),
    };
  }

  /**
   * Identifies the user's top largest expenses.
   */
  async getTopExpenses(userId: string, args: { period?: 'today' | 'this_week' | 'this_month' | 'last_month' | 'all_time'; limit?: number } = {}) {
    const now = new Date();
    let startDate: Date | undefined;
    let endDate: Date | undefined;

    if (args.period === 'today') {
      startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    } else if (args.period === 'this_week') {
      const day = now.getDay();
      const diff = now.getDate() - day + (day === 0 ? -6 : 1);
      startDate = new Date(now.getFullYear(), now.getMonth(), diff);
    } else if (args.period === 'this_month') {
      startDate = new Date(now.getFullYear(), now.getMonth(), 1);
    } else if (args.period === 'last_month') {
      startDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      endDate = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);
    }

    const where: any = {
      userId,
      deletedAt: null,
      type: { equals: 'expense', mode: 'insensitive' },
    };

    if (startDate || endDate) {
      where.occurredAt = {};
      if (startDate) where.occurredAt.gte = startDate;
      if (endDate) where.occurredAt.lte = endDate;
    }

    const limit = Math.min(args.limit || 5, 10);
    const topTxns = await prisma.transaction.findMany({
      where,
      orderBy: { amount: 'desc' },
      take: limit,
      include: {
        category: { select: { name: true } },
      },
    });

    return {
      period: args.period || 'this_month',
      top_expenses: topTxns.map((t) => ({
        date: t.occurredAt.toISOString().split('T')[0],
        merchant: t.counterparty || 'Unknown',
        category: t.category?.name || 'Uncategorized',
        amount: Number(t.amount),
      })),
      currency: 'ETB',
    };
  }

  /**
   * Computes category-by-category spending allocation.
   */
  async getCategoryBreakdown(userId: string, args: { period?: 'this_month' | 'last_month' | 'this_week' } = {}) {
    const now = new Date();
    let startDate = new Date(now.getFullYear(), now.getMonth(), 1);
    let endDate: Date | undefined;

    if (args.period === 'last_month') {
      startDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      endDate = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);
    } else if (args.period === 'this_week') {
      const day = now.getDay();
      const diff = now.getDate() - day + (day === 0 ? -6 : 1);
      startDate = new Date(now.getFullYear(), now.getMonth(), diff);
    }

    const where: any = {
      userId,
      deletedAt: null,
      type: { equals: 'expense', mode: 'insensitive' },
      occurredAt: { gte: startDate, ...(endDate ? { lte: endDate } : {}) },
    };

    const txns = await prisma.transaction.findMany({
      where,
      select: {
        amount: true,
        category: { select: { id: true, name: true, icon: true } },
      },
    });

    const categoryMap = new Map<string, { name: string; icon: string | null; total: number; count: number }>();
    let totalExpense = 0;

    for (const t of txns) {
      const amt = Number(t.amount);
      totalExpense += amt;
      const catName = t.category?.name || 'Uncategorized';
      const existing = categoryMap.get(catName) || { name: catName, icon: t.category?.icon || null, total: 0, count: 0 };
      existing.total += amt;
      existing.count += 1;
      categoryMap.set(catName, existing);
    }

    const breakdown = Array.from(categoryMap.values())
      .map((c) => ({
        category: c.name,
        amount: Math.round(c.total * 100) / 100,
        percentage: totalExpense > 0 ? Math.round((c.total / totalExpense) * 1000) / 10 : 0,
        count: c.count,
      }))
      .sort((a, b) => b.amount - a.amount);

    return {
      period: args.period || 'this_month',
      total_expense: Math.round(totalExpense * 100) / 100,
      categories: breakdown,
      currency: 'ETB',
    };
  }

  /**
   * Detects recurring subscriptions, regular bills, and monthly commitments.
   */
  async detectRecurringBills(userId: string) {
    const sixtyDaysAgo = new Date(Date.now() - 60 * 24 * 60 * 60 * 1000);
    const txns = await prisma.transaction.findMany({
      where: {
        userId,
        deletedAt: null,
        type: { equals: 'expense', mode: 'insensitive' },
        occurredAt: { gte: sixtyDaysAgo },
      },
      select: {
        counterparty: true,
        amount: true,
        occurredAt: true,
        category: { select: { name: true } },
      },
      orderBy: { occurredAt: 'desc' },
    });

    const merchantGroups = new Map<string, { merchant: string; amounts: number[]; category: string; latestDate: Date }>();
    for (const t of txns) {
      if (!t.counterparty || t.counterparty.trim().length === 0) continue;
      const m = t.counterparty.trim();
      const amt = Number(t.amount);
      const existing = merchantGroups.get(m) || { merchant: m, amounts: [], category: t.category?.name || 'General', latestDate: t.occurredAt };
      existing.amounts.push(amt);
      merchantGroups.set(m, existing);
    }

    const recurring: any[] = [];
    let estimatedMonthlyCommitment = 0;

    for (const group of merchantGroups.values()) {
      if (group.amounts.length >= 2) {
        const avg = group.amounts.reduce((a, b) => a + b, 0) / group.amounts.length;
        estimatedMonthlyCommitment += avg;
        recurring.push({
          merchant: group.merchant,
          category: group.category,
          average_amount: Math.round(avg * 100) / 100,
          occurrences_last_60d: group.amounts.length,
          last_charged: group.latestDate.toISOString().split('T')[0],
        });
      }
    }

    return {
      recurring_bills: recurring,
      estimated_monthly_commitment: Math.round(estimatedMonthlyCommitment * 100) / 100,
      has_recurring: recurring.length > 0,
      currency: 'ETB',
    };
  }

  /**
   * Retrieves active saving goals, targets, and progress.
   */
  async querySavingGoals(userId: string) {
    const savingPlans = await prisma.savingPlan.findMany({
      where: { userId, deletedAt: null },
      include: { linkedAccount: true },
      orderBy: { priority: 'asc' },
    });

    const goals = savingPlans.map((p) => {
      const target = Number(p.targetAmount);
      const current = p.linkedAccount ? Number(p.linkedAccount.lastKnownBalance || 0) : 0;
      const remaining = Math.max(0, target - current);
      const pct = target > 0 ? Math.round((current / target) * 100) : 0;
      return {
        id: p.id,
        name: p.name,
        target_amount: target,
        current_amount: current,
        remaining_amount: remaining,
        percentage_completed: pct,
        target_date: p.endDate ? p.endDate.toISOString().split('T')[0] : null,
      };
    });

    return {
      saving_goals: goals,
      total_goals_count: goals.length,
      currency: 'ETB',
    };
  }
}

export const financeTools = new FinanceTools();

/**
 * Gemini Tool Declarations for Function Calling
 */
export const GEMINI_TOOL_DECLARATIONS = [
  {
    name: 'get_account_balances',
    description: 'Retrieve current bank and wallet account balances (CBE, Telebirr, Abyssinia, Cash) and total liquid/savings balances. ALWAYS call this when user asks about their balance, how much money they have, or bank status.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
  },
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
  {
    name: 'query_transactions',
    description: 'Search, filter, and inspect specific individual transactions by merchant name, note keyword, date window, category, type (EXPENSE/INCOME), or amount range.',
    parameters: {
      type: 'OBJECT',
      properties: {
        query: { type: 'STRING', description: 'Keyword to search across merchant name or note' },
        period: { type: 'STRING', enum: ['today', 'this_week', 'this_month', 'last_month', 'last_30_days', 'year_to_date'], description: 'Time horizon' },
        start_date: { type: 'STRING', description: 'Optional start date YYYY-MM-DD' },
        end_date: { type: 'STRING', description: 'Optional end date YYYY-MM-DD' },
        category_name: { type: 'STRING', description: 'Optional category name' },
        type: { type: 'STRING', enum: ['EXPENSE', 'INCOME', 'TRANSFER'], description: 'Transaction type' },
        min_amount: { type: 'NUMBER', description: 'Minimum amount filter' },
        max_amount: { type: 'NUMBER', description: 'Maximum amount filter' },
        limit: { type: 'NUMBER', description: 'Max number of transactions to return (1-25)' },
      },
    },
  },
  {
    name: 'get_recent_transactions',
    description: 'Fetch the most recent recorded expenses or transactions. Alias for query_transactions with recent sort.',
    parameters: {
      type: 'OBJECT',
      properties: {
        limit: { type: 'NUMBER', description: 'Number of recent transactions to return (default 10)' },
        period: { type: 'STRING', enum: ['today', 'this_week', 'this_month', 'last_month'], description: 'Time horizon' },
      },
    },
  },
  {
    name: 'search_merchant_spending',
    description: 'Analyze total spend, transaction frequency, and average spending with a specific merchant (e.g. Feres, Ride, Kaldis, Telebirr, Supermarket).',
    parameters: {
      type: 'OBJECT',
      properties: {
        merchant_name: { type: 'STRING', description: 'The merchant or counterparty name to analyze' },
        period: { type: 'STRING', enum: ['this_month', 'last_month', 'this_year', 'all_time'], description: 'Time period' },
      },
      required: ['merchant_name'],
    },
  },
  {
    name: 'get_top_expenses',
    description: 'Retrieve the largest individual expense transactions for a given period.',
    parameters: {
      type: 'OBJECT',
      properties: {
        period: { type: 'STRING', enum: ['today', 'this_week', 'this_month', 'last_month', 'all_time'], description: 'Time period' },
        limit: { type: 'NUMBER', description: 'How many top expenses to return (default 5)' },
      },
    },
  },
  {
    name: 'get_category_breakdown',
    description: 'Get total spend and percentage allocation for all expense categories.',
    parameters: {
      type: 'OBJECT',
      properties: {
        period: { type: 'STRING', enum: ['this_week', 'this_month', 'last_month'], description: 'Time period' },
      },
    },
  },
  {
    name: 'detect_recurring_bills',
    description: 'Detect recurring monthly subscriptions, regular bills, and periodic obligations (e.g. internet, rent, gym).',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
  },
  {
    name: 'query_saving_goals',
    description: 'Retrieve active saving goals, target amounts, current saved amounts, and completion percentages.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
  },
];

/**
 * OpenAI / OpenRouter Tool Declarations for Function Calling
 */
export const OPENAI_TOOL_DECLARATIONS = [
  {
    type: 'function',
    function: {
      name: 'get_account_balances',
      description: 'Retrieve current bank and wallet account balances (CBE, Telebirr, Abyssinia, Cash) and total liquid/savings balances. ALWAYS call this when user asks about their balance, how much money they have, or bank status.',
      parameters: {
        type: 'object',
        properties: {},
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_spending_summary',
      description: 'Retrieve exact, computed spending and income totals for a specific time period. NEVER invent numbers; always use this tool.',
      parameters: {
        type: 'object',
        properties: {
          period: {
            type: 'string',
            enum: ['today', 'this_week', 'this_month', 'last_month'],
            description: 'The time horizon to aggregate expenses and income for',
          },
          category_id: {
            type: 'string',
            description: 'Optional UUID of the specific category to filter by',
          },
        },
        required: ['period'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'simulate_scenario',
      description: 'Simulate the impact of spending a specific amount of money against the user budget and limits. Returns deterministic safe-to-spend balance and deficit pace.',
      parameters: {
        type: 'object',
        properties: {
          amount: {
            type: 'number',
            description: 'The prospective amount in ETB the user wishes to spend',
          },
          category_id: {
            type: 'string',
            description: 'Optional category UUID of the item or dining occasion',
          },
        },
        required: ['amount'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_budget_status',
      description: 'Get the exact progress, utilization percentages, and remaining balances for all user budget limits for the current month.',
      parameters: {
        type: 'object',
        properties: {},
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_active_plan_snapshot',
      description: 'Retrieve the live daily and weekly allowance, tomorrow allowance, pacing status, and streak for the active Adaptive Spending Plan.',
      parameters: {
        type: 'object',
        properties: {},
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'simulate_plan_spending',
      description: 'Mathematically forecast if a proposed daily spend rate will keep the user within budget by the end of their spending plan period.',
      parameters: {
        type: 'object',
        properties: {
          proposed_spend_amount: {
            type: 'number',
            description: 'The proposed daily expenditure in ETB',
          },
        },
        required: ['proposed_spend_amount'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'query_loans_debts',
      description: 'Query who owes the user money (lent) and what debts the user owes others (borrowed), including remaining balances.',
      parameters: {
        type: 'object',
        properties: {
          status: {
            type: 'string',
            enum: ['active', 'settled', 'all'],
            description: 'Filter debts by status',
          },
          person_name: {
            type: 'string',
            description: 'Optional name of the contact person to filter by',
          },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'query_reimbursements',
      description: 'Query expenses that have been reimbursed by friends or counterparties.',
      parameters: {
        type: 'object',
        properties: {},
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'query_transactions',
      description: 'Search, filter, and inspect specific individual transactions by merchant name, note keyword, date window, category, type (EXPENSE/INCOME), or amount range.',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Keyword to search across merchant name or note' },
          period: { type: 'string', enum: ['today', 'this_week', 'this_month', 'last_month', 'last_30_days', 'year_to_date'], description: 'Time horizon' },
          start_date: { type: 'string', description: 'Optional start date YYYY-MM-DD' },
          end_date: { type: 'string', description: 'Optional end date YYYY-MM-DD' },
          category_name: { type: 'string', description: 'Optional category name' },
          type: { type: 'string', enum: ['EXPENSE', 'INCOME', 'TRANSFER'], description: 'Transaction type' },
          min_amount: { type: 'number', description: 'Minimum amount filter' },
          max_amount: { type: 'number', description: 'Maximum amount filter' },
          limit: { type: 'number', description: 'Max number of transactions to return (1-25)' },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_recent_transactions',
      description: 'Fetch the most recent recorded expenses or transactions. Alias for query_transactions.',
      parameters: {
        type: 'object',
        properties: {
          limit: { type: 'number', description: 'Number of recent transactions to return (default 10)' },
          period: { type: 'string', enum: ['today', 'this_week', 'this_month', 'last_month'], description: 'Time horizon' },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'search_merchant_spending',
      description: 'Analyze total spend, transaction frequency, and average spending with a specific merchant (e.g. Feres, Ride, Kaldis, Telebirr, Supermarket).',
      parameters: {
        type: 'object',
        properties: {
          merchant_name: { type: 'string', description: 'The merchant or counterparty name to analyze' },
          period: { type: 'string', enum: ['this_month', 'last_month', 'this_year', 'all_time'], description: 'Time period' },
        },
        required: ['merchant_name'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_top_expenses',
      description: 'Retrieve the largest individual expense transactions for a given period.',
      parameters: {
        type: 'object',
        properties: {
          period: { type: 'string', enum: ['today', 'this_week', 'this_month', 'last_month', 'all_time'], description: 'Time period' },
          limit: { type: 'number', description: 'How many top expenses to return (default 5)' },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_category_breakdown',
      description: 'Get total spend and percentage allocation for all expense categories.',
      parameters: {
        type: 'object',
        properties: {
          period: { type: 'string', enum: ['this_week', 'this_month', 'last_month'], description: 'Time period' },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'detect_recurring_bills',
      description: 'Detect recurring monthly subscriptions, regular bills, and periodic obligations (e.g. internet, rent, gym).',
      parameters: {
        type: 'object',
        properties: {},
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'query_saving_goals',
      description: 'Retrieve active saving goals, target amounts, current saved amounts, and completion percentages.',
      parameters: {
        type: 'object',
        properties: {},
      },
    },
  },
];

