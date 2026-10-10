import { z } from 'zod';

export const createReimbursementSchema = z.object({
  expense_txn_id: z.string().uuid(),
  credit_txn_id: z.string().uuid(),
  amount: z.coerce.number().positive(),
  note: z.string().optional(),
});

export type CreateReimbursementInput = z.infer<typeof createReimbursementSchema>;
