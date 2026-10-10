import { z } from 'zod';

export const createPlanSchema = z.object({
  name: z.string().min(1).default('My Spending Plan'),
  total_amount: z.coerce.number().positive(),
  start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'YYYY-MM-DD required'),
  end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'YYYY-MM-DD required'),
  rollover_mode: z.enum(['SPREAD_EVENLY', 'NEXT_DAY', 'WEEK_ONLY', 'TO_SAVINGS']).default('SPREAD_EVENLY'),
  reserve_percent: z.coerce.number().min(0).max(100).default(0),
  saving_goal: z.coerce.number().min(0).default(0),
  min_daily_floor: z.coerce.number().min(0).default(0),
  day_weights: z.record(z.number()).optional(),
  fixed_expenses: z.array(z.object({
    title: z.string().min(1),
    amount: z.coerce.number().positive(),
    due_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    paid: z.boolean().default(false),
  })).optional(),
  category_limits: z.array(z.object({
    category: z.string().min(1),
    amount: z.coerce.number().positive(),
  })).optional(),
});

export const updatePlanSchema = z.object({
  name: z.string().min(1).optional(),
  total_amount: z.coerce.number().positive().optional(),
  start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  rollover_mode: z.enum(['SPREAD_EVENLY', 'NEXT_DAY', 'WEEK_ONLY', 'TO_SAVINGS']).optional(),
  reserve_percent: z.coerce.number().min(0).max(100).optional(),
  saving_goal: z.coerce.number().min(0).optional(),
  min_daily_floor: z.coerce.number().min(0).optional(),
  day_weights: z.record(z.number()).optional(),
  active: z.boolean().optional(),
});

export const simulatePlanSchema = z.object({
  proposed_daily_spend: z.coerce.number().min(0),
});

export const createFixedExpenseSchema = z.object({
  title: z.string().min(1),
  amount: z.coerce.number().positive(),
  due_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  paid: z.boolean().default(false),
});

export type CreatePlanInput = z.infer<typeof createPlanSchema>;
export type UpdatePlanInput = z.infer<typeof updatePlanSchema>;
export type SimulatePlanInput = z.infer<typeof simulatePlanSchema>;
export type CreateFixedExpenseInput = z.infer<typeof createFixedExpenseSchema>;
