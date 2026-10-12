import { z } from 'zod';

export const createPlanSchema = z.object({
  name: z.string().min(1).default('My Spending Plan'),
  total_amount: z.coerce.number().positive().optional(),
  spending_limit: z.coerce.number().positive().optional(),
  period_type: z.enum(['daily', 'weekly', 'monthly', 'yearly', 'custom']).default('monthly'),
  start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'YYYY-MM-DD required'),
  end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'YYYY-MM-DD required'),
  monthly_start_day: z.coerce.number().min(1).max(28).default(1),
  rollover_mode: z.enum(['SPREAD_EVENLY', 'NEXT_DAY', 'WEEK_ONLY', 'TO_SAVINGS']).default('SPREAD_EVENLY'),
  reserve_type: z.enum(['none', 'fixed', 'percentage']).default('none'),
  reserve_value: z.coerce.number().min(0).default(0),
  reserve_percent: z.coerce.number().min(0).max(100).default(0),
  saving_goal: z.coerce.number().min(0).default(0),
  min_daily_floor: z.coerce.number().min(0).default(0),
  day_weights: z.record(z.number()).optional(),
  watched_bank_ids: z.array(z.string()).nullable().optional(),
  count_fees: z.boolean().default(true),
  count_withdrawals: z.boolean().default(true),
  reaction_mode: z.enum(['adaptive', 'fixed']).default('adaptive'),
  morning_brief_enabled: z.boolean().default(true),
  morning_brief_time: z.string().default('07:30'),
  daily_report_enabled: z.boolean().default(true),
  daily_report_time: z.string().default('21:00'),
  skip_empty_days: z.boolean().default(false),
  alert_thresholds: z.array(z.number()).default([50, 80, 100]),
  reserve_alert_enabled: z.boolean().default(true),
  fixed_expenses: z.array(z.object({
    title: z.string().min(1).optional(),
    name: z.string().min(1).optional(),
    amount: z.coerce.number().positive(),
    due_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    linked_category_id: z.string().uuid().nullable().optional(),
    reminder_enabled: z.boolean().default(true),
    status: z.enum(['expected', 'paid']).default('expected'),
    paid: z.boolean().default(false),
  })).optional(),
  expected_expenses: z.array(z.object({
    name: z.string().min(1),
    amount: z.coerce.number().positive(),
    due_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    linked_category_id: z.string().uuid().nullable().optional(),
    reminder_enabled: z.boolean().default(true),
    status: z.enum(['expected', 'paid']).default('expected'),
  })).optional(),
  category_limits: z.array(z.object({
    category: z.string().min(1),
    amount: z.coerce.number().positive(),
  })).optional(),
});

export const updatePlanSchema = z.object({
  name: z.string().min(1).optional(),
  total_amount: z.coerce.number().positive().optional(),
  spending_limit: z.coerce.number().positive().optional(),
  period_type: z.enum(['daily', 'weekly', 'monthly', 'yearly', 'custom']).optional(),
  start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  monthly_start_day: z.coerce.number().min(1).max(28).optional(),
  rollover_mode: z.enum(['SPREAD_EVENLY', 'NEXT_DAY', 'WEEK_ONLY', 'TO_SAVINGS']).optional(),
  reserve_type: z.enum(['none', 'fixed', 'percentage']).optional(),
  reserve_value: z.coerce.number().min(0).optional(),
  reserve_percent: z.coerce.number().min(0).max(100).optional(),
  saving_goal: z.coerce.number().min(0).optional(),
  min_daily_floor: z.coerce.number().min(0).optional(),
  day_weights: z.record(z.number()).optional(),
  watched_bank_ids: z.array(z.string()).nullable().optional(),
  count_fees: z.boolean().optional(),
  count_withdrawals: z.boolean().optional(),
  reaction_mode: z.enum(['adaptive', 'fixed']).optional(),
  active: z.boolean().optional(),
  status: z.enum(['active', 'paused', 'finished', 'archived']).optional(),
  morning_brief_enabled: z.boolean().optional(),
  morning_brief_time: z.string().optional(),
  daily_report_enabled: z.boolean().optional(),
  daily_report_time: z.string().optional(),
  skip_empty_days: z.boolean().optional(),
  alert_thresholds: z.array(z.number()).optional(),
  reserve_alert_enabled: z.boolean().optional(),
});

export const simulatePlanSchema = z.object({
  proposed_daily_spend: z.coerce.number().min(0),
});

export const createFixedExpenseSchema = z.object({
  title: z.string().min(1).optional(),
  name: z.string().min(1).optional(),
  amount: z.coerce.number().positive(),
  due_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  linked_category_id: z.string().uuid().nullable().optional(),
  reminder_enabled: z.boolean().default(true),
  paid: z.boolean().default(false),
  status: z.enum(['expected', 'paid']).default('expected'),
});

export const updateFixedExpenseSchema = z.object({
  name: z.string().min(1).optional(),
  title: z.string().min(1).optional(),
  amount: z.coerce.number().positive().optional(),
  due_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  linked_category_id: z.string().uuid().nullable().optional(),
  reminder_enabled: z.boolean().optional(),
  paid: z.boolean().optional(),
  status: z.enum(['expected', 'paid']).optional(),
});

export type CreatePlanInput = z.infer<typeof createPlanSchema>;
export type UpdatePlanInput = z.infer<typeof updatePlanSchema>;
export type SimulatePlanInput = z.infer<typeof simulatePlanSchema>;
export type CreateFixedExpenseInput = z.infer<typeof createFixedExpenseSchema>;
export type UpdateFixedExpenseInput = z.infer<typeof updateFixedExpenseSchema>;
