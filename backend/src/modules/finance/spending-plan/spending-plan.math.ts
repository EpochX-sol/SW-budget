/**
 * Adaptive Spending Plan - Pure Calculation Engine
 * Milestone B6: Deterministic math, 4 rollover strategies, week partitioning, scenario simulation.
 * Pure TypeScript with zero side-effects.
 */

export type RolloverMode = 'SPREAD_EVENLY' | 'NEXT_DAY' | 'WEEK_ONLY' | 'TO_SAVINGS';

export interface PlanSnapshotWeek {
  index: number;
  startDay: number;
  endDay: number;
  days: number;
  baseTarget: number;
  adjustedTarget: number;
  spent: number;
  pctUsed: number;
  pctElapsed: number;
}

export interface PlanSnapshot {
  planId: string;
  asOf: string; // 'YYYY-MM-DD' in Africa/Addis_Ababa timezone
  totals: {
    budget: number;
    fixed: number;
    reserve: number;
    flexible: number;
    spent: number;
    remaining: number;
  };
  days: {
    total: number;
    elapsed: number;
    left: number;
  };
  today: {
    baseDaily: number;
    allowance: number;
    spent: number;
    remainingToday: number;
    varianceVsAllowancePct: number | null;
    varianceVsBasePct: number;
  };
  tomorrow: {
    allowance: number;
    pctOfBase: number;
    adjustmentPct: number;
  } | null;
  pace: {
    expectedToDate: number;
    cumulativeVariancePct: number;
    projectedTotal: number;
    projectedOverspend: number;
    daysUntilBroke: number | null;
  };
  weeks: PlanSnapshotWeek[];
  status: 'GREEN' | 'YELLOW' | 'ORANGE' | 'RED';
  streak: number;
}

export interface ComputeSnapshotInput {
  planId: string;
  asOfDate: string; // 'YYYY-MM-DD'
  budget: number;
  fixedTotal?: number;
  reservePercent?: number;
  savingGoal?: number;
  minDailyFloor?: number;
  totalDays: number; // N
  dayIndex: number;  // d (1-based, 1 <= d <= totalDays)
  spentByDay: number[]; // length = dayIndex, index 0 = Day 1 net spend
  rolloverMode?: RolloverMode;
  dayWeights?: Record<string, number>;
}

/** Round to 2 decimal places deterministically */
export function round2(num: number): number {
  return Math.round((num + Number.EPSILON) * 100) / 100;
}

/** Formats date into YYYY-MM-DD under Africa/Addis_Ababa (UTC+3) */
export function toAddisAbabaDateString(date: Date | string | number): string {
  const d = typeof date === 'object' ? date : new Date(date);
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Africa/Addis_Ababa',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(d);
}

/**
 * Pure calculation engine for Adaptive Spending Plan
 */
export function computeSnapshot(input: ComputeSnapshotInput): PlanSnapshot {
  const {
    planId,
    asOfDate,
    budget: B,
    fixedTotal: F = 0,
    reservePercent = 0,
    savingGoal = 0,
    minDailyFloor = 0,
    totalDays: N,
    dayIndex: d,
    spentByDay,
    rolloverMode = 'SPREAD_EVENLY',
  } = input;

  if (N <= 0) {
    throw new Error('Total days (N) must be greater than 0');
  }

  const reserve = round2(B * (reservePercent / 100));
  const X = round2(Math.max(0, B - F - reserve - savingGoal)); // Flexible pool
  const baseDaily = round2(N > 0 ? X / N : 0);

  const spentToday = round2(spentByDay[d - 1] ?? 0);
  const spentTotal = round2(spentByDay.slice(0, d).reduce((acc, curr) => acc + curr, 0));
  const spentPrev = round2(spentTotal - spentToday);

  const daysLeftInclToday = Math.max(1, N - d + 1);
  const daysLeftAfterToday = Math.max(0, N - d);

  // 1. Allowance Today
  let allowanceToday = 0;
  if (rolloverMode === 'NEXT_DAY' && d > 1) {
    const yesterdaySpent = spentByDay[d - 2] ?? 0;
    // Absorbs yesterday's variance directly
    allowanceToday = Math.max(0, baseDaily - (yesterdaySpent - baseDaily));
  } else if (rolloverMode === 'WEEK_ONLY') {
    // Current week boundary
    const weekStartDay = Math.floor((d - 1) / 7) * 7 + 1;
    const daysPassedInWeek = d - weekStartDay;
    const daysLeftInWeek = Math.min(7 - daysPassedInWeek, daysLeftInclToday);
    const weekBaseTarget = baseDaily * Math.min(7, N - weekStartDay + 1);
    const spentInWeekPrev = spentByDay
      .slice(weekStartDay - 1, d - 1)
      .reduce((a, b) => a + b, 0);
    const remainingInWeek = Math.max(0, weekBaseTarget - spentInWeekPrev);
    allowanceToday = daysLeftInWeek > 0 ? remainingInWeek / daysLeftInWeek : baseDaily;
  } else {
    // SPREAD_EVENLY or TO_SAVINGS
    allowanceToday = daysLeftInclToday > 0 ? Math.max(0, (X - spentPrev) / daysLeftInclToday) : 0;
  }
  allowanceToday = round2(allowanceToday);

  const remaining = round2(X - spentTotal);

  // 2. Tomorrow Allowance
  let tomorrowAllowance: number | null = null;
  let tomorrowPctOfBase: number | null = null;
  let adjustmentPct = 0;

  if (daysLeftAfterToday > 0) {
    if (rolloverMode === 'NEXT_DAY') {
      tomorrowAllowance = Math.max(0, baseDaily - (spentToday - allowanceToday));
    } else if (rolloverMode === 'WEEK_ONLY') {
      const currentWeekIndex = Math.floor((d - 1) / 7);
      const nextDayWeekIndex = Math.floor(d / 7);
      if (nextDayWeekIndex > currentWeekIndex) {
        // Next day starts a brand new week at baseDaily
        tomorrowAllowance = baseDaily;
      } else {
        const weekStartDay = currentWeekIndex * 7 + 1;
        const daysLeftInWeek = Math.min(7, N - weekStartDay + 1) - (d - weekStartDay + 1);
        const weekBaseTarget = baseDaily * Math.min(7, N - weekStartDay + 1);
        const spentInWeek = spentByDay
          .slice(weekStartDay - 1, d)
          .reduce((a, b) => a + b, 0);
        const remainingInWeek = Math.max(0, weekBaseTarget - spentInWeek);
        tomorrowAllowance = daysLeftInWeek > 0 ? remainingInWeek / daysLeftInWeek : baseDaily;
      }
    } else if (rolloverMode === 'TO_SAVINGS') {
      if (spentToday < allowanceToday) {
        // Underspend is swept into savings; tomorrow remains at baseDaily
        tomorrowAllowance = baseDaily;
      } else {
        // Overspend is spread across remaining days
        tomorrowAllowance = Math.max(0, remaining / daysLeftAfterToday);
      }
    } else {
      // SPREAD_EVENLY
      tomorrowAllowance = Math.max(0, remaining / daysLeftAfterToday);
    }

    tomorrowAllowance = round2(tomorrowAllowance);
    tomorrowPctOfBase = baseDaily > 0 ? round2((tomorrowAllowance / baseDaily) * 100) : 100;
    adjustmentPct = round2(tomorrowPctOfBase - 100);
  }

  // 3. Pace & Variance
  const expectedToDate = round2(baseDaily * d);
  const avgDaily = d > 0 ? round2(spentTotal / d) : 0;
  const projectedTotal = round2(avgDaily * N);
  const projectedOverspend = round2(projectedTotal - X);

  const ratio = expectedToDate > 0 ? spentTotal / expectedToDate : 0;
  let status: 'GREEN' | 'YELLOW' | 'ORANGE' | 'RED';
  if (remaining <= 0 || (d >= 3 && projectedTotal > X * 1.2)) {
    status = 'RED';
  } else if (ratio > 1.0) {
    status = 'ORANGE';
  } else if (ratio > 0.9) {
    status = 'YELLOW';
  } else {
    status = 'GREEN';
  }

  // 4. Streak Calculation (Consecutive days within allowance or within 5% leeway)
  let streak = 0;
  for (let i = d - 1; i >= 0; i--) {
    const daySpend = spentByDay[i] ?? 0;
    if (daySpend <= baseDaily * 1.05) {
      streak++;
    } else {
      break;
    }
  }

  // 5. Partition Weeks
  const weeks = partitionWeeks({
    totalDays: N,
    currentDay: d,
    baseDaily,
    tomorrowAllowance: tomorrowAllowance ?? baseDaily,
    spentByDay,
  });

  const remainingToday = round2(allowanceToday - spentToday);
  const varianceVsAllowancePct = allowanceToday > 0
    ? round2(((spentToday - allowanceToday) / allowanceToday) * 100)
    : null;
  const varianceVsBasePct = baseDaily > 0
    ? round2(((spentToday - baseDaily) / baseDaily) * 100)
    : 0;

  return {
    planId,
    asOf: asOfDate,
    totals: {
      budget: B,
      fixed: F,
      reserve,
      flexible: X,
      spent: spentTotal,
      remaining,
    },
    days: {
      total: N,
      elapsed: d,
      left: daysLeftAfterToday,
    },
    today: {
      baseDaily,
      allowance: allowanceToday,
      spent: spentToday,
      remainingToday,
      varianceVsAllowancePct,
      varianceVsBasePct,
    },
    tomorrow: tomorrowAllowance !== null ? {
      allowance: tomorrowAllowance,
      pctOfBase: tomorrowPctOfBase!,
      adjustmentPct,
    } : null,
    pace: {
      expectedToDate,
      cumulativeVariancePct: expectedToDate > 0
        ? round2(((spentTotal - expectedToDate) / expectedToDate) * 100)
        : 0,
      projectedTotal,
      projectedOverspend,
      daysUntilBroke: avgDaily > 0 && remaining > 0 ? round2(remaining / avgDaily) : remaining <= 0 ? 0 : null,
    },
    weeks,
    status,
    streak,
  };
}

/**
 * Partitions the plan into 7-day calendar weeks, computing base and dynamically adjusted targets
 * ensuring that: Sum(adjustedTarget) = Sum(spentToDate) + Sum(futureDays * tomorrowAllowance) = Total Flexible
 */
export function partitionWeeks(input: {
  totalDays: number;
  currentDay: number;
  baseDaily: number;
  tomorrowAllowance: number;
  spentByDay: number[];
}): PlanSnapshotWeek[] {
  const { totalDays, currentDay, baseDaily, tomorrowAllowance, spentByDay } = input;
  const weeks: PlanSnapshotWeek[] = [];
  const numWeeks = Math.ceil(totalDays / 7);

  for (let w = 0; w < numWeeks; w++) {
    const startDay = w * 7 + 1;
    const endDay = Math.min((w + 1) * 7, totalDays);
    const daysInWeek = endDay - startDay + 1;
    const baseTarget = round2(baseDaily * daysInWeek);

    // Calculate actual spent in this week so far
    let spentInWeek = 0;
    let completedDaysInWeek = 0;

    for (let day = startDay; day <= endDay; day++) {
      if (day <= currentDay) {
        spentInWeek += spentByDay[day - 1] ?? 0;
        completedDaysInWeek++;
      }
    }
    spentInWeek = round2(spentInWeek);

    // Future days in this week
    const futureDaysInWeek = daysInWeek - completedDaysInWeek;
    const adjustedTarget = round2(spentInWeek + (futureDaysInWeek * tomorrowAllowance));

    const pctUsed = baseTarget > 0 ? round2((spentInWeek / baseTarget) * 100) : 0;
    const pctElapsed = daysInWeek > 0 ? round2((completedDaysInWeek / daysInWeek) * 100) : 0;

    weeks.push({
      index: w + 1,
      startDay,
      endDay,
      days: daysInWeek,
      baseTarget,
      adjustedTarget,
      spent: spentInWeek,
      pctUsed,
      pctElapsed,
    });
  }

  return weeks;
}

/**
 * Scenario simulator for "What if I spend X ETB per day?"
 */
export interface SimulationResult {
  dailySpend: number;
  projectedTotal: number;
  projectedDiff: number; // positive = overspend, negative = savings
  daysUntilExhausted: number | null;
  status: 'SAFE' | 'WARNING' | 'DEFICIT';
}

export function simulateScenario(params: {
  flexibleBudget: number;
  totalDays: number;
  currentDay: number;
  spentTotal: number;
  proposedDailySpend: number;
}): SimulationResult {
  const { flexibleBudget, totalDays, currentDay, spentTotal, proposedDailySpend } = params;
  const remainingDays = Math.max(0, totalDays - currentDay);
  const remainingBudget = flexibleBudget - spentTotal;

  const futureSpend = round2(proposedDailySpend * remainingDays);
  const projectedTotal = round2(spentTotal + futureSpend);
  const projectedDiff = round2(projectedTotal - flexibleBudget);

  let daysUntilExhausted: number | null = null;
  if (proposedDailySpend > 0) {
    daysUntilExhausted = remainingBudget > 0 ? round2(remainingBudget / proposedDailySpend) : 0;
  }

  let status: 'SAFE' | 'WARNING' | 'DEFICIT';
  if (projectedDiff > 0) {
    status = 'DEFICIT';
  } else if (projectedDiff > -0.1 * flexibleBudget) {
    status = 'WARNING';
  } else {
    status = 'SAFE';
  }

  return {
    dailySpend: proposedDailySpend,
    projectedTotal,
    projectedDiff,
    daysUntilExhausted,
    status,
  };
}
