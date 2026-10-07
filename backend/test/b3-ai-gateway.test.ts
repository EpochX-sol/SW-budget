import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import supertest from 'supertest';
import { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { prisma } from '../src/db/prisma.js';
import { financeTools } from '../src/modules/ai/tools/finance-tools.js';
import { aiMemoryService } from '../src/modules/ai/ai-memory.service.js';

describe('Milestone B3: AI Gateway, Vector Memory & Deterministic Tools Test Suite', () => {
  let app: FastifyInstance;
  let accessToken: string;
  let testUserId: string;
  const testEmail = `b3_ai_tester_${Date.now()}@example.com`;
  const testDeviceId = '018f3a5e-1111-7000-8000-0000000000b3';
  let accountId: string;
  let categoryId: string;
  let threadId: string;

  beforeAll(async () => {
    app = await buildApp();
    await app.ready();

    // 1. Register test user
    const regRes = await supertest(app.server)
      .post('/v1/auth/register')
      .send({
        email: testEmail,
        password: 'Password123!',
        display_name: 'AI Gateway Tester',
        currency: 'ETB',
        device: {
          id: testDeviceId,
          device_name: 'AI Test Phone',
          platform: 'android',
          app_version: '1.0.0',
        },
      });

    expect(regRes.status).toBe(201);
    accessToken = regRes.body.access_token;
    testUserId = regRes.body.user.id;

    // 2. Setup account & category for financial testing
    const acc = await prisma.account.create({
      data: {
        id: '018f3a5e-2222-7000-8000-000000000001',
        userId: testUserId,
        provider: 'CBE',
        name: 'Main CBE',
        changeSeq: 1n,
      },
    });
    accountId = acc.id;

    const cat = await prisma.category.create({
      data: {
        id: '018f3a5e-3333-7000-8000-000000000001',
        userId: testUserId,
        name: 'Dining & Cafes',
        icon: 'utensils',
        colorHex: '#F59E0B',
        changeSeq: 2n,
      },
    });
    categoryId = cat.id;

    // 3. Setup a monthly budget limit
    await prisma.limit.create({
      data: {
        id: '018f3a5e-4444-7000-8000-000000000001',
        userId: testUserId,
        scopeType: 'category',
        scopeId: categoryId,
        periodType: 'monthly',
        amount: 5000.0,
        mode: 'soft',
        changeSeq: 3n,
      },
    });

    // 4. Seed test transactions for the current month
    const now = new Date();
    await prisma.transaction.createMany({
      data: [
        {
          id: '018f3a5e-5555-7000-8000-000000000001',
          userId: testUserId,
          accountId,
          categoryId,
          type: 'expense',
          amount: 600.0,
          occurredAt: now,
          dedupeKey: `ai_txn_1_${Date.now()}`,
          changeSeq: 4n,
        },
        {
          id: '018f3a5e-5555-7000-8000-000000000002',
          userId: testUserId,
          accountId,
          categoryId,
          type: 'expense',
          amount: 1400.0,
          occurredAt: now,
          dedupeKey: `ai_txn_2_${Date.now()}`,
          changeSeq: 5n,
        },
        {
          id: '018f3a5e-5555-7000-8000-000000000003',
          userId: testUserId,
          accountId,
          categoryId,
          type: 'income',
          amount: 8000.0,
          occurredAt: now,
          dedupeKey: `ai_txn_3_${Date.now()}`,
          changeSeq: 6n,
        },
      ],
    });
  });

  afterAll(async () => {
    // Clean up test user and cascade-deleted entities
    if (testUserId) {
      await prisma.user.deleteMany({ where: { id: testUserId } });
    }
    await app.close();
  });

  // ─────────────────────────────────────────────────────────────
  // 1. Deterministic Financial Math Tools
  // ─────────────────────────────────────────────────────────────
  describe('Deterministic Financial Math Tools ("Numbers from code, words from AI")', () => {
    it('getSpendingSummary: computes exact arithmetic totals without hallucinations', async () => {
      const summary = await financeTools.getSpendingSummary(testUserId, { period: 'this_month' });

      expect(summary.total_expense).toBe(2000); // 600 + 1400
      expect(summary.total_income).toBe(8000);
      expect(summary.net_savings).toBe(6000);
      expect(summary.transaction_count).toBe(3);
      expect(summary.currency).toBe('ETB');
    });

    it('simulateScenario: evaluates purchase against limit and calculates safe pace', async () => {
      // Scenario A: Safe purchase (spend 1,000 ETB on Dining with 5,000 ETB limit, currently at 2,000)
      const safeScenario = await financeTools.simulateScenario(testUserId, {
        amount: 1000,
        category_id: categoryId,
      });

      expect(safeScenario.current_spent).toBe(2000);
      expect(safeScenario.simulated_total).toBe(3000);
      expect(safeScenario.limit_breached).toBe(false);
      expect(safeScenario.remaining_before).toBe(3000);
      expect(safeScenario.remaining_after).toBe(2000);
      expect(safeScenario.safe_daily_budget_after).toBeGreaterThan(0);

      // Scenario B: Deficit purchase (spend 3,500 ETB, exceeding the 5,000 limit)
      const breachScenario = await financeTools.simulateScenario(testUserId, {
        amount: 3500,
        category_id: categoryId,
      });

      expect(breachScenario.current_spent).toBe(2000);
      expect(breachScenario.simulated_total).toBe(5500);
      expect(breachScenario.limit_breached).toBe(true);
      expect(breachScenario.remaining_after).toBe(-500);
      expect(breachScenario.days_in_deficit).toBeGreaterThan(0);
      expect(breachScenario.recommended_cap).toBe(3000);
    });

    it('getBudgetStatus: calculates percentage utilization and status flags across all limits', async () => {
      const status = await financeTools.getBudgetStatus(testUserId);

      expect(status.active_limits.length).toBe(1);
      const diningLimit = status.active_limits[0];
      expect(diningLimit.scope_name).toBe('Dining & Cafes');
      expect(diningLimit.limit_amount).toBe(5000);
      expect(diningLimit.spent).toBe(2000);
      expect(diningLimit.remaining).toBe(3000);
      expect(diningLimit.percentage_used).toBe(40);
      expect(diningLimit.status).toBe('safe');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 2. pgvector Episodic Memory & Contradiction Resolution
  // ─────────────────────────────────────────────────────────────
  describe('Episodic Vector Memory (pgvector + Contradiction Resolution)', () => {
    let memory1Id: string;
    let memory2Id: string;

    it('adds and retrieves user episodic memory with vector embeddings', async () => {
      const res = await supertest(app.server)
        .post('/v1/ai/memories')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          kind: 'goal',
          content: 'Saving for a MacBook Pro M3 with a target of 120,000 ETB by December.',
          importance: 5,
          pinned: true,
        });

      expect(res.status).toBe(201);
      expect(res.body.id).toBeDefined();
      expect(res.body.kind).toBe('goal');
      memory1Id = res.body.id;

      // Query memories via semantic search
      const results = await aiMemoryService.searchMemories(testUserId, 'laptop savings target', 5);
      expect(results.length).toBeGreaterThanOrEqual(1);
      const match = results.find((m) => m.id === memory1Id);
      expect(match).toBeDefined();
      expect(match.final_score).toBeGreaterThan(0);
    });

    it('automatically supersedes contradicted memories when updated goals are added', async () => {
      // User updates their goal with higher amount
      const res = await supertest(app.server)
        .post('/v1/ai/memories')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          kind: 'goal',
          content: 'Saving for a MacBook Pro M3 with a target of 145,000 ETB by December.',
          importance: 5,
          pinned: true,
        });

      expect(res.status).toBe(201);
      memory2Id = res.body.id;

      // Prior memory should be marked as superseded
      const prior = await prisma.aiMemory.findUnique({ where: { id: memory1Id } });
      expect(prior?.supersededBy).toBe(memory2Id);

      // Search query should now only return the active, non-superseded memory
      const activeResults = await aiMemoryService.searchMemories(testUserId, 'MacBook savings goal', 5);
      expect(activeResults.some((m) => m.id === memory1Id)).toBe(false);
      expect(activeResults.some((m) => m.id === memory2Id)).toBe(true);
    });

    it('lists memories and supports soft-deletion', async () => {
      const listRes = await supertest(app.server)
        .get('/v1/ai/memories')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(listRes.status).toBe(200);
      expect(Array.isArray(listRes.body.memories)).toBe(true);

      // Delete memory
      const delRes = await supertest(app.server)
        .delete(`/v1/ai/memories/${memory2Id}`)
        .set('Authorization', `Bearer ${accessToken}`);

      expect(delRes.status).toBe(204);

      // Verify excluded from search
      const activeAfterDel = await aiMemoryService.searchMemories(testUserId, 'MacBook goal', 5);
      expect(activeAfterDel.some((m) => m.id === memory2Id)).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 3. AI Chat Streaming (Server-Sent Events)
  // ─────────────────────────────────────────────────────────────
  describe('AI Streaming Chat (/v1/ai/threads/:id/messages)', () => {
    it('creates an AI conversation thread', async () => {
      const res = await supertest(app.server)
        .post('/v1/ai/threads')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ title: 'Weekend Dining Inquiry' });

      expect(res.status).toBe(201);
      expect(res.body.id).toBeDefined();
      expect(res.body.title).toBe('Weekend Dining Inquiry');
      threadId = res.body.id;
    });

    it('streams chat response via SSE with tool execution and mathematical fidelity', async () => {
      const res = await supertest(app.server)
        .post(`/v1/ai/threads/${threadId}/messages`)
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ content: 'Can I afford to spend 2500 ETB on dining tonight?' });

      expect(res.status).toBe(200);
      expect(res.headers['content-type']).toContain('text/event-stream');

      // Parse SSE events from response text
      const rawText = res.text;
      expect(rawText).toContain('event: tool_start');
      expect(rawText).toContain('event: tool_end');
      expect(rawText).toContain('event: delta');
      expect(rawText).toContain('event: done');

      // Verify tool execution results in the stream
      expect(rawText).toContain('simulate_scenario');
      expect(rawText).toContain('"amount":2500');

      // Verify messages recorded in thread
      const messagesRes = await supertest(app.server)
        .get(`/v1/ai/threads/${threadId}/messages`)
        .set('Authorization', `Bearer ${accessToken}`);

      expect(messagesRes.status).toBe(200);
      expect(messagesRes.body.length).toBe(2); // 1 user + 1 assistant
      const assistantMsg = messagesRes.body.find((m: any) => m.role === 'assistant');
      expect(assistantMsg).toBeDefined();
      expect(assistantMsg.tokensUsed).toBeGreaterThan(0);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 4. Token Budget Enforcement & Proposals
  // ─────────────────────────────────────────────────────────────
  describe('Token Budget Enforcement & Proposals', () => {
    it('GET /v1/ai/usage returns token consumption and reset timestamp', async () => {
      const usageRes = await supertest(app.server)
        .get('/v1/ai/usage')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(usageRes.status).toBe(200);
      expect(usageRes.body.monthly_limit).toBe(50000);
      expect(usageRes.body.tokens_consumed).toBeGreaterThan(0);
      expect(usageRes.body.resets_at).toBeDefined();
    });

    it('enforces monthly quota cutoff with HTTP 429 when budget is exhausted', async () => {
      const currentMonth = new Date().toISOString().slice(0, 7);
      // Artificially simulate quota exhaustion
      await prisma.aiUsage.upsert({
        where: { userId_month: { userId: testUserId, month: currentMonth } },
        create: { userId: testUserId, month: currentMonth, tokensConsumed: 50000 },
        update: { tokensConsumed: 50000 },
      });

      const res = await supertest(app.server)
        .post(`/v1/ai/threads/${threadId}/messages`)
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ content: 'How much have I spent today?' });

      expect(res.status).toBe(429);
      expect(res.body.detail).toContain('budget reached');

      // Restore quota for subsequent tests
      await prisma.aiUsage.update({
        where: { userId_month: { userId: testUserId, month: currentMonth } },
        data: { tokensConsumed: 1000 },
      });
    });

    it('manages AI proposals lifecycle (create, list, and decide)', async () => {
      // 1. Create a proposal
      const proposal = await prisma.aiProposal.create({
        data: {
          userId: testUserId,
          kind: 'adjust_limit',
          payload: {
            category_id: categoryId,
            suggested_amount: 6500.0,
            reason: 'Consistently spending near 5,000 ETB limit',
          },
        },
      });

      // 2. Fetch proposals
      const listRes = await supertest(app.server)
        .get('/v1/ai/proposals')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(listRes.status).toBe(200);
      expect(listRes.body.length).toBeGreaterThanOrEqual(1);

      // 3. User accepts proposal
      const decideRes = await supertest(app.server)
        .post(`/v1/ai/proposals/${proposal.id}/decision`)
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ decision: 'accepted' });

      expect(decideRes.status).toBe(200);
      expect(decideRes.body.status).toBe('accepted');
      expect(decideRes.body.decidedAt).toBeDefined();
    });
  });
});
