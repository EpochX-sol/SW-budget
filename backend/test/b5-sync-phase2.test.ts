import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { FastifyInstance } from 'fastify';
import supertest from 'supertest';
import { buildApp } from '../src/app.js';
import { prisma } from '../src/db/prisma.js';
import { redisConnection } from '../src/jobs/redis.js';

describe('Milestone B5: Monotonic Sync Protocol for Plans, Debts & Reimbursements', { timeout: 25000 }, () => {
  let app: FastifyInstance;
  let accessToken: string;
  let userId: string;
  const testDeviceId = '018f3a5b-9b42-7c30-9b32-e02165849b33';
  const testEmail = 'b5_sync_user@example.com';

  const accountId = '018f3a5e-0000-7000-8000-000000000101';
  const expenseTxnId = '018f3a5e-0000-7000-8000-000000000102';
  const creditTxnId = '018f3a5e-0000-7000-8000-000000000103';
  const planId = '018f3a5e-0000-7000-8000-000000000104';
  const fixedExpenseId = '018f3a5e-0000-7000-8000-000000000105';
  const categoryLimitId = '018f3a5e-0000-7000-8000-000000000106';
  const reimbursementId = '018f3a5e-0000-7000-8000-000000000107';
  const contactPersonId = '018f3a5e-0000-7000-8000-000000000108';
  const loanDebtId = '018f3a5e-0000-7000-8000-000000000109';
  const loanRepaymentId = '018f3a5e-0000-7000-8000-000000000110';

  beforeAll(async () => {
    app = await buildApp();
    await app.ready();

    // Clean up test user if exists
    await prisma.user.deleteMany({
      where: { email: testEmail },
    });

    // Register user to obtain access token
    const regRes = await supertest(app.server)
      .post('/v1/auth/register')
      .send({
        email: testEmail,
        password: 'Password123!',
        display_name: 'B5 Sync User',
        device: {
          id: testDeviceId,
          device_name: 'B5 Android Device',
          platform: 'android',
          app_version: '1.2.0',
        },
      });

    accessToken = regRes.body.access_token;
    userId = regRes.body.user.id;
  });

  afterAll(async () => {
    await prisma.user.deleteMany({
      where: { email: testEmail },
    });
    await app.close();
    await prisma.$disconnect();
    redisConnection.disconnect();
  });

  describe('1. Push Synchronization with Phase 2 Primitives', () => {
    const idempotencyKey = '018f3a5e-9999-7000-8000-000000000001';

    it('successfully pushes a complete batch with plans, fixed expenses, reimbursements, and debts', async () => {
      const nowIso = new Date().toISOString();

      const pushRes = await supertest(app.server)
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${accessToken}`)
        .set('Idempotency-Key', idempotencyKey)
        .send({
          device_id: testDeviceId,
          batch_index: 1,
          total_batches: 1,
          changes: [
            // Account
            {
              entity: 'account',
              op: 'upsert',
              id: accountId,
              client_updated_at: nowIso,
              data: {
                provider: 'CBE',
                name: 'CBE Main Checking',
                last_known_balance: 15000,
                is_savings: false,
              },
            },
            // Expense Txn (Dinner with friends)
            {
              entity: 'transaction',
              op: 'upsert',
              id: expenseTxnId,
              client_updated_at: nowIso,
              data: {
                account_id: accountId,
                type: 'expense',
                amount: 1200,
                counterparty: 'Bole Traditional Restaurant',
                occurred_at: '2026-10-08T19:30:00.000Z',
                source: 'sms',
                dedupe_key: 'dedupe_dinner_1001',
              },
            },
            // Credit Txn (Friend transferred their share)
            {
              entity: 'transaction',
              op: 'upsert',
              id: creditTxnId,
              client_updated_at: nowIso,
              data: {
                account_id: accountId,
                type: 'income',
                amount: 600,
                counterparty: 'Abebe Kebede',
                occurred_at: '2026-10-09T08:00:00.000Z',
                source: 'sms',
                dedupe_key: 'dedupe_friend_transfer_1002',
              },
            },
            // Budget Plan
            {
              entity: 'budget_plan',
              op: 'upsert',
              id: planId,
              client_updated_at: nowIso,
              data: {
                name: 'October 2-Week Spending Plan',
                total_amount: 14000,
                start_date: '2026-10-01',
                end_date: '2026-10-14',
                rollover_mode: 'SPREAD_EVENLY',
                reserve_percent: 5,
                saving_goal: 1000,
                min_daily_floor: 200,
                active: true,
              },
            },
            // Fixed Expense under plan
            {
              entity: 'fixed_expense',
              op: 'upsert',
              id: fixedExpenseId,
              client_updated_at: nowIso,
              data: {
                plan_id: planId,
                title: 'Monthly Internet Wifi',
                amount: 1500,
                due_date: '2026-10-05',
                paid: true,
              },
            },
            // Category Limit under plan
            {
              entity: 'category_limit',
              op: 'upsert',
              id: categoryLimitId,
              client_updated_at: nowIso,
              data: {
                plan_id: planId,
                category: 'Dining & Drinks',
                amount: 3000,
              },
            },
            // Reimbursement
            {
              entity: 'reimbursement',
              op: 'upsert',
              id: reimbursementId,
              client_updated_at: nowIso,
              data: {
                expense_txn_id: expenseTxnId,
                credit_txn_id: creditTxnId,
                amount: 600,
                note: 'Abebe paid back for restaurant dinner',
              },
            },
            // Contact Person
            {
              entity: 'contact_person',
              op: 'upsert',
              id: contactPersonId,
              client_updated_at: nowIso,
              data: {
                name: 'Abebe Kebede',
                phone_number: '+251911223344',
              },
            },
            // Loan / Debt (Lent money)
            {
              entity: 'loan_debt',
              op: 'upsert',
              id: loanDebtId,
              client_updated_at: nowIso,
              data: {
                person_id: contactPersonId,
                type: 'lent',
                initial_amount: 5000,
                current_balance: 3000,
                due_date: '2026-11-01',
                status: 'active',
                note: 'Emergency loan to Abebe',
              },
            },
            // Loan Repayment
            {
              entity: 'loan_repayment',
              op: 'upsert',
              id: loanRepaymentId,
              client_updated_at: nowIso,
              data: {
                loan_debt_id: loanDebtId,
                amount: 2000,
                repaid_at: '2026-10-10T09:00:00.000Z',
                note: 'First installment repaid',
              },
            },
          ],
        });

      expect(pushRes.status).toBe(200);
      expect(pushRes.body.accepted_ids).toHaveLength(10);
      expect(pushRes.body.accepted_ids).toContain(planId);
      expect(pushRes.body.accepted_ids).toContain(fixedExpenseId);
      expect(pushRes.body.accepted_ids).toContain(categoryLimitId);
      expect(pushRes.body.accepted_ids).toContain(reimbursementId);
      expect(pushRes.body.accepted_ids).toContain(contactPersonId);
      expect(pushRes.body.accepted_ids).toContain(loanDebtId);
      expect(pushRes.body.accepted_ids).toContain(loanRepaymentId);
      expect(pushRes.body.new_cursor).toBeGreaterThanOrEqual(10);

      // Verify persistence directly in PostgreSQL
      const dbPlan = await prisma.budgetPlan.findUnique({ where: { id: planId } });
      expect(dbPlan).not.toBeNull();
      expect(Number(dbPlan?.totalAmount)).toBe(14000);
      expect(dbPlan?.rolloverMode).toBe('SPREAD_EVENLY');

      const dbReimb = await prisma.reimbursement.findUnique({ where: { id: reimbursementId } });
      expect(dbReimb).not.toBeNull();
      expect(Number(dbReimb?.amount)).toBe(600);
      expect(dbReimb?.expenseTxnId).toBe(expenseTxnId);

      const dbDebt = await prisma.loanDebt.findUnique({ where: { id: loanDebtId } });
      expect(dbDebt).not.toBeNull();
      expect(Number(dbDebt?.currentBalance)).toBe(3000);
      expect(dbDebt?.type).toBe('lent');
    });

    it('enforces idempotency on repeated push with same Idempotency-Key', async () => {
      const pushRes = await supertest(app.server)
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${accessToken}`)
        .set('Idempotency-Key', idempotencyKey)
        .send({
          device_id: testDeviceId,
          changes: [],
        });

      expect(pushRes.status).toBe(200);
      expect(pushRes.body.accepted_ids).toContain(planId);
      expect(pushRes.body.accepted_ids).toContain(reimbursementId);
    });
  });

  describe('2. Pull Synchronization with Phase 2 Primitives', () => {
    it('retrieves all newly synced entity types with change_seq > 0', async () => {
      const pullRes = await supertest(app.server)
        .get('/v1/sync/pull?cursor=0&limit=50')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(pullRes.status).toBe(200);
      expect(pullRes.body.changes.length).toBeGreaterThanOrEqual(10);

      const pulledPlan = pullRes.body.changes.find((c: any) => c.id === planId);
      expect(pulledPlan).toBeDefined();
      expect(pulledPlan.entity).toBe('budget_plan');
      expect(pulledPlan.data.name).toBe('October 2-Week Spending Plan');
      expect(pulledPlan.data.total_amount).toBe('14000');

      const pulledReimb = pullRes.body.changes.find((c: any) => c.id === reimbursementId);
      expect(pulledReimb).toBeDefined();
      expect(pulledReimb.entity).toBe('reimbursement');
      expect(pulledReimb.data.amount).toBe('600');

      const pulledPerson = pullRes.body.changes.find((c: any) => c.id === contactPersonId);
      expect(pulledPerson).toBeDefined();
      expect(pulledPerson.entity).toBe('contact_person');
      expect(pulledPerson.data.name).toBe('Abebe Kebede');

      const pulledDebt = pullRes.body.changes.find((c: any) => c.id === loanDebtId);
      expect(pulledDebt).toBeDefined();
      expect(pulledDebt.entity).toBe('loan_debt');
      expect(pulledDebt.data.current_balance).toBe('3000');
    });

    it('returns empty changes when cursor matches the highest change_seq', async () => {
      const syncState = await prisma.userSyncState.findUnique({
        where: { userId },
      });
      const currentSeq = Number(syncState?.seq);

      const pullRes = await supertest(app.server)
        .get(`/v1/sync/pull?cursor=${currentSeq}&limit=50`)
        .set('Authorization', `Bearer ${accessToken}`);

      expect(pullRes.status).toBe(200);
      expect(pullRes.body.changes).toHaveLength(0);
    });
  });

  describe('3. Soft-Deletes via Sync Push', () => {
    it('applies soft delete to budget plan and contact person', async () => {
      const deletePushRes = await supertest(app.server)
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          device_id: testDeviceId,
          batch_index: 1,
          total_batches: 1,
          changes: [
            {
              entity: 'fixed_expense',
              op: 'delete',
              id: fixedExpenseId,
              client_updated_at: new Date().toISOString(),
              data: {},
            },
            {
              entity: 'loan_debt',
              op: 'delete',
              id: loanDebtId,
              client_updated_at: new Date().toISOString(),
              data: {},
            },
          ],
        });

      expect(deletePushRes.status).toBe(200);
      expect(deletePushRes.body.accepted_ids).toContain(fixedExpenseId);
      expect(deletePushRes.body.accepted_ids).toContain(loanDebtId);

      // Verify pull returns op: 'delete'
      const pullRes = await supertest(app.server)
        .get(`/v1/sync/pull?cursor=${deletePushRes.body.new_cursor - 2}&limit=10`)
        .set('Authorization', `Bearer ${accessToken}`);

      expect(pullRes.status).toBe(200);
      const deletedFe = pullRes.body.changes.find((c: any) => c.id === fixedExpenseId);
      expect(deletedFe).toBeDefined();
      expect(deletedFe.op).toBe('delete');

      const deletedDebt = pullRes.body.changes.find((c: any) => c.id === loanDebtId);
      expect(deletedDebt).toBeDefined();
      expect(deletedDebt.op).toBe('delete');
    });
  });

  describe('4. Security & Validation Rejections', () => {
    it('rejects unauthenticated sync push with 401', async () => {
      const res = await supertest(app.server)
        .post('/v1/sync/push')
        .send({
          device_id: testDeviceId,
          changes: [],
        });

      expect(res.status).toBe(401);
    });

    it('rejects sync push with invalid entity type', async () => {
      const res = await supertest(app.server)
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          device_id: testDeviceId,
          changes: [
            {
              entity: 'invalid_crypto_entity',
              op: 'upsert',
              id: '018f3a5e-0000-7000-8000-000000000999',
              client_updated_at: new Date().toISOString(),
              data: {},
            },
          ],
        });

      expect(res.status).toBe(400);
    });
  });
});
