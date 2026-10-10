import { describe, it, expect } from 'vitest';
import {
  computeSnapshot,
  partitionWeeks,
  simulateScenario,
  round2,
  toAddisAbabaDateString,
} from '../src/modules/finance/spending-plan/spending-plan.math.js';

describe('Milestone B6: Adaptive Spending Plan Math Calculation Engine', () => {
  const planId = '018f3a5e-0000-7000-8000-000000000001';

  describe('Worked Example Specification (Section 7.3: B=14000, N=14)', () => {
    it('accurately computes Day 1 (1500 ETB spent vs 1000 ETB allowance)', () => {
      const snap = computeSnapshot({
        planId,
        asOfDate: '2026-10-01',
        budget: 14000,
        totalDays: 14,
        dayIndex: 1,
        spentByDay: [1500],
        rolloverMode: 'SPREAD_EVENLY',
      });

      expect(snap.totals.budget).toBe(14000);
      expect(snap.totals.flexible).toBe(14000);
      expect(snap.today.baseDaily).toBe(1000);
      expect(snap.today.allowance).toBe(1000);
      expect(snap.today.spent).toBe(1500);
      expect(snap.today.varianceVsAllowancePct).toBe(50);
      expect(snap.totals.remaining).toBe(12500);
      expect(snap.days.left).toBe(13);

      expect(snap.tomorrow).not.toBeNull();
      // 12500 / 13 = 961.538... -> 961.54
      expect(snap.tomorrow!.allowance).toBe(961.54);
      expect(snap.tomorrow!.pctOfBase).toBe(96.15); // or 96.2% rounded
      expect(snap.status).toBe('ORANGE');
    });

    it('accurately computes Day 2 (700 ETB spent vs 961.54 ETB allowance)', () => {
      const snap = computeSnapshot({
        planId,
        asOfDate: '2026-10-02',
        budget: 14000,
        totalDays: 14,
        dayIndex: 2,
        spentByDay: [1500, 700],
        rolloverMode: 'SPREAD_EVENLY',
      });

      expect(snap.today.baseDaily).toBe(1000);
      expect(snap.today.allowance).toBe(961.54);
      expect(snap.today.spent).toBe(700);
      // ((700 - 961.54) / 961.54) * 100 = -27.2000...
      expect(snap.today.varianceVsAllowancePct).toBeCloseTo(-27.2, 1);
      expect(snap.totals.spent).toBe(2200);
      expect(snap.totals.remaining).toBe(11800);
      expect(snap.days.left).toBe(12);

      expect(snap.tomorrow).not.toBeNull();
      // 11800 / 12 = 983.333... -> 983.33
      expect(snap.tomorrow!.allowance).toBe(983.33);
      expect(snap.tomorrow!.pctOfBase).toBeCloseTo(98.3, 1);
    });

    it('accurately computes Day 3 (1200 ETB spent vs 983.33 ETB allowance)', () => {
      const snap = computeSnapshot({
        planId,
        asOfDate: '2026-10-03',
        budget: 14000,
        totalDays: 14,
        dayIndex: 3,
        spentByDay: [1500, 700, 1200],
        rolloverMode: 'SPREAD_EVENLY',
      });

      expect(snap.today.allowance).toBe(983.33);
      expect(snap.today.spent).toBe(1200);
      // ((1200 - 983.33) / 983.33) * 100 = +22.03%
      expect(snap.today.varianceVsAllowancePct).toBeCloseTo(22.0, 1);
      expect(snap.totals.spent).toBe(3400);
      expect(snap.totals.remaining).toBe(10600);
      expect(snap.days.left).toBe(11);

      expect(snap.tomorrow).not.toBeNull();
      // 10600 / 11 = 963.636... -> 963.64
      expect(snap.tomorrow!.allowance).toBe(963.64);
      expect(snap.tomorrow!.pctOfBase).toBeCloseTo(96.4, 1);

      // Verify Weekly view
      expect(snap.weeks.length).toBe(2);
      const week1 = snap.weeks[0];
      const week2 = snap.weeks[1];

      expect(week1.baseTarget).toBe(7000);
      expect(week1.spent).toBe(3400);
      // Adjusted target week 1: 3400 + (4 * 963.64) = 7254.56
      expect(week1.adjustedTarget).toBeCloseTo(7254.56, 1);

      expect(week2.baseTarget).toBe(7000);
      // Adjusted target week 2: 7 * 963.64 = 6745.48
      expect(week2.adjustedTarget).toBeCloseTo(6745.48, 1);

      // Invariant: sum of adjusted targets equals flexible budget (14000)
      const totalAdjusted = week1.adjustedTarget + week2.adjustedTarget;
      expect(totalAdjusted).toBeCloseTo(14000, 0);
    });
  });

  describe('Deductions: Fixed Expenses, Emergency Reserve, Saving Goal', () => {
    it('correctly deducts fixed expenses and emergency reserves from flexible pool', () => {
      // 20000 budget, 4000 fixed, 10% reserve (2000), 1000 saving goal -> Flexible = 13000
      const snap = computeSnapshot({
        planId,
        asOfDate: '2026-10-01',
        budget: 20000,
        fixedTotal: 4000,
        reservePercent: 10,
        savingGoal: 1000,
        totalDays: 26,
        dayIndex: 1,
        spentByDay: [500],
      });

      expect(snap.totals.fixed).toBe(4000);
      expect(snap.totals.reserve).toBe(2000);
      expect(snap.totals.flexible).toBe(13000);
      expect(snap.today.baseDaily).toBe(500); // 13000 / 26 = 500
      expect(snap.today.allowance).toBe(500);
      expect(snap.today.spent).toBe(500);
      expect(snap.totals.remaining).toBe(12500);
    });
  });

  describe('Rollover Strategies Comparison', () => {
    it('NEXT_DAY mode: day 2 absorbs day 1 variance entirely', () => {
      // Base daily is 1000. Day 1 spent 1400 (+400 over).
      // On NEXT_DAY mode, tomorrow (day 2) should absorb -400 -> allowance = 600.
      const snapDay1 = computeSnapshot({
        planId,
        asOfDate: '2026-10-01',
        budget: 10000,
        totalDays: 10,
        dayIndex: 1,
        spentByDay: [1400],
        rolloverMode: 'NEXT_DAY',
      });

      expect(snapDay1.tomorrow!.allowance).toBe(600);

      // On Day 2, allowanceToday is 600
      const snapDay2 = computeSnapshot({
        planId,
        asOfDate: '2026-10-02',
        budget: 10000,
        totalDays: 10,
        dayIndex: 2,
        spentByDay: [1400, 600],
        rolloverMode: 'NEXT_DAY',
      });

      expect(snapDay2.today.allowance).toBe(600);
      // Day 2 was on target (600 vs 600), so day 3 resets back to base 1000
      expect(snapDay2.tomorrow!.allowance).toBe(1000);
    });

    it('WEEK_ONLY mode: resets target to baseDaily at week boundary', () => {
      // Day 7 is end of week 1. Next day (Day 8) starts week 2 fresh.
      const snapDay7 = computeSnapshot({
        planId,
        asOfDate: '2026-10-07',
        budget: 14000,
        totalDays: 14,
        dayIndex: 7,
        spentByDay: [1500, 1500, 1000, 1000, 1000, 1000, 1000],
        rolloverMode: 'WEEK_ONLY',
      });

      // Even though week 1 overspent by 1000 ETB, Day 8 begins week 2 at baseDaily (1000)
      expect(snapDay7.tomorrow!.allowance).toBe(1000);
    });

    it('TO_SAVINGS mode: underspending does not inflate next day allowance', () => {
      // Base is 1000. Day 1 spent only 200 (underspend of 800).
      // TO_SAVINGS keeps tomorrow at baseDaily (1000) rather than raising it.
      const snap = computeSnapshot({
        planId,
        asOfDate: '2026-10-01',
        budget: 10000,
        totalDays: 10,
        dayIndex: 1,
        spentByDay: [200],
        rolloverMode: 'TO_SAVINGS',
      });

      expect(snap.tomorrow!.allowance).toBe(1000);
    });
  });

  describe('Edge Cases', () => {
    it('handles last day of plan (d = N)', () => {
      const snap = computeSnapshot({
        planId,
        asOfDate: '2026-10-14',
        budget: 14000,
        totalDays: 14,
        dayIndex: 14,
        spentByDay: new Array(14).fill(1000),
      });

      expect(snap.days.left).toBe(0);
      expect(snap.tomorrow).toBeNull();
      expect(snap.totals.remaining).toBe(0);
    });

    it('handles budget exhausted before plan end', () => {
      // 5000 budget exhausted on day 2 of 10
      const snap = computeSnapshot({
        planId,
        asOfDate: '2026-10-02',
        budget: 5000,
        totalDays: 10,
        dayIndex: 2,
        spentByDay: [3000, 2500], // Spent 5500
      });

      expect(snap.totals.remaining).toBe(-500);
      expect(snap.status).toBe('RED');
      expect(snap.tomorrow!.allowance).toBe(0);
      expect(snap.pace.daysUntilBroke).toBe(0);
    });

    it('calculates streak of compliant days', () => {
      // Base daily = 1000. Days 1, 2, 3 spent <= 1050 (streak = 3).
      // Day 4 spent 1500 (streak reset). Day 5 spent 800 (streak = 1).
      const snap = computeSnapshot({
        planId,
        asOfDate: '2026-10-05',
        budget: 10000,
        totalDays: 10,
        dayIndex: 5,
        spentByDay: [900, 950, 1000, 1500, 800],
      });

      expect(snap.streak).toBe(1);
    });
  });

  describe('Scenario Simulator', () => {
    it('simulates safe spend scenario', () => {
      const sim = simulateScenario({
        flexibleBudget: 14000,
        totalDays: 14,
        currentDay: 4,
        spentTotal: 4000,
        proposedDailySpend: 800, // 800 * 10 = 8000 -> Total = 12000
      });

      expect(sim.projectedTotal).toBe(12000);
      expect(sim.projectedDiff).toBe(-2000); // 2000 savings
      expect(sim.status).toBe('SAFE');
      expect(sim.daysUntilExhausted).toBe(12.5);
    });

    it('simulates deficit spend scenario', () => {
      const sim = simulateScenario({
        flexibleBudget: 14000,
        totalDays: 14,
        currentDay: 4,
        spentTotal: 4000,
        proposedDailySpend: 1500, // 1500 * 10 = 15000 -> Total = 19000
      });

      expect(sim.projectedTotal).toBe(19000);
      expect(sim.projectedDiff).toBe(5000); // 5000 overspend
      expect(sim.status).toBe('DEFICIT');
      expect(sim.daysUntilExhausted).toBeCloseTo(6.67, 1);
    });
  });

  describe('Timezone formatting', () => {
    it('correctly maps dates to Africa/Addis_Ababa (+03:00)', () => {
      // 2026-10-10 21:30:00 UTC is 2026-10-11 00:30:00 in Addis Ababa
      const utcDate = new Date('2026-10-10T21:30:00.000Z');
      const addisStr = toAddisAbabaDateString(utcDate);
      expect(addisStr).toBe('2026-10-11');
    });
  });
});
