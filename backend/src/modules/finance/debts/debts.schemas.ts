import { z } from 'zod';

export const createDebtSchema = z.object({
  person_name: z.string().min(1),
  phone_number: z.string().optional(),
  type: z.enum(['lent', 'borrowed']),
  initial_amount: z.coerce.number().positive(),
  due_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  note: z.string().optional(),
});

export const updateDebtStatusSchema = z.object({
  status: z.enum(['active', 'settled', 'forgiven']),
});

export const recordRepaymentSchema = z.object({
  amount: z.coerce.number().positive(),
  txn_id: z.string().uuid().optional(),
  repaid_at: z.string().optional(),
  note: z.string().optional(),
});

export type CreateDebtInput = z.infer<typeof createDebtSchema>;
export type UpdateDebtStatusInput = z.infer<typeof updateDebtStatusSchema>;
export type RecordRepaymentInput = z.infer<typeof recordRepaymentSchema>;
