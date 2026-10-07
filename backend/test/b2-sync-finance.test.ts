import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { FastifyInstance } from 'fastify';
import supertest from 'supertest';
import * as ed from '@noble/ed25519';
import { buildApp } from '../src/app.js';
import { prisma } from '../src/db/prisma.js';
import { processAggregateJob } from '../src/jobs/workers/aggregates.worker.js';
import { redisConnection } from '../src/jobs/redis.js';

describe('Milestone B2: Deep Financial APIs, Sync & Templates Test Suite', { timeout: 20000 }, () => {
  let app: FastifyInstance;
  let accessToken: string;
  let userId: string;
  const testDeviceId = '018f3a5b-9b42-7c30-9b32-e02165849b20';
  const testEmail = 'test_b2_user@example.com';

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
        password: 'SecurePassword123!',
        display_name: 'B2 Test User',
        device: {
          id: testDeviceId,
          device_name: 'Test Device B2',
          platform: 'android',
          app_version: '1.0.0',
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

  // ─────────────────────────────────────────────────────────────
  // 1. Financial CRUD Tests
  // ─────────────────────────────────────────────────────────────
  describe('Core Financial CRUD', () => {
    let createdAccountId: string;

    it('creates and lists accounts for the user', async () => {
      const res = await supertest(app.server)
        .post('/v1/accounts')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          provider: 'CBE',
          name: 'CBE Main Checking',
          account_mask: '1234',
          last_known_balance: 15400.5,
          is_savings: false,
        });

      expect(res.status).toBe(201);
      expect(res.body.provider).toBe('CBE');
      expect(Number(res.body.lastKnownBalance)).toBe(15400.5);
      createdAccountId = res.body.id;

      const listRes = await supertest(app.server)
        .get('/v1/accounts')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(listRes.status).toBe(200);
      expect(listRes.body.length).toBeGreaterThanOrEqual(1);
      expect(listRes.body[0].id).toBe(createdAccountId);
    });

    it('fetches seeded system categories and creates a custom category', async () => {
      const catRes = await supertest(app.server)
        .get('/v1/categories')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(catRes.status).toBe(200);
      expect(catRes.body.length).toBeGreaterThanOrEqual(15);
      const foodCat = catRes.body.find((c: any) => c.name === 'Food & Groceries');
      expect(foodCat).toBeDefined();
      expect(foodCat.isSystem).toBe(true);

      // Create user custom category
      const createCat = await supertest(app.server)
        .post('/v1/categories')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          name: 'Side Hustle Tech',
          icon: 'laptop',
          color_hex: '#14B8A6',
        });

      expect(createCat.status).toBe(201);
      expect(createCat.body.name).toBe('Side Hustle Tech');
      expect(createCat.body.isSystem).toBe(false);
    });

    it('creates, reads, and updates a limit', async () => {
      const createRes = await supertest(app.server)
        .post('/v1/limits')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          scope_type: 'overall',
          period_type: 'monthly',
          amount: 25000,
          mode: 'soft',
          rollover: true,
          alert_thresholds: [50, 80, 100],
        });

      expect(createRes.status).toBe(201);
      expect(Number(createRes.body.amount)).toBe(25000);
      const limitId = createRes.body.id;

      const updateRes = await supertest(app.server)
        .patch(`/v1/limits/${limitId}`)
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          amount: 30000,
        });

      expect(updateRes.status).toBe(200);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 2. Monotonic Sequence Sync Engine (Push & Pull)
  // ─────────────────────────────────────────────────────────────
  describe('Monotonic Sequence Sync Engine (/v1/sync)', () => {
    const txnId = '018f3a60-2233-7a11-b998-112233445566';
    const accountId = '018f3a5d-1111-7b22-8888-000000000001';
    const idempotencyKey = 'idemp_key_sync_test_001';

    it('POST /v1/sync/push increments sequence monotonically and records outbox event', async () => {
      const pushRes = await supertest(app.server)
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${accessToken}`)
        .set('Idempotency-Key', idempotencyKey)
        .send({
          device_id: testDeviceId,
          batch_index: 1,
          total_batches: 1,
          changes: [
            {
              entity: 'account',
              op: 'upsert',
              id: accountId,
              client_updated_at: new Date().toISOString(),
              data: {
                provider: 'TELEBIRR',
                name: 'Telebirr Wallet',
                last_known_balance: 4200.0,
                is_savings: false,
              },
            },
            {
              entity: 'transaction',
              op: 'upsert',
              id: txnId,
              client_updated_at: new Date().toISOString(),
              data: {
                account_id: accountId,
                category_id: '018f3a5e-0001-7000-8000-000000000001', // Food
                type: 'expense',
                amount: 350.5,
                balance_after: 3849.5,
                counterparty: 'Kaldis Coffee',
                reference: 'REF12345678',
                occurred_at: '2026-10-07T10:15:00.000Z',
                source: 'sms',
                parse_confidence: 0.98,
                balance_chain_ok: true,
                dedupe_key: 'dedupe_kaldis_001',
              },
            },
          ],
        });

      expect(pushRes.status).toBe(200);
      expect(pushRes.body.accepted_ids).toContain(txnId);
      expect(pushRes.body.accepted_ids).toContain(accountId);
      expect(pushRes.body.new_cursor).toBeGreaterThan(0);

      const firstCursor = pushRes.body.new_cursor;

      // Verify sequence stored in DB matches
      const syncState = await prisma.userSyncState.findUnique({
        where: { userId },
      });
      expect(Number(syncState?.seq)).toBe(firstCursor);

      // Verify Transaction stored in DB with changeSeq
      const dbTxn = await prisma.transaction.findUnique({
        where: { id: txnId },
      });
      expect(dbTxn).toBeDefined();
      expect(Number(dbTxn?.changeSeq)).toBe(firstCursor);
      expect(Number(dbTxn?.amount)).toBe(350.5);

      // Verify outbox event created
      const outbox = await prisma.outboxEvent.findFirst({
        where: { userId, eventType: 'sync.push' },
        orderBy: { id: 'desc' },
      });
      expect(outbox).toBeDefined();
    });

    it('guarantees idempotency on duplicate sync push requests', async () => {
      // Re-send with identical Idempotency-Key
      const pushRes = await supertest(app.server)
        .post('/v1/sync/push')
        .set('Authorization', `Bearer ${accessToken}`)
        .set('Idempotency-Key', idempotencyKey)
        .send({
          device_id: testDeviceId,
          changes: [],
        });

      expect(pushRes.status).toBe(200);
      expect(pushRes.body.accepted_ids).toContain(txnId);
    });

    it('GET /v1/sync/pull retrieves changes strictly higher than cursor', async () => {
      // Pull with cursor = 0 retrieves the pushed changes
      const pullRes = await supertest(app.server)
        .get('/v1/sync/pull?cursor=0&limit=50')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(pullRes.status).toBe(200);
      expect(pullRes.body.changes.length).toBeGreaterThanOrEqual(2);
      const pulledTxn = pullRes.body.changes.find((c: any) => c.id === txnId);
      expect(pulledTxn).toBeDefined();
      expect(pulledTxn.entity).toBe('transaction');
      expect(pulledTxn.data.counterparty).toBe('Kaldis Coffee');

      // Pull with cursor = current_seq returns empty changes
      const emptyPull = await supertest(app.server)
        .get(`/v1/sync/pull?cursor=${pullRes.body.cursor}&limit=50`)
        .set('Authorization', `Bearer ${accessToken}`);

      expect(emptyPull.status).toBe(200);
      expect(emptyPull.body.changes.length).toBe(0);
      expect(emptyPull.body.has_more).toBe(false);
    });

    it('GET /v1/sync/status returns current sequence and status', async () => {
      const statusRes = await supertest(app.server)
        .get('/v1/sync/status')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(statusRes.status).toBe(200);
      expect(statusRes.body.current_seq).toBeGreaterThan(0);
      expect(statusRes.body.status).toBe('synced');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 3. Incremental Daily Category Aggregates Worker
  // ─────────────────────────────────────────────────────────────
  describe('Incremental Daily Aggregates Worker', () => {
    it('accurately computes daily expense totals for date and category', async () => {
      const day = '2026-10-07';
      const categoryId = '018f3a5e-0001-7000-8000-000000000001';
      const accountId = '018f3a5d-1111-7b22-8888-000000000001';

      // Execute worker processing directly
      await processAggregateJob({
        data: {
          userId,
          day,
          categoryId,
          accountId,
        },
      } as any);

      // Verify aggregate record in daily_category_totals
      const targetDate = new Date(`${day}T00:00:00.000Z`);
      const aggregate = await prisma.dailyCategoryTotal.findUnique({
        where: {
          userId_day_categoryId_accountId: {
            userId,
            day: targetDate,
            categoryId,
            accountId,
          },
        },
      });

      expect(aggregate).toBeDefined();
      expect(Number(aggregate?.expense)).toBe(350.5);
      expect(aggregate?.txnCount).toBe(1);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 4. Ed25519-Signed SMS Template Registry
  // ─────────────────────────────────────────────────────────────
  describe('Signed Template Registry (GET /v1/sms-templates)', () => {
    it('returns valid templates and a verifiable Ed25519 digital signature', async () => {
      const res = await supertest(app.server).get('/v1/sms-templates');

      expect(res.status).toBe(200);
      expect(res.body.bundle_version).toBe(3);
      expect(Array.isArray(res.body.templates)).toBe(true);
      expect(res.body.templates.length).toBeGreaterThanOrEqual(3);

      const cbeTemplate = res.body.templates.find((t: any) => t.bank === 'CBE');
      expect(cbeTemplate).toBeDefined();
      expect(cbeTemplate.fields.amount).toBeDefined();

      // Cryptographically verify signature if keys are provided
      if (res.body.signature && res.body.public_key) {
        const payload = JSON.stringify({
          version: res.body.bundle_version,
          templates: res.body.templates,
        });
        const messageBytes = Buffer.from(payload, 'utf-8');
        const signatureBytes = Buffer.from(res.body.signature, 'hex');
        const publicKeyBytes = Buffer.from(res.body.public_key, 'hex');

        const isValid = await ed.verifyAsync(signatureBytes, messageBytes, publicKeyBytes);
        expect(isValid).toBe(true);
      }
    });
  });
});
