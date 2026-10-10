import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { FastifyInstance } from 'fastify';
import supertest from 'supertest';
import { buildApp } from '../src/app.js';
import { prisma } from '../src/db/prisma.js';
import { redisConnection } from '../src/jobs/redis.js';
import { processSnapshotRebuildJob } from '../src/jobs/workers/plan-snapshots.worker.js';
import { processPlanNotificationJob } from '../src/jobs/workers/plan-notifications.worker.js';
import { schedulerWorker } from '../src/jobs/workers/scheduler.worker.js';

describe('Milestones B7, B8, B9: Deep APIs, Workers & AI Gateway Test Suite', { timeout: 35000 }, () => {
  let app: FastifyInstance;
  let accessToken: string;
  let userId: string;
  let createdPlanId: string;
  let createdExpenseTxnId: string;
  let createdCreditTxnId: string;
  let createdDebtId: string;

  const testDeviceId = '018f3a5b-9b42-7c30-9b32-e02165849b77';
  const testEmail = 'b789_full_test_user@example.com';
  const testAccountId = '018f3a5e-0000-7000-8000-000000000201';

  beforeAll(async () => {
    app = await buildApp();
    await app.ready();

    // Clean up test user
    await prisma.user.deleteMany({
      where: { email: testEmail },
    });

    // Register user
    const regRes = await supertest(app.server)
      .post('/v1/auth/register')
      .send({
        email: testEmail,
        password: 'Password123!',
        display_name: 'B789 Test User',
        device: {
          id: testDeviceId,
          device_name: 'Test Device B789',
          platform: 'android',
          app_version: '2.0.0',
        },
      });

    accessToken = regRes.body.access_token;
    userId = regRes.body.user.id;

    // Create a base account and transactions for testing
    await prisma.account.create({
      data: {
        id: testAccountId,
        userId,
        provider: 'CBE',
        name: 'Primary Checking',
        changeSeq: 1n,
      },
    });

    createdExpenseTxnId = '018f3a5e-0000-7000-8000-000000000202';
    createdCreditTxnId = '018f3a5e-0000-7000-8000-000000000203';

    await prisma.transaction.createMany({
      data: [
        {
          id: createdExpenseTxnId,
          userId,
          accountId: testAccountId,
          type: 'expense',
          amount: 1000,
          counterparty: 'Bole Grocery Store',
          occurredAt: new Date(),
          dedupeKey: 'dedupe_exp_202',
          changeSeq: 2n,
        },
        {
          id: createdCreditTxnId,
          userId,
          accountId: testAccountId,
          type: 'income',
          amount: 500,
          counterparty: 'Henok Friend',
          occurredAt: new Date(),
          dedupeKey: 'dedupe_inc_203',
          changeSeq: 3n,
        },
      ],
    });
  });

  afterAll(async () => {
    await prisma.user.deleteMany({
      where: { email: testEmail },
    });
    await app.close();
    await prisma.$disconnect();
    redisConnection.disconnect();
  });

  // ─────────────────────────────────────────────────────────────
  // Milestone B7: REST APIs for Spending Plans, Reimbursements, Debts & OTA
  // ─────────────────────────────────────────────────────────────
  describe('Milestone B7: REST APIs', () => {
    it('POST /v1/plans rejects inverted dates with 400', async () => {
      const res = await supertest(app.server)
        .post('/v1/plans')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          name: 'Invalid Plan',
          total_amount: 10000,
          start_date: '2026-10-20',
          end_date: '2026-10-10', // Before start
        });

      expect(res.status).toBe(400);
      expect(res.body.detail).toContain('start_date must be on or before end_date');
    });

    it('POST /v1/plans successfully creates a spending plan and computes initial snapshot', async () => {
      const res = await supertest(app.server)
        .post('/v1/plans')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          name: 'October 2-Week Plan',
          total_amount: 14000,
          start_date: '2026-10-01',
          end_date: '2026-10-14',
          rollover_mode: 'SPREAD_EVENLY',
          reserve_percent: 5,
          saving_goal: 1000,
          min_daily_floor: 100,
          fixed_expenses: [
            {
              title: 'Apartment Wifi',
              amount: 1500,
              due_date: '2026-10-05',
              paid: true,
            },
          ],
          category_limits: [
            {
              category: 'Food',
              amount: 3000,
            },
          ],
        });

      expect(res.status).toBe(201);
      expect(res.body.plan).toBeDefined();
      expect(res.body.plan.name).toBe('October 2-Week Plan');
      expect(res.body.snapshot).toBeDefined();
      expect(res.body.snapshot.totals.budget).toBe(14000);
      expect(res.body.snapshot.totals.fixed).toBe(1500);

      createdPlanId = res.body.plan.id;
    });

    it('POST /v1/plans rejects overlapping active plans with 400', async () => {
      const res = await supertest(app.server)
        .post('/v1/plans')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          name: 'Overlapping Plan',
          total_amount: 8000,
          start_date: '2026-10-05',
          end_date: '2026-10-18',
        });

      expect(res.status).toBe(400);
      expect(res.body.detail).toContain('overlaps');
    });

    it('GET /v1/plans/active returns current active plan and snapshot', async () => {
      const res = await supertest(app.server)
        .get('/v1/plans/active')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.plan.id).toBe(createdPlanId);
      expect(res.body.snapshot).toBeDefined();
      expect(res.body.snapshot.today.allowance).toBeGreaterThan(0);
    });

    it('GET /v1/plans/:id/weeks returns partitioned calendar weeks', async () => {
      const res = await supertest(app.server)
        .get(`/v1/plans/${createdPlanId}/weeks`)
        .set('Authorization', `Bearer ${accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.weeks).toHaveLength(2);
      expect(res.body.weeks[0].baseTarget).toBeGreaterThan(0);
    });

    it('POST /v1/plans/:id/simulate runs what-if spend scenarios', async () => {
      const res = await supertest(app.server)
        .post(`/v1/plans/${createdPlanId}/simulate`)
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          proposed_daily_spend: 600,
        });

      expect(res.status).toBe(200);
      expect(res.body.dailySpend).toBe(600);
      expect(res.body.projectedTotal).toBeGreaterThan(0);
      expect(['SAFE', 'WARNING', 'DEFICIT']).toContain(res.body.status);
    });

    it('POST /v1/plans/:id/fixed-expenses adds fixed commitment and updates snapshot', async () => {
      const res = await supertest(app.server)
        .post(`/v1/plans/${createdPlanId}/fixed-expenses`)
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          title: 'Water Bill',
          amount: 300,
          due_date: '2026-10-08',
          paid: false,
        });

      expect(res.status).toBe(201);
      expect(res.body.fixedExpense.title).toBe('Water Bill');
      // Fixed total increased from 1500 to 1800
      expect(res.body.snapshot.totals.fixed).toBe(1800);
    });

    it('POST /v1/finance/reimbursements links credit to expense and prevents over-allocation', async () => {
      // 1. Valid reimbursement of 400 ETB
      const validRes = await supertest(app.server)
        .post('/v1/finance/reimbursements')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          expense_txn_id: createdExpenseTxnId,
          credit_txn_id: createdCreditTxnId,
          amount: 400,
          note: 'Henok lunch share',
        });

      expect(validRes.status).toBe(201);
      expect(Number(validRes.body.amount)).toBe(400);

      // 2. Over-allocation: 1000 original - 400 = 600 remaining unreimbursed. Trying to reimburse 700 must fail.
      const invalidRes = await supertest(app.server)
        .post('/v1/finance/reimbursements')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          expense_txn_id: createdExpenseTxnId,
          credit_txn_id: createdCreditTxnId,
          amount: 700,
        });

      expect(invalidRes.status).toBe(400);
      expect(invalidRes.body.detail).toContain('exceeds remaining unreimbursed');

      // 3. List reimbursements
      const listRes = await supertest(app.server)
        .get('/v1/finance/reimbursements')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(listRes.status).toBe(200);
      expect(listRes.body.reimbursements).toHaveLength(1);
      expect(listRes.body.reimbursements[0].expenseTxn.id).toBe(createdExpenseTxnId);
    });

    it('POST /v1/finance/debts manages lending and repayments', async () => {
      // 1. Create debt (Lent 3000 to Dawit)
      const debtRes = await supertest(app.server)
        .post('/v1/finance/debts')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          person_name: 'Dawit Tadesse',
          phone_number: '+251922334455',
          type: 'lent',
          initial_amount: 3000,
          due_date: '2026-11-15',
          note: 'Short term loan',
        });

      expect(debtRes.status).toBe(201);
      expect(Number(debtRes.body.currentBalance)).toBe(3000);
      expect(debtRes.body.person.name).toBe('Dawit Tadesse');
      createdDebtId = debtRes.body.id;

      // 2. Partial repayment of 1500
      const rep1 = await supertest(app.server)
        .post(`/v1/finance/debts/${createdDebtId}/repayments`)
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          amount: 1500,
          note: 'First installment',
        });

      expect(rep1.status).toBe(201);
      expect(Number(rep1.body.debt.currentBalance)).toBe(1500);
      expect(rep1.body.debt.status).toBe('active');

      // 3. Final repayment of 1500 -> auto settles
      const rep2 = await supertest(app.server)
        .post(`/v1/finance/debts/${createdDebtId}/repayments`)
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          amount: 1500,
          note: 'Final settlement',
        });

      expect(rep2.status).toBe(201);
      expect(Number(rep2.body.debt.currentBalance)).toBe(0);
      expect(rep2.body.debt.status).toBe('settled');
    });

    it('GET /v1/templates/patterns delivers Totals 3238 regex patterns with ETag & 304 caching', async () => {
      // 1. Initial request without ETag
      const res = await supertest(app.server).get('/v1/templates/patterns');

      expect(res.status).toBe(200);
      expect(res.headers.etag).toBeDefined();
      expect(res.body.patterns_count).toBe(215); // 215 structured patterns spanning 3,238 lines
      expect(res.body.version).toBe('2026.10.10');

      const etag = res.headers.etag;

      // 2. Subsequent request with If-None-Match
      const cachedRes = await supertest(app.server)
        .get('/v1/templates/patterns')
        .set('If-None-Match', etag);

      expect(cachedRes.status).toBe(304);
      expect(cachedRes.text).toBe('');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Milestone B8: BullMQ Background Workers & Schedulers
  // ─────────────────────────────────────────────────────────────
  describe('Milestone B8: Background Workers & Schedulers', () => {
    it('executes processSnapshotRebuildJob and refreshes snapshot cache', async () => {
      const result = await processSnapshotRebuildJob({
        planId: createdPlanId,
        userId,
        trigger: 'transaction_created',
      });

      expect(result.planId).toBe(createdPlanId);
      expect(['GREEN', 'YELLOW', 'ORANGE', 'RED']).toContain(result.status);

      // Verify DB snapshot record updated
      const dbSnap = await prisma.planSnapshot.findFirst({
        where: { planId: createdPlanId },
      });
      expect(dbSnap).not.toBeNull();
    });

    it('executes processPlanNotificationJob and enforces 1-per-day deduplication', async () => {
      // Ensure preferences allow dispatch (outside quiet hours)
      await prisma.notificationPreference.upsert({
        where: { userId },
        create: { userId, quietStart: '01:00', quietEnd: '01:00' },
        update: { quietStart: '01:00', quietEnd: '01:00' },
      });

      // 1. Dispatch 80% threshold warning
      const notif1 = await processPlanNotificationJob({
        userId,
        planId: createdPlanId,
        type: 'threshold_80',
        amount: 800,
        allowance: 1000,
      });

      expect(notif1.dispatched).toBe(true);
      expect(notif1.notification_id).not.toBeNull();

      // 2. Immediate second dispatch on same day is deduplicated
      const notif2 = await processPlanNotificationJob({
        userId,
        planId: createdPlanId,
        type: 'threshold_80',
        amount: 850,
        allowance: 1000,
      });

      expect(notif2.dispatched).toBe(false);
    });

    it('executes schedulerWorker.runAddisMidnightTick advancing Day d for active plans', async () => {
      const tick = await schedulerWorker.runAddisMidnightTick();
      expect(tick.plans_ticked).toBeGreaterThanOrEqual(1);
      const matched = tick.results.find((r) => r.planId === createdPlanId);
      expect(matched).toBeDefined();
      expect(matched?.status).toBe('ok');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // Milestone B9: AI Gateway Deterministic Tools & Context Grounding
  // ─────────────────────────────────────────────────────────────
  describe('Milestone B9: AI Gateway Integration', () => {
    let threadId: string;

    it('creates an AI thread and answers questions using deterministic plan tools', async () => {
      // 1. Create thread
      const threadRes = await supertest(app.server)
        .post('/v1/ai/threads')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          title: 'Adaptive Budget Coaching',
        });

      expect(threadRes.status).toBe(201);
      threadId = threadRes.body.id;

      // 2. Chat query invoking get_active_plan_snapshot
      const chatRes = await supertest(app.server)
        .post(`/v1/ai/threads/${threadId}/messages`)
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          content: 'What is my plan allowance for today and tomorrow?',
        });

      expect(chatRes.status).toBe(200);
      expect(chatRes.text).toContain('event: tool_start');
      expect(chatRes.text).toContain('get_active_plan_snapshot');
      expect(chatRes.text).toContain('October 2-Week Plan');
      expect(chatRes.text).toContain('event: done');
    });

    it('answers debt queries using deterministic query_loans_debts tool', async () => {
      const debtChatRes = await supertest(app.server)
        .post(`/v1/ai/threads/${threadId}/messages`)
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          content: 'Who owes me money or what debt do I have?',
        });

      expect(debtChatRes.status).toBe(200);
      expect(debtChatRes.text).toContain('query_loans_debts');
      expect(debtChatRes.text).toContain('event: done');
    });
  });
});
