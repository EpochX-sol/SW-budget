import { prisma } from '../../../db/prisma.js';
import { Prisma } from '@prisma/client';
import { CreateReimbursementInput } from './reimbursement.schemas.js';
import { spendingPlanService } from '../spending-plan/spending-plan.service.js';

export class ReimbursementService {
  /**
   * Links a credit transaction to a prior expense transaction.
   */
  async createReimbursement(userId: string, input: CreateReimbursementInput) {
    const { expense_txn_id, credit_txn_id, amount, note } = input;

    // 1. Fetch expense transaction
    const expenseTxn = await prisma.transaction.findFirst({
      where: { id: expense_txn_id, userId, deletedAt: null },
      include: {
        expenseReimbursements: {
          where: { deletedAt: null },
        },
      },
    });

    if (!expenseTxn) {
      const err: any = new Error('Expense transaction not found');
      err.statusCode = 404;
      throw err;
    }

    if (expenseTxn.type !== 'expense') {
      const err: any = new Error('Original transaction must be an expense');
      err.statusCode = 400;
      throw err;
    }

    // 2. Fetch credit transaction
    const creditTxn = await prisma.transaction.findFirst({
      where: { id: credit_txn_id, userId, deletedAt: null },
    });

    if (!creditTxn) {
      const err: any = new Error('Credit transaction not found');
      err.statusCode = 404;
      throw err;
    }

    // 3. Verify unreimbursed portion
    const alreadyReimbursed = expenseTxn.expenseReimbursements.reduce(
      (sum, r) => sum + Number(r.amount),
      0
    );
    const unreimbursed = Number(expenseTxn.amount) - alreadyReimbursed;

    if (amount > unreimbursed + 0.001) {
      const err: any = new Error(
        `Reimbursement amount (${amount} ETB) exceeds remaining unreimbursed amount (${unreimbursed} ETB)`
      );
      err.statusCode = 400;
      throw err;
    }

    // 4. Allocate change_seq
    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });

    const reimbursement = await prisma.reimbursement.create({
      data: {
        userId,
        expenseTxnId: expense_txn_id,
        creditTxnId: credit_txn_id,
        amount: new Prisma.Decimal(amount),
        note: note || null,
        changeSeq: syncState.seq,
      },
    });

    // 5. Invalidate active plan snapshot if exists
    const active = await prisma.budgetPlan.findFirst({
      where: { userId, active: true, deletedAt: null },
    });
    if (active) {
      await spendingPlanService.recomputeSnapshot(active.id, userId);
    }

    return reimbursement;
  }

  /**
   * Lists all reimbursements for user.
   */
  async listReimbursements(userId: string) {
    return prisma.reimbursement.findMany({
      where: { userId, deletedAt: null },
      include: {
        expenseTxn: {
          select: {
            id: true,
            amount: true,
            counterparty: true,
            occurredAt: true,
          },
        },
        creditTxn: {
          select: {
            id: true,
            amount: true,
            counterparty: true,
            occurredAt: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  /**
   * Soft deletes a reimbursement.
   */
  async deleteReimbursement(userId: string, id: string) {
    const existing = await prisma.reimbursement.findFirst({
      where: { id, userId, deletedAt: null },
    });

    if (!existing) {
      const err: any = new Error('Reimbursement not found');
      err.statusCode = 404;
      throw err;
    }

    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });

    await prisma.reimbursement.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        changeSeq: syncState.seq,
      },
    });

    // Invalidate active plan snapshot if exists
    const active = await prisma.budgetPlan.findFirst({
      where: { userId, active: true, deletedAt: null },
    });
    if (active) {
      await spendingPlanService.recomputeSnapshot(active.id, userId);
    }

    return { success: true };
  }

  /**
   * Queries reimbursements for AI Coach tool.
   */
  async queryReimbursements(userId: string, _args: any) {
    const list = await this.listReimbursements(userId);
    return {
      total_reimbursements_count: list.length,
      reimbursements: list.map((r) => ({
        id: r.id,
        amount: Number(r.amount),
        counterparty: r.creditTxn.counterparty || r.expenseTxn.counterparty || 'Unknown',
        original_expense: Number(r.expenseTxn.amount),
        note: r.note,
        created_at: r.createdAt.toISOString(),
      })),
    };
  }
}

export const reimbursementService = new ReimbursementService();
