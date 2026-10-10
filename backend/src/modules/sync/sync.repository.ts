import { prisma } from '../../db/prisma.js';
import { Prisma } from '@prisma/client';
import { SyncChangeItem } from './sync.schemas.js';

export class SyncRepository {
  async getUserSeq(userId: string): Promise<bigint> {
    const state = await prisma.userSyncState.findUnique({
      where: { userId },
    });
    return state?.seq ?? 0n;
  }

  async applyPushBatch(userId: string, changes: SyncChangeItem[]) {
    return prisma.$transaction(async (tx: any) => {
      // 1. Lock user_sync_state FOR UPDATE and increment sequence
      const lockedRows: any = await tx.$queryRawUnsafe(
        'SELECT seq FROM user_sync_state WHERE user_id = $1::uuid FOR UPDATE',
        userId
      );

      if (!lockedRows || lockedRows.length === 0) {
        throw new Error('User sync state not initialized');
      }

      const currentSeq = BigInt(lockedRows[0].seq);
      let runningSeq = currentSeq;

      const acceptedIds: string[] = [];
      const aggregateUpdates: Array<{ day: string; categoryId: string; accountId: string }> = [];

      // 2. Apply each change with strictly monotonic changeSeq
      for (const change of changes) {
        runningSeq += 1n;
        const itemSeq = runningSeq;
        const { entity, op, id, data } = change;

        if (entity === 'transaction') {
          if (op === 'delete') {
            await tx.transaction.updateMany({
              where: { id, userId },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            const amount = new Prisma.Decimal(data.amount || 0);
            const balanceAfter = data.balance_after != null ? new Prisma.Decimal(data.balance_after) : null;
            const occurredAt = new Date(data.occurred_at || new Date());

            await tx.transaction.upsert({
              where: { id },
              create: {
                id,
                userId,
                accountId: data.account_id,
                categoryId: data.category_id || null,
                type: data.type || 'expense',
                amount,
                balanceAfter,
                counterparty: data.counterparty || null,
                reference: data.reference || null,
                note: data.note || null,
                occurredAt,
                source: data.source || 'sms',
                parseConfidence: data.parse_confidence != null ? data.parse_confidence : null,
                templateId: data.template_id || null,
                balanceChainOk: data.balance_chain_ok ?? null,
                gapBeforeAmount: data.gap_before_amount != null ? new Prisma.Decimal(data.gap_before_amount) : null,
                isInternalTransfer: data.is_internal_transfer || false,
                parentTxnId: data.parent_txn_id || null,
                dedupeKey: data.dedupe_key || `manual_${id}`,
                needsReview: data.needs_review || false,
                userEditedFields: data.user_edited_fields || [],
                changeSeq: itemSeq,
              },
              update: {
                accountId: data.account_id,
                categoryId: data.category_id || null,
                type: data.type || 'expense',
                amount,
                balanceAfter,
                counterparty: data.counterparty || null,
                reference: data.reference || null,
                note: data.note || null,
                occurredAt,
                parseConfidence: data.parse_confidence != null ? data.parse_confidence : null,
                balanceChainOk: data.balance_chain_ok ?? null,
                gapBeforeAmount: data.gap_before_amount != null ? new Prisma.Decimal(data.gap_before_amount) : null,
                needsReview: data.needs_review || false,
                userEditedFields: data.user_edited_fields || [],
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });

            if (data.category_id && data.account_id) {
              const dayStr = occurredAt.toISOString().slice(0, 10);
              aggregateUpdates.push({
                day: dayStr,
                categoryId: data.category_id,
                accountId: data.account_id,
              });
            }
          }
        } else if (entity === 'account') {
          if (op === 'delete') {
            await tx.account.updateMany({
              where: { id, userId },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.account.upsert({
              where: { id },
              create: {
                id,
                userId,
                provider: data.provider,
                name: data.name,
                accountMask: data.account_mask || null,
                lastKnownBalance: data.last_known_balance != null ? new Prisma.Decimal(data.last_known_balance) : null,
                isSavings: data.is_savings || false,
                changeSeq: itemSeq,
              },
              update: {
                provider: data.provider,
                name: data.name,
                accountMask: data.account_mask || null,
                lastKnownBalance: data.last_known_balance != null ? new Prisma.Decimal(data.last_known_balance) : null,
                isSavings: data.is_savings || false,
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        } else if (entity === 'category') {
          if (op === 'delete') {
            await tx.category.updateMany({
              where: { id, userId, isSystem: false },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.category.upsert({
              where: { id },
              create: {
                id,
                userId,
                name: data.name,
                icon: data.icon,
                colorHex: data.color_hex,
                isSystem: false,
                changeSeq: itemSeq,
              },
              update: {
                name: data.name,
                icon: data.icon,
                colorHex: data.color_hex,
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        } else if (entity === 'limit') {
          if (op === 'delete') {
            await tx.limit.updateMany({
              where: { id, userId },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.limit.upsert({
              where: { id },
              create: {
                id,
                userId,
                scopeType: data.scope_type || 'overall',
                scopeId: data.scope_id || null,
                periodType: data.period_type,
                startDate: data.start_date ? new Date(data.start_date) : null,
                endDate: data.end_date ? new Date(data.end_date) : null,
                amount: new Prisma.Decimal(data.amount || 0),
                mode: data.mode || 'soft',
                rollover: data.rollover || false,
                alertThresholds: data.alert_thresholds || [50, 80, 100],
                active: data.active ?? true,
                changeSeq: itemSeq,
              },
              update: {
                scopeType: data.scope_type || 'overall',
                scopeId: data.scope_id || null,
                periodType: data.period_type,
                amount: new Prisma.Decimal(data.amount || 0),
                mode: data.mode || 'soft',
                rollover: data.rollover || false,
                alertThresholds: data.alert_thresholds || [50, 80, 100],
                active: data.active ?? true,
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        } else if (entity === 'saving_plan') {
          if (op === 'delete') {
            await tx.savingPlan.updateMany({
              where: { id, userId },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.savingPlan.upsert({
              where: { id },
              create: {
                id,
                userId,
                name: data.name,
                periodType: data.period_type,
                targetAmount: new Prisma.Decimal(data.target_amount || 0),
                startDate: new Date(data.start_date || new Date()),
                endDate: data.end_date ? new Date(data.end_date) : null,
                ruleType: data.rule_type || 'fixed',
                ruleValue: data.rule_value != null ? new Prisma.Decimal(data.rule_value) : null,
                linkedAccountId: data.linked_account_id || null,
                priority: data.priority || 3,
                status: data.status || 'active',
                changeSeq: itemSeq,
              },
              update: {
                name: data.name,
                targetAmount: new Prisma.Decimal(data.target_amount || 0),
                ruleType: data.rule_type || 'fixed',
                ruleValue: data.rule_value != null ? new Prisma.Decimal(data.rule_value) : null,
                priority: data.priority || 3,
                status: data.status || 'active',
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        } else if (entity === 'budget_plan') {
          if (op === 'delete') {
            await tx.budgetPlan.updateMany({
              where: { id, userId },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.budgetPlan.upsert({
              where: { id },
              create: {
                id,
                userId,
                name: data.name || 'My Spending Plan',
                totalAmount: new Prisma.Decimal(data.total_amount || 0),
                startDate: new Date(data.start_date || new Date()),
                endDate: new Date(data.end_date || new Date()),
                rolloverMode: data.rollover_mode || 'SPREAD_EVENLY',
                reservePercent: new Prisma.Decimal(data.reserve_percent || 0),
                savingGoal: new Prisma.Decimal(data.saving_goal || 0),
                minDailyFloor: new Prisma.Decimal(data.min_daily_floor || 0),
                dayWeights: data.day_weights || null,
                active: data.active ?? true,
                changeSeq: itemSeq,
              },
              update: {
                name: data.name || 'My Spending Plan',
                totalAmount: new Prisma.Decimal(data.total_amount || 0),
                startDate: new Date(data.start_date || new Date()),
                endDate: new Date(data.end_date || new Date()),
                rolloverMode: data.rollover_mode || 'SPREAD_EVENLY',
                reservePercent: new Prisma.Decimal(data.reserve_percent || 0),
                savingGoal: new Prisma.Decimal(data.saving_goal || 0),
                minDailyFloor: new Prisma.Decimal(data.min_daily_floor || 0),
                dayWeights: data.day_weights || null,
                active: data.active ?? true,
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        } else if (entity === 'fixed_expense') {
          if (op === 'delete') {
            await tx.fixedExpense.updateMany({
              where: { id, plan: { userId } },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.fixedExpense.upsert({
              where: { id },
              create: {
                id,
                planId: data.plan_id,
                title: data.title,
                amount: new Prisma.Decimal(data.amount || 0),
                dueDate: data.due_date ? new Date(data.due_date) : null,
                paid: data.paid ?? false,
                changeSeq: itemSeq,
              },
              update: {
                title: data.title,
                amount: new Prisma.Decimal(data.amount || 0),
                dueDate: data.due_date ? new Date(data.due_date) : null,
                paid: data.paid ?? false,
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        } else if (entity === 'category_limit') {
          if (op === 'delete') {
            await tx.categoryLimit.updateMany({
              where: { id, plan: { userId } },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.categoryLimit.upsert({
              where: { id },
              create: {
                id,
                planId: data.plan_id,
                category: data.category,
                amount: new Prisma.Decimal(data.amount || 0),
                changeSeq: itemSeq,
              },
              update: {
                category: data.category,
                amount: new Prisma.Decimal(data.amount || 0),
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        } else if (entity === 'reimbursement') {
          if (op === 'delete') {
            await tx.reimbursement.updateMany({
              where: { id, userId },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.reimbursement.upsert({
              where: { id },
              create: {
                id,
                userId,
                expenseTxnId: data.expense_txn_id,
                creditTxnId: data.credit_txn_id,
                amount: new Prisma.Decimal(data.amount || 0),
                note: data.note || null,
                changeSeq: itemSeq,
              },
              update: {
                expenseTxnId: data.expense_txn_id,
                creditTxnId: data.credit_txn_id,
                amount: new Prisma.Decimal(data.amount || 0),
                note: data.note || null,
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        } else if (entity === 'contact_person') {
          if (op === 'delete') {
            await tx.contactPerson.updateMany({
              where: { id, userId },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.contactPerson.upsert({
              where: { id },
              create: {
                id,
                userId,
                name: data.name,
                phoneNumber: data.phone_number || null,
                changeSeq: itemSeq,
              },
              update: {
                name: data.name,
                phoneNumber: data.phone_number || null,
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        } else if (entity === 'loan_debt') {
          if (op === 'delete') {
            await tx.loanDebt.updateMany({
              where: { id, userId },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.loanDebt.upsert({
              where: { id },
              create: {
                id,
                userId,
                personId: data.person_id,
                type: data.type || 'borrowed',
                initialAmount: new Prisma.Decimal(data.initial_amount || 0),
                currentBalance: new Prisma.Decimal(data.current_balance || 0),
                dueDate: data.due_date ? new Date(data.due_date) : null,
                status: data.status || 'active',
                note: data.note || null,
                changeSeq: itemSeq,
              },
              update: {
                personId: data.person_id,
                type: data.type || 'borrowed',
                initialAmount: new Prisma.Decimal(data.initial_amount || 0),
                currentBalance: new Prisma.Decimal(data.current_balance || 0),
                dueDate: data.due_date ? new Date(data.due_date) : null,
                status: data.status || 'active',
                note: data.note || null,
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        } else if (entity === 'loan_repayment') {
          if (op === 'delete') {
            await tx.loanRepayment.updateMany({
              where: { id, userId },
              data: { deletedAt: new Date(), changeSeq: itemSeq },
            });
          } else {
            await tx.loanRepayment.upsert({
              where: { id },
              create: {
                id,
                userId,
                loanDebtId: data.loan_debt_id,
                txnId: data.txn_id || null,
                amount: new Prisma.Decimal(data.amount || 0),
                repaidAt: new Date(data.repaid_at || new Date()),
                note: data.note || null,
                changeSeq: itemSeq,
              },
              update: {
                loanDebtId: data.loan_debt_id,
                txnId: data.txn_id || null,
                amount: new Prisma.Decimal(data.amount || 0),
                repaidAt: new Date(data.repaid_at || new Date()),
                note: data.note || null,
                changeSeq: itemSeq,
                deletedAt: null,
              },
            });
          }
        }

        acceptedIds.push(id);
      }

      if (runningSeq > currentSeq) {
        await tx.userSyncState.update({
          where: { userId },
          data: { seq: runningSeq },
        });
      }

      // 3. Record transactional outbox event
      await tx.outboxEvent.create({
        data: {
          userId,
          eventType: 'sync.push',
          payload: {
            changeSeq: runningSeq.toString(),
            count: changes.length,
          },
        },
      });

      return {
        acceptedIds,
        newCursor: runningSeq,
        aggregateUpdates,
      };
    });
  }

  async pullChanges(userId: string, cursor: bigint, limit: number) {
    // Query each syncable entity where changeSeq > cursor ordered by changeSeq ASC
    const [
      txns,
      accounts,
      categories,
      limits,
      plans,
      budgetPlans,
      fixedExpenses,
      categoryLimits,
      reimbursements,
      contactPersons,
      loanDebts,
      loanRepayments,
    ] = await Promise.all([
      prisma.transaction.findMany({
        where: { userId, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.account.findMany({
        where: { userId, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.category.findMany({
        where: { userId, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.limit.findMany({
        where: { userId, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.savingPlan.findMany({
        where: { userId, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.budgetPlan.findMany({
        where: { userId, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.fixedExpense.findMany({
        where: { plan: { userId }, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.categoryLimit.findMany({
        where: { plan: { userId }, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.reimbursement.findMany({
        where: { userId, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.contactPerson.findMany({
        where: { userId, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.loanDebt.findMany({
        where: { userId, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
      prisma.loanRepayment.findMany({
        where: { userId, changeSeq: { gt: cursor } },
        orderBy: { changeSeq: 'asc' },
        take: limit,
      }),
    ]);

    // Flatten and normalize into standard change items
    const allChanges: Array<{
      entity: string;
      op: 'upsert' | 'delete';
      id: string;
      change_seq: bigint;
      data: any;
    }> = [];

    for (const t of txns) {
      allChanges.push({
        entity: 'transaction',
        op: t.deletedAt ? 'delete' : 'upsert',
        id: t.id,
        change_seq: t.changeSeq,
        data: {
          account_id: t.accountId,
          category_id: t.categoryId,
          type: t.type,
          amount: t.amount.toString(),
          balance_after: t.balanceAfter ? t.balanceAfter.toString() : null,
          counterparty: t.counterparty,
          reference: t.reference,
          note: t.note,
          occurred_at: t.occurredAt.toISOString(),
          source: t.source,
          parse_confidence: t.parseConfidence,
          template_id: t.templateId,
          balance_chain_ok: t.balanceChainOk,
          gap_before_amount: t.gapBeforeAmount ? t.gapBeforeAmount.toString() : null,
          is_internal_transfer: t.isInternalTransfer,
          dedupe_key: t.dedupeKey,
          needs_review: t.needsReview,
          user_edited_fields: t.userEditedFields,
        },
      });
    }

    for (const a of accounts) {
      allChanges.push({
        entity: 'account',
        op: a.deletedAt ? 'delete' : 'upsert',
        id: a.id,
        change_seq: a.changeSeq,
        data: {
          provider: a.provider,
          name: a.name,
          account_mask: a.accountMask,
          last_known_balance: a.lastKnownBalance ? a.lastKnownBalance.toString() : null,
          is_savings: a.isSavings,
        },
      });
    }

    for (const c of categories) {
      allChanges.push({
        entity: 'category',
        op: c.deletedAt ? 'delete' : 'upsert',
        id: c.id,
        change_seq: c.changeSeq,
        data: {
          name: c.name,
          icon: c.icon,
          color_hex: c.colorHex,
        },
      });
    }

    for (const l of limits) {
      allChanges.push({
        entity: 'limit',
        op: l.deletedAt ? 'delete' : 'upsert',
        id: l.id,
        change_seq: l.changeSeq,
        data: {
          scope_type: l.scopeType,
          scope_id: l.scopeId,
          period_type: l.periodType,
          amount: l.amount.toString(),
          mode: l.mode,
          rollover: l.rollover,
          alert_thresholds: l.alertThresholds,
          active: l.active,
        },
      });
    }

    for (const p of plans) {
      allChanges.push({
        entity: 'saving_plan',
        op: p.deletedAt ? 'delete' : 'upsert',
        id: p.id,
        change_seq: p.changeSeq,
        data: {
          name: p.name,
          period_type: p.periodType,
          target_amount: p.targetAmount.toString(),
          rule_type: p.ruleType,
          status: p.status,
        },
      });
    }

    for (const bp of budgetPlans) {
      allChanges.push({
        entity: 'budget_plan',
        op: bp.deletedAt ? 'delete' : 'upsert',
        id: bp.id,
        change_seq: bp.changeSeq,
        data: {
          name: bp.name,
          total_amount: bp.totalAmount.toString(),
          start_date: bp.startDate.toISOString().slice(0, 10),
          end_date: bp.endDate.toISOString().slice(0, 10),
          rollover_mode: bp.rolloverMode,
          reserve_percent: bp.reservePercent.toString(),
          saving_goal: bp.savingGoal.toString(),
          min_daily_floor: bp.minDailyFloor.toString(),
          day_weights: bp.dayWeights,
          active: bp.active,
        },
      });
    }

    for (const fe of fixedExpenses) {
      allChanges.push({
        entity: 'fixed_expense',
        op: fe.deletedAt ? 'delete' : 'upsert',
        id: fe.id,
        change_seq: fe.changeSeq,
        data: {
          plan_id: fe.planId,
          title: fe.title,
          amount: fe.amount.toString(),
          due_date: fe.dueDate ? fe.dueDate.toISOString().slice(0, 10) : null,
          paid: fe.paid,
        },
      });
    }

    for (const cl of categoryLimits) {
      allChanges.push({
        entity: 'category_limit',
        op: cl.deletedAt ? 'delete' : 'upsert',
        id: cl.id,
        change_seq: cl.changeSeq,
        data: {
          plan_id: cl.planId,
          category: cl.category,
          amount: cl.amount.toString(),
        },
      });
    }

    for (const r of reimbursements) {
      allChanges.push({
        entity: 'reimbursement',
        op: r.deletedAt ? 'delete' : 'upsert',
        id: r.id,
        change_seq: r.changeSeq,
        data: {
          expense_txn_id: r.expenseTxnId,
          credit_txn_id: r.creditTxnId,
          amount: r.amount.toString(),
          note: r.note,
        },
      });
    }

    for (const cp of contactPersons) {
      allChanges.push({
        entity: 'contact_person',
        op: cp.deletedAt ? 'delete' : 'upsert',
        id: cp.id,
        change_seq: cp.changeSeq,
        data: {
          name: cp.name,
          phone_number: cp.phoneNumber,
        },
      });
    }

    for (const ld of loanDebts) {
      allChanges.push({
        entity: 'loan_debt',
        op: ld.deletedAt ? 'delete' : 'upsert',
        id: ld.id,
        change_seq: ld.changeSeq,
        data: {
          person_id: ld.personId,
          type: ld.type,
          initial_amount: ld.initialAmount.toString(),
          current_balance: ld.currentBalance.toString(),
          due_date: ld.dueDate ? ld.dueDate.toISOString().slice(0, 10) : null,
          status: ld.status,
          note: ld.note,
        },
      });
    }

    for (const lr of loanRepayments) {
      allChanges.push({
        entity: 'loan_repayment',
        op: lr.deletedAt ? 'delete' : 'upsert',
        id: lr.id,
        change_seq: lr.changeSeq,
        data: {
          loan_debt_id: lr.loanDebtId,
          txn_id: lr.txnId,
          amount: lr.amount.toString(),
          repaid_at: lr.repaidAt.toISOString(),
          note: lr.note,
        },
      });
    }

    // Sort all by change_seq
    allChanges.sort((a, b) => (a.change_seq < b.change_seq ? -1 : a.change_seq > b.change_seq ? 1 : 0));

    const paged = allChanges.slice(0, limit);
    const hasMore = allChanges.length > limit;
    const maxSeq = paged.length > 0 ? paged[paged.length - 1].change_seq : cursor;

    return {
      cursor: maxSeq,
      hasMore,
      changes: paged.map((c) => ({
        ...c,
        change_seq: Number(c.change_seq),
      })),
    };
  }
}

export const syncRepository = new SyncRepository();
