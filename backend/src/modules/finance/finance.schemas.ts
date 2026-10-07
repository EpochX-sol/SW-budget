import { z } from 'zod';

// ─────────────────────────────────────────────────────────────
// Accounts
// ─────────────────────────────────────────────────────────────
export const createAccountSchema = z.object({
  id: z.string().uuid().optional(),
  provider: z.enum(['CBE', 'TELEBIRR', 'ABYSSINIA', 'CASH', 'OTHER']),
  name: z.string().min(1).max(100),
  account_mask: z.string().max(20).optional(),
  last_known_balance: z.coerce.number().optional(),
  is_savings: z.boolean().default(false),
});

export const updateAccountSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  account_mask: z.string().max(20).optional(),
  last_known_balance: z.coerce.number().optional(),
  is_savings: z.boolean().optional(),
});

// ─────────────────────────────────────────────────────────────
// Categories
// ─────────────────────────────────────────────────────────────
export const createCategorySchema = z.object({
  id: z.string().uuid().optional(),
  name: z.string().min(1).max(100),
  icon: z.string().min(1).max(50),
  color_hex: z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'Must be a valid hex color (e.g. #10B981)'),
});

export const updateCategorySchema = z.object({
  name: z.string().min(1).max(100).optional(),
  icon: z.string().min(1).max(50).optional(),
  color_hex: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
});

// ─────────────────────────────────────────────────────────────
// Limits
// ─────────────────────────────────────────────────────────────
export const createLimitSchema = z.object({
  id: z.string().uuid().optional(),
  scope_type: z.enum(['overall', 'category', 'account']).default('overall'),
  scope_id: z.string().uuid().optional(),
  period_type: z.enum(['daily', 'weekly', 'monthly', 'custom']),
  start_date: z.string().optional(), // YYYY-MM-DD
  end_date: z.string().optional(),
  amount: z.coerce.number().positive('Limit amount must be greater than 0'),
  mode: z.enum(['soft', 'hard']).default('soft'),
  rollover: z.boolean().default(false),
  alert_thresholds: z.array(z.number().int()).default([50, 80, 100]),
  active: z.boolean().default(true),
});

export const updateLimitSchema = z.object({
  amount: z.coerce.number().positive().optional(),
  mode: z.enum(['soft', 'hard']).optional(),
  rollover: z.boolean().optional(),
  alert_thresholds: z.array(z.number().int()).optional(),
  active: z.boolean().optional(),
});

// ─────────────────────────────────────────────────────────────
// Saving Plans
// ─────────────────────────────────────────────────────────────
export const createSavingPlanSchema = z.object({
  id: z.string().uuid().optional(),
  name: z.string().min(1).max(100),
  period_type: z.enum(['weekly', 'monthly', 'yearly', 'custom']),
  target_amount: z.coerce.number().positive('Target amount must be greater than 0'),
  start_date: z.string(), // YYYY-MM-DD
  end_date: z.string().optional(),
  rule_type: z.enum(['fixed', 'percent_of_income', 'round_up', 'leftover']),
  rule_value: z.coerce.number().optional(),
  linked_account_id: z.string().uuid().optional(),
  priority: z.number().int().min(1).max(5).default(3),
  status: z.enum(['active', 'completed', 'paused']).default('active'),
});

export const updateSavingPlanSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  target_amount: z.coerce.number().positive().optional(),
  end_date: z.string().optional(),
  rule_type: z.enum(['fixed', 'percent_of_income', 'round_up', 'leftover']).optional(),
  rule_value: z.coerce.number().optional(),
  priority: z.number().int().min(1).max(5).optional(),
  status: z.enum(['active', 'completed', 'paused']).optional(),
});

// ─────────────────────────────────────────────────────────────
// Transactions Query
// ─────────────────────────────────────────────────────────────
export const transactionQuerySchema = z.object({
  from: z.string().optional(),
  to: z.string().optional(),
  account_id: z.string().uuid().optional(),
  category_id: z.string().uuid().optional(),
  type: z.string().optional(),
  q: z.string().optional(),
  limit: z.coerce.number().min(1).max(500).default(50),
  offset: z.coerce.number().min(0).default(0),
});

export const updateTransactionSchema = z.object({
  category_id: z.string().uuid().nullable().optional(),
  note: z.string().max(500).nullable().optional(),
  needs_review: z.boolean().optional(),
  user_edited_fields: z.array(z.string()).optional(),
});

export const createTransactionSchema = z.object({
  id: z.string().uuid().optional(),
  account_id: z.string().uuid(),
  category_id: z.string().uuid().optional().nullable(),
  type: z.enum(['income', 'expense', 'transfer']).default('expense'),
  amount: z.coerce.number(),
  balance_after: z.coerce.number().optional().nullable(),
  counterparty: z.string().max(200).optional().nullable(),
  reference: z.string().max(100).optional().nullable(),
  note: z.string().max(500).optional().nullable(),
  occurred_at: z.string().optional(),
  source: z.enum(['sms', 'manual', 'import', 'receipt_ocr']).default('manual'),
  parse_confidence: z.number().optional().nullable(),
  is_internal_transfer: z.boolean().default(false),
  dedupe_key: z.string().optional().nullable(),
  needs_review: z.boolean().default(false),
});

// ─────────────────────────────────────────────────────────────
// Exported Inferred Types
// ─────────────────────────────────────────────────────────────
export type CreateAccountInput = z.infer<typeof createAccountSchema>;
export type UpdateAccountInput = z.infer<typeof updateAccountSchema>;

export type CreateCategoryInput = z.infer<typeof createCategorySchema>;
export type UpdateCategoryInput = z.infer<typeof updateCategorySchema>;

export type CreateLimitInput = z.infer<typeof createLimitSchema>;
export type UpdateLimitInput = z.infer<typeof updateLimitSchema>;

export type CreateSavingPlanInput = z.infer<typeof createSavingPlanSchema>;
export type UpdateSavingPlanInput = z.infer<typeof updateSavingPlanSchema>;

export type TransactionQueryInput = z.infer<typeof transactionQuerySchema>;
export type UpdateTransactionInput = z.infer<typeof updateTransactionSchema>;
export type CreateTransactionInput = z.infer<typeof createTransactionSchema>;

