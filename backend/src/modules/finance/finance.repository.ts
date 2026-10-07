import { prisma } from '../../db/prisma.js';
import { Prisma } from '@prisma/client';
import crypto from 'node:crypto';
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

export class FinanceRepository {
  // Accounts
  async getAccounts(userId: string) {
    return prisma.account.findMany({
      where: { userId, deletedAt: null },
      orderBy: { createdAt: 'asc' },
    });
  }

  async createAccount(userId: string, data: CreateAccountInput, changeSeq: bigint) {
    return prisma.account.create({
      data: {
        id: data.id || crypto.randomUUID(),
        userId,
        provider: data.provider,
        name: data.name,
        accountMask: data.account_mask,
        lastKnownBalance: data.last_known_balance != null ? new Prisma.Decimal(data.last_known_balance) : null,
        isSavings: data.is_savings || false,
        changeSeq,
      },
    });
  }

  async updateAccount(userId: string, id: string, data: UpdateAccountInput, changeSeq: bigint) {
    return prisma.account.updateMany({
      where: { id, userId, deletedAt: null },
      data: {
        name: data.name,
        accountMask: data.account_mask,
        lastKnownBalance: data.last_known_balance != null ? new Prisma.Decimal(data.last_known_balance) : undefined,
        isSavings: data.is_savings,
        changeSeq,
        updatedAt: new Date(),
      },
    });
  }

  async deleteAccount(userId: string, id: string, changeSeq: bigint) {
    return prisma.account.updateMany({
      where: { id, userId, deletedAt: null },
      data: {
        deletedAt: new Date(),
        changeSeq,
      },
    });
  }

  // Categories
  async getCategories(userId: string) {
    return prisma.category.findMany({
      where: {
        OR: [{ userId }, { isSystem: true }],
        deletedAt: null,
      },
      orderBy: [{ isSystem: 'desc' }, { name: 'asc' }],
    });
  }

  async createCategory(userId: string, data: CreateCategoryInput, changeSeq: bigint) {
    return prisma.category.create({
      data: {
        id: data.id || crypto.randomUUID(),
        userId,
        name: data.name,
        icon: data.icon,
        colorHex: data.color_hex,
        isSystem: false,
        changeSeq,
      },
    });
  }

  async updateCategory(userId: string, id: string, data: UpdateCategoryInput, changeSeq: bigint) {
    return prisma.category.updateMany({
      where: { id, userId, isSystem: false, deletedAt: null },
      data: {
        name: data.name,
        icon: data.icon,
        colorHex: data.color_hex,
        changeSeq,
      },
    });
  }

  async deleteCategory(userId: string, id: string, changeSeq: bigint) {
    return prisma.category.updateMany({
      where: { id, userId, isSystem: false, deletedAt: null },
      data: {
        deletedAt: new Date(),
        changeSeq,
      },
    });
  }

  // Limits
  async getLimits(userId: string) {
    return prisma.limit.findMany({
      where: { userId, deletedAt: null },
      orderBy: { createdAt: 'desc' },
    });
  }

  async createLimit(userId: string, data: CreateLimitInput, changeSeq: bigint) {
    return prisma.limit.create({
      data: {
        id: data.id || crypto.randomUUID(),
        userId,
        scopeType: data.scope_type,
        scopeId: data.scope_id,
        periodType: data.period_type,
        startDate: data.start_date ? new Date(data.start_date) : null,
        endDate: data.end_date ? new Date(data.end_date) : null,
        amount: new Prisma.Decimal(data.amount),
        mode: data.mode,
        rollover: data.rollover,
        alertThresholds: data.alert_thresholds,
        active: data.active,
        changeSeq,
      },
    });
  }

  async updateLimit(userId: string, id: string, data: UpdateLimitInput, changeSeq: bigint) {
    return prisma.limit.updateMany({
      where: { id, userId, deletedAt: null },
      data: {
        amount: data.amount != null ? new Prisma.Decimal(data.amount) : undefined,
        mode: data.mode,
        rollover: data.rollover,
        alertThresholds: data.alert_thresholds,
        active: data.active,
        changeSeq,
        updatedAt: new Date(),
      },
    });
  }

  async deleteLimit(userId: string, id: string, changeSeq: bigint) {
    return prisma.limit.updateMany({
      where: { id, userId, deletedAt: null },
      data: {
        deletedAt: new Date(),
        changeSeq,
      },
    });
  }

  // Saving Plans
  async getSavingPlans(userId: string) {
    return prisma.savingPlan.findMany({
      where: { userId, deletedAt: null },
      include: { linkedAccount: true },
      orderBy: { priority: 'asc' },
    });
  }

  async createSavingPlan(userId: string, data: CreateSavingPlanInput, changeSeq: bigint) {
    return prisma.savingPlan.create({
      data: {
        id: data.id || crypto.randomUUID(),
        userId,
        name: data.name,
        periodType: data.period_type,
        targetAmount: new Prisma.Decimal(data.target_amount),
        startDate: new Date(data.start_date),
        endDate: data.end_date ? new Date(data.end_date) : null,
        ruleType: data.rule_type,
        ruleValue: data.rule_value != null ? new Prisma.Decimal(data.rule_value) : null,
        linkedAccountId: data.linked_account_id,
        priority: data.priority,
        status: data.status,
        changeSeq,
      },
    });
  }

  async updateSavingPlan(userId: string, id: string, data: UpdateSavingPlanInput, changeSeq: bigint) {
    return prisma.savingPlan.updateMany({
      where: { id, userId, deletedAt: null },
      data: {
        name: data.name,
        targetAmount: data.target_amount != null ? new Prisma.Decimal(data.target_amount) : undefined,
        endDate: data.end_date ? new Date(data.end_date) : undefined,
        ruleType: data.rule_type,
        ruleValue: data.rule_value != null ? new Prisma.Decimal(data.rule_value) : undefined,
        priority: data.priority,
        status: data.status,
        changeSeq,
        updatedAt: new Date(),
      },
    });
  }

  async deleteSavingPlan(userId: string, id: string, changeSeq: bigint) {
    return prisma.savingPlan.updateMany({
      where: { id, userId, deletedAt: null },
      data: {
        deletedAt: new Date(),
        changeSeq,
      },
    });
  }

  // Transactions
  async getTransactions(userId: string, filter: TransactionQueryInput) {
    const where: Prisma.TransactionWhereInput = {
      userId,
      deletedAt: null,
    };

    if (filter.from || filter.to) {
      where.occurredAt = {};
      if (filter.from) where.occurredAt.gte = new Date(filter.from);
      if (filter.to) where.occurredAt.lte = new Date(filter.to);
    }
    if (filter.account_id) where.accountId = filter.account_id;
    if (filter.category_id) where.categoryId = filter.category_id;
    if (filter.type) where.type = filter.type;
    if (filter.q) {
      where.OR = [
        { counterparty: { contains: filter.q, mode: 'insensitive' } },
        { reference: { contains: filter.q, mode: 'insensitive' } },
        { note: { contains: filter.q, mode: 'insensitive' } },
      ];
    }

    const [items, total] = await Promise.all([
      prisma.transaction.findMany({
        where,
        include: {
          account: { select: { id: true, name: true, provider: true } },
          category: { select: { id: true, name: true, icon: true, colorHex: true } },
        },
        orderBy: { occurredAt: 'desc' },
        take: filter.limit,
        skip: filter.offset,
      }),
      prisma.transaction.count({ where }),
    ]);

    return { items, total };
  }

  async createTransaction(userId: string, data: CreateTransactionInput, changeSeq: bigint) {
    return prisma.transaction.create({
      data: {
        id: data.id || crypto.randomUUID(),
        userId,
        accountId: data.account_id,
        categoryId: data.category_id || null,
        type: data.type || 'expense',
        amount: new Prisma.Decimal(data.amount),
        balanceAfter: data.balance_after != null ? new Prisma.Decimal(data.balance_after) : null,
        counterparty: data.counterparty || null,
        reference: data.reference || null,
        note: data.note || null,
        occurredAt: data.occurred_at ? new Date(data.occurred_at) : new Date(),
        source: data.source || 'manual',
        parseConfidence: data.parse_confidence != null ? data.parse_confidence : null,
        isInternalTransfer: data.is_internal_transfer || false,
        dedupeKey: data.dedupe_key || `manual_${crypto.randomUUID()}`,
        needsReview: data.needs_review || false,
        changeSeq,
      },
    });
  }

  async updateTransaction(userId: string, id: string, data: UpdateTransactionInput, changeSeq: bigint) {
    return prisma.transaction.updateMany({
      where: { id, userId, deletedAt: null },
      data: {
        categoryId: data.category_id !== undefined ? data.category_id : undefined,
        note: data.note !== undefined ? data.note : undefined,
        needsReview: data.needs_review !== undefined ? data.needs_review : undefined,
        userEditedFields: data.user_edited_fields !== undefined ? data.user_edited_fields : undefined,
        changeSeq,
        updatedAt: new Date(),
      },
    });
  }

  async deleteTransaction(userId: string, id: string, changeSeq: bigint) {
    return prisma.transaction.updateMany({
      where: { id, userId, deletedAt: null },
      data: {
        deletedAt: new Date(),
        changeSeq,
      },
    });
  }
}

export const financeRepository = new FinanceRepository();
