import { prisma } from '../../db/prisma.js';
import { financeRepository, FinanceRepository } from './finance.repository.js';
import {
  CreateAccountInput,
  UpdateAccountInput,
  CreateCategoryInput,
  UpdateCategoryInput,
  CreateLimitInput,
  UpdateLimitInput,
  CreateSavingPlanInput,
  UpdateSavingPlanInput,
  TransactionQueryInput,
  UpdateTransactionInput,
  CreateTransactionInput,
} from './finance.schemas.js';

export class FinanceService {
  constructor(private repo: FinanceRepository = financeRepository) {}

  private async getNextSeq(userId: string): Promise<bigint> {
    const updated = await prisma.userSyncState.update({
      where: { userId },
      data: {
        seq: { increment: 1 },
      },
    });
    return updated.seq;
  }

  // Accounts
  async getAccounts(userId: string) {
    return this.repo.getAccounts(userId);
  }

  async createAccount(userId: string, data: CreateAccountInput) {
    const seq = await this.getNextSeq(userId);
    return this.repo.createAccount(userId, data, seq);
  }

  async updateAccount(userId: string, id: string, data: UpdateAccountInput) {
    const seq = await this.getNextSeq(userId);
    return this.repo.updateAccount(userId, id, data, seq);
  }

  async deleteAccount(userId: string, id: string) {
    const seq = await this.getNextSeq(userId);
    return this.repo.deleteAccount(userId, id, seq);
  }

  // Categories
  async getCategories(userId: string) {
    return this.repo.getCategories(userId);
  }

  async createCategory(userId: string, data: CreateCategoryInput) {
    const seq = await this.getNextSeq(userId);
    return this.repo.createCategory(userId, data, seq);
  }

  async updateCategory(userId: string, id: string, data: UpdateCategoryInput) {
    const seq = await this.getNextSeq(userId);
    return this.repo.updateCategory(userId, id, data, seq);
  }

  async deleteCategory(userId: string, id: string) {
    const seq = await this.getNextSeq(userId);
    return this.repo.deleteCategory(userId, id, seq);
  }

  // Limits
  async getLimits(userId: string) {
    return this.repo.getLimits(userId);
  }

  async createLimit(userId: string, data: CreateLimitInput) {
    const seq = await this.getNextSeq(userId);
    return this.repo.createLimit(userId, data, seq);
  }

  async updateLimit(userId: string, id: string, data: UpdateLimitInput) {
    const seq = await this.getNextSeq(userId);
    return this.repo.updateLimit(userId, id, data, seq);
  }

  async deleteLimit(userId: string, id: string) {
    const seq = await this.getNextSeq(userId);
    return this.repo.deleteLimit(userId, id, seq);
  }

  // Saving Plans
  async getSavingPlans(userId: string) {
    return this.repo.getSavingPlans(userId);
  }

  async createSavingPlan(userId: string, data: CreateSavingPlanInput) {
    const seq = await this.getNextSeq(userId);
    return this.repo.createSavingPlan(userId, data, seq);
  }

  async updateSavingPlan(userId: string, id: string, data: UpdateSavingPlanInput) {
    const seq = await this.getNextSeq(userId);
    return this.repo.updateSavingPlan(userId, id, data, seq);
  }

  async deleteSavingPlan(userId: string, id: string) {
    const seq = await this.getNextSeq(userId);
    return this.repo.deleteSavingPlan(userId, id, seq);
  }

  // Transactions
  async getTransactions(userId: string, filter: TransactionQueryInput) {
    return this.repo.getTransactions(userId, filter);
  }

  async createTransaction(userId: string, data: CreateTransactionInput) {
    const seq = await this.getNextSeq(userId);
    return this.repo.createTransaction(userId, data, seq);
  }

  async updateTransaction(userId: string, id: string, data: UpdateTransactionInput) {
    const seq = await this.getNextSeq(userId);
    return this.repo.updateTransaction(userId, id, data, seq);
  }

  async deleteTransaction(userId: string, id: string) {
    const seq = await this.getNextSeq(userId);
    return this.repo.deleteTransaction(userId, id, seq);
  }
}

export const financeService = new FinanceService();

