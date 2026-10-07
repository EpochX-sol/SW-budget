import { prisma } from '../../db/prisma.js';

export class AnalyticsService {
  /**
   * Generates a 30-day financial burn-down forecast.
   */
  async getForecast(userId: string) {
    // 1. Current balance across all accounts
    const accounts = await prisma.account.findMany({
      where: { userId, deletedAt: null },
      select: { lastKnownBalance: true },
    });

    const currentBalance = accounts.reduce(
      (sum, acc) => sum + (acc.lastKnownBalance ? Number(acc.lastKnownBalance) : 0),
      0
    );

    // 2. Compute 30-day daily burn rate
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const pastTxns = await prisma.transaction.findMany({
      where: {
        userId,
        type: 'expense',
        occurredAt: { gte: thirtyDaysAgo },
        deletedAt: null,
      },
      select: { amount: true },
    });

    const totalSpent30Days = pastTxns.reduce((sum, t) => sum + Number(t.amount), 0);
    const dailyBurnRate = Math.max(10, Math.round((totalSpent30Days / 30) * 100) / 100);

    // 3. Generate 30-day projected trajectory
    const points = [];
    const now = new Date();
    let projected = currentBalance;

    for (let i = 0; i <= 30; i++) {
      const d = new Date(now.getTime() + i * 24 * 60 * 60 * 1000);
      const dateStr = d.toISOString().split('T')[0];
      points.push({
        date: dateStr,
        projected_balance: Math.round(projected * 100) / 100,
        day_offset: i,
      });
      projected = Math.max(0, projected - dailyBurnRate);
    }

    const projectedEndBalance = points[points.length - 1].projected_balance;

    return {
      current_balance: Math.round(currentBalance * 100) / 100,
      daily_burn_rate: dailyBurnRate,
      projected_end_balance: projectedEndBalance,
      currency: 'ETB',
      forecast_horizon_days: 30,
      points,
    };
  }

  /**
   * Analyzes spending trends and category distribution.
   */
  async getTrends(userId: string) {
    const now = new Date();
    const currentMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const lastMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const lastMonthEnd = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);

    const [currentTxns, lastMonthTxns, categories] = await Promise.all([
      prisma.transaction.findMany({
        where: {
          userId,
          type: 'expense',
          occurredAt: { gte: currentMonthStart },
          deletedAt: null,
        },
        select: { categoryId: true, amount: true },
      }),
      prisma.transaction.findMany({
        where: {
          userId,
          type: 'expense',
          occurredAt: { gte: lastMonthStart, lte: lastMonthEnd },
          deletedAt: null,
        },
        select: { amount: true },
      }),
      prisma.category.findMany({
        where: { OR: [{ isSystem: true }, { userId }], deletedAt: null },
      }),
    ]);

    const catMap = new Map(categories.map((c) => [c.id, { name: c.name, color: c.colorHex, icon: c.icon }]));

    const currentTotal = currentTxns.reduce((sum, t) => sum + Number(t.amount), 0);
    const lastMonthTotal = lastMonthTxns.reduce((sum, t) => sum + Number(t.amount), 0);

    // Group by category
    const catTotals = new Map<string, number>();
    for (const t of currentTxns) {
      const cid = t.categoryId || 'uncategorized';
      catTotals.set(cid, (catTotals.get(cid) || 0) + Number(t.amount));
    }

    const categoryBreakdown = [];
    for (const [cid, spent] of catTotals.entries()) {
      const catInfo = catMap.get(cid) || { name: 'Uncategorized', color: '#6B7280', icon: 'tag' };
      const pct = currentTotal > 0 ? (spent / currentTotal) * 100 : 0;
      categoryBreakdown.push({
        category_id: cid,
        name: catInfo.name,
        color: catInfo.color,
        icon: catInfo.icon,
        total_spent: Math.round(spent * 100) / 100,
        percentage: Math.round(pct * 10) / 10,
      });
    }

    categoryBreakdown.sort((a, b) => b.total_spent - a.total_spent);

    return {
      current_month_total: Math.round(currentTotal * 100) / 100,
      last_month_total: Math.round(lastMonthTotal * 100) / 100,
      month_over_month_change_pct:
        lastMonthTotal > 0
          ? Math.round(((currentTotal - lastMonthTotal) / lastMonthTotal) * 1000) / 10
          : 0,
      category_breakdown: categoryBreakdown,
      currency: 'ETB',
    };
  }

  /**
   * Aggregates banking and transaction fee insights.
   */
  async getFees(userId: string) {
    const dailyTotals = await prisma.dailyCategoryTotal.findMany({
      where: { userId },
      select: { fees: true, day: true },
    });

    const totalFees = dailyTotals.reduce((sum, d) => sum + Number(d.fees), 0);

    return {
      total_fees: Math.round(totalFees * 100) / 100,
      currency: 'ETB',
      description: 'Transaction fees identified across CBE transfers, Telebirr merchant charges, and ATM withdrawals.',
    };
  }
}

export const analyticsService = new AnalyticsService();
