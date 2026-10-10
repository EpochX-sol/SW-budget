import { prisma } from '../../../db/prisma.js';
import { Prisma } from '@prisma/client';
import {
  CreateDebtInput,
  UpdateDebtStatusInput,
  RecordRepaymentInput,
} from './debts.schemas.js';

export class DebtsService {
  /**
   * Lists all loans and debts for user grouped with contact person and repayments.
   */
  async listDebts(userId: string) {
    return prisma.loanDebt.findMany({
      where: { userId, deletedAt: null },
      include: {
        person: true,
        repayments: {
          where: { deletedAt: null },
          orderBy: { repaidAt: 'desc' },
        },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  /**
   * Creates a new loan or debt record.
   */
  async createDebt(userId: string, input: CreateDebtInput) {
    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 2n } },
    });
    const personSeq = syncState.seq - 1n;
    const debtSeq = syncState.seq;

    // Find or create contact person
    let person = await prisma.contactPerson.findFirst({
      where: { userId, name: input.person_name, deletedAt: null },
    });

    if (!person) {
      person = await prisma.contactPerson.create({
        data: {
          userId,
          name: input.person_name,
          phoneNumber: input.phone_number || null,
          changeSeq: personSeq,
        },
      });
    }

    const initialAmount = new Prisma.Decimal(input.initial_amount);
    const debt = await prisma.loanDebt.create({
      data: {
        userId,
        personId: person.id,
        type: input.type,
        initialAmount,
        currentBalance: initialAmount,
        dueDate: input.due_date ? new Date(input.due_date) : null,
        status: 'active',
        note: input.note || null,
        changeSeq: debtSeq,
      },
      include: {
        person: true,
      },
    });

    return debt;
  }

  /**
   * Retrieves a debt by ID.
   */
  async getDebtById(userId: string, debtId: string) {
    const debt = await prisma.loanDebt.findFirst({
      where: { id: debtId, userId, deletedAt: null },
      include: {
        person: true,
        repayments: {
          where: { deletedAt: null },
          orderBy: { repaidAt: 'desc' },
        },
      },
    });

    if (!debt) {
      const err: any = new Error('Debt record not found');
      err.statusCode = 404;
      throw err;
    }

    return debt;
  }

  /**
   * Updates debt status.
   */
  async updateDebtStatus(userId: string, debtId: string, input: UpdateDebtStatusInput) {
    await this.getDebtById(userId, debtId);

    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 1n } },
    });

    return prisma.loanDebt.update({
      where: { id: debtId },
      data: {
        status: input.status,
        changeSeq: syncState.seq,
      },
      include: { person: true },
    });
  }

  /**
   * Records a repayment against a loan or debt.
   */
  async recordRepayment(userId: string, debtId: string, input: RecordRepaymentInput) {
    const debt = await this.getDebtById(userId, debtId);

    const syncState = await prisma.userSyncState.update({
      where: { userId },
      data: { seq: { increment: 2n } },
    });
    const repaymentSeq = syncState.seq - 1n;
    const debtSeq = syncState.seq;

    const repaymentAmount = Number(input.amount);
    const newBalance = Math.max(0, Number(debt.currentBalance) - repaymentAmount);
    const newStatus = newBalance === 0 ? 'settled' : debt.status;

    // Create repayment
    const repayment = await prisma.loanRepayment.create({
      data: {
        userId,
        loanDebtId: debtId,
        txnId: input.txn_id || null,
        amount: new Prisma.Decimal(input.amount),
        repaidAt: input.repaid_at ? new Date(input.repaid_at) : new Date(),
        note: input.note || null,
        changeSeq: repaymentSeq,
      },
    });

    // Update debt current balance
    const updatedDebt = await prisma.loanDebt.update({
      where: { id: debtId },
      data: {
        currentBalance: new Prisma.Decimal(newBalance),
        status: newStatus,
        changeSeq: debtSeq,
      },
      include: { person: true },
    });

    return {
      repayment,
      debt: updatedDebt,
    };
  }

  /**
   * Helper for AI Coach tool queries.
   */
  async queryDebts(userId: string, args: { status?: string; person_name?: string }) {
    const where: any = { userId, deletedAt: null };
    if (args.status && args.status !== 'all') {
      where.status = args.status;
    }
    if (args.person_name) {
      where.person = { name: { contains: args.person_name, mode: 'insensitive' } };
    }

    const debts = await prisma.loanDebt.findMany({
      where,
      include: { person: true },
      orderBy: { createdAt: 'desc' },
    });

    let totalLent = 0;
    let totalBorrowed = 0;

    for (const d of debts) {
      if (d.status === 'active') {
        if (d.type === 'lent') {
          totalLent += Number(d.currentBalance);
        } else {
          totalBorrowed += Number(d.currentBalance);
        }
      }
    }

    return {
      total_lent: totalLent,
      total_borrowed: totalBorrowed,
      debts: debts.map((d) => ({
        id: d.id,
        person: d.person.name,
        type: d.type,
        initial_amount: Number(d.initialAmount),
        balance: Number(d.currentBalance),
        due_date: d.dueDate ? d.dueDate.toISOString().slice(0, 10) : null,
        status: d.status,
        note: d.note,
      })),
    };
  }
}

export const debtsService = new DebtsService();
