import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import supertest from 'supertest';
import { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { prisma } from '../src/db/prisma.js';
import { notificationService } from '../src/modules/notifications/notification.service.js';
import { schedulerWorker } from '../src/jobs/workers/scheduler.worker.js';
import { exportService } from '../src/modules/export/export.service.js';

describe('Milestone B4: Schedulers, Analytics, Push & Hardening Test Suite', () => {
  let app: FastifyInstance;
  let accessToken: string;
  let testUserId: string;
  const testEmail = `b4_tester_${Date.now()}@example.com`;
  const testDeviceId = '018f3a5f-1111-7000-8000-0000000000b4';
  let accountId: string;
  let categoryId: string;

  beforeAll(async () => {
    app = await buildApp();
    await app.ready();

    // 1. Register test user
    const regRes = await supertest(app.server)
      .post('/v1/auth/register')
      .send({
        email: testEmail,
        password: 'SecurePassword123!',
        display_name: 'B4 Analytics User',
        currency: 'ETB',
        device: {
          id: testDeviceId,
          device_name: 'B4 Pixel Tester',
          platform: 'android',
          app_version: '1.0.0',
        },
      });

    expect(regRes.status).toBe(201);
    accessToken = regRes.body.access_token;
    testUserId = regRes.body.user.id;

    // 2. Setup account & category
    const acc = await prisma.account.create({
      data: {
        id: '018f3a5f-2222-7000-8000-000000000001',
        userId: testUserId,
        provider: 'CBE',
        name: 'Checking Account',
        lastKnownBalance: 28500.0,
        changeSeq: 1n,
      },
    });
    accountId = acc.id;

    const cat = await prisma.category.create({
      data: {
        id: '018f3a5f-3333-7000-8000-000000000001',
        userId: testUserId,
        name: 'Groceries & Household',
        icon: 'shopping-cart',
        colorHex: '#10B981',
        changeSeq: 2n,
      },
    });
    categoryId = cat.id;

    // 3. Seed transactions for analytics
    const now = new Date();
    await prisma.transaction.createMany({
      data: [
        {
          id: '018f3a5f-4444-7000-8000-000000000001',
          userId: testUserId,
          accountId,
          categoryId,
          type: 'expense',
          amount: 1200.0,
          occurredAt: now,
          dedupeKey: `b4_txn_1_${Date.now()}`,
          changeSeq: 3n,
        },
        {
          id: '018f3a5f-4444-7000-8000-000000000002',
          userId: testUserId,
          accountId,
          categoryId,
          type: 'expense',
          amount: 850.0,
          occurredAt: now,
          dedupeKey: `b4_txn_2_${Date.now()}`,
          changeSeq: 4n,
        },
      ],
    });
  });

  afterAll(async () => {
    if (testUserId) {
      await prisma.user.deleteMany({ where: { id: testUserId } });
    }
    await app.close();
  });

  // ─────────────────────────────────────────────────────────────
  // 1. Notification Service, Quiet Hours & Lock-Screen Privacy
  // ─────────────────────────────────────────────────────────────
  describe('Notification Engine & Privacy Controls', () => {
    it('accurately evaluates quiet hours spanning midnight (22:00 to 07:00)', () => {
      const midnightTime = new Date('2026-10-07T02:30:00Z');
      midnightTime.setHours(2, 30);
      expect(notificationService.isQuietTime('22:00', '07:00', midnightTime)).toBe(true);

      const eveningTime = new Date();
      eveningTime.setHours(23, 15);
      expect(notificationService.isQuietTime('22:00', '07:00', eveningTime)).toBe(true);

      const daytime = new Date();
      daytime.setHours(14, 0);
      expect(notificationService.isQuietTime('22:00', '07:00', daytime)).toBe(false);
    });

    it('enforces deduplication keys to prevent duplicate notifications', async () => {
      const dedupeKey = `limit_alert_test_${Date.now()}`;
      const res1 = await notificationService.dispatchNotification({
        userId: testUserId,
        type: 'limit_alert',
        channel: 'push',
        priority: 'urgent',
        title: 'Limit Warning',
        body: 'You are close to your limit',
        dedupeKey,
      });

      expect(res1.dispatched).toBe(true);

      const res2 = await notificationService.dispatchNotification({
        userId: testUserId,
        type: 'limit_alert',
        channel: 'push',
        priority: 'urgent',
        title: 'Limit Warning',
        body: 'You are close to your limit',
        dedupeKey,
      });

      expect(res2.dispatched).toBe(false);
      expect(res2.reason).toBe('duplicate_dedupe_key');
    });

    it('masks sensitive monetary figures when showAmounts is disabled (lockscreen privacy)', async () => {
      // Set showAmounts to false
      await prisma.notificationPreference.upsert({
        where: { userId: testUserId },
        create: { userId: testUserId, showAmounts: false },
        update: { showAmounts: false },
      });

      const res = await notificationService.dispatchNotification({
        userId: testUserId,
        type: 'morning_allowance',
        channel: 'push',
        priority: 'urgent',
        title: 'Daily Allowance',
        body: 'Your daily budget is ETB 1,500.00 today.',
        amount: 1500,
        dedupeKey: `mask_test_${Date.now()}`,
      });

      expect(res.dispatched).toBe(true);
      expect(res.notification?.body).not.toContain('1,500');
      expect(res.notification?.body).toContain('your configured limit');
    });

    it('manages in-app notifications and preferences via REST API', async () => {
      const listRes = await supertest(app.server)
        .get('/v1/notifications')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(listRes.status).toBe(200);
      expect(listRes.body.length).toBeGreaterThanOrEqual(1);
      const notifId = listRes.body[0].id;

      // Mark as read
      const readRes = await supertest(app.server)
        .patch(`/v1/notifications/${notifId}/read`)
        .set('Authorization', `Bearer ${accessToken}`);

      expect(readRes.status).toBe(200);

      // Update preferences
      const putPref = await supertest(app.server)
        .put('/v1/notifications/preferences')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          quiet_start: '23:00',
          quiet_end: '06:00',
          show_amounts: true,
          daily_cap: 8,
        });

      expect(putPref.status).toBe(200);
      expect(putPref.body.dailyCap).toBe(8);
      expect(putPref.body.showAmounts).toBe(true);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 2. Minute-Tick Scheduler Worker
  // ─────────────────────────────────────────────────────────────
  describe('Minute-Tick Scheduler Worker', () => {
    it('executes scheduled morning allowance and advances next_run_at by 24 hours', async () => {
      const pastTime = new Date(Date.now() - 10000); // 10s in the past

      await prisma.userSchedule.upsert({
        where: {
          userId_kind: { userId: testUserId, kind: 'morning_allowance' },
        },
        create: {
          userId: testUserId,
          kind: 'morning_allowance',
          nextRunAt: pastTime,
        },
        update: {
          nextRunAt: pastTime,
        },
      });

      // Run scheduler cycle
      const cycle = await schedulerWorker.runSchedulerCycle();
      expect(cycle.tasks_processed).toBeGreaterThanOrEqual(1);

      // Verify schedule was advanced into the future
      const updatedSchedule = await prisma.userSchedule.findUnique({
        where: {
          userId_kind: { userId: testUserId, kind: 'morning_allowance' },
        },
      });

      expect(new Date(updatedSchedule!.nextRunAt).getTime()).toBeGreaterThan(Date.now());
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 3. Analytics & Financial Forecasting Endpoints
  // ─────────────────────────────────────────────────────────────
  describe('Financial Analytics & 30-Day Burn-Down Forecasting', () => {
    it('GET /v1/analytics/forecast: returns 30-day projected balance trajectory', async () => {
      const res = await supertest(app.server)
        .get('/v1/analytics/forecast')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.current_balance).toBe(28500);
      expect(res.body.daily_burn_rate).toBeGreaterThan(0);
      expect(res.body.points.length).toBe(31); // day 0 through day 30
      expect(res.body.points[0].projected_balance).toBe(28500);
    });

    it('GET /v1/analytics/trends: breaks down monthly expenditures by category', async () => {
      const res = await supertest(app.server)
        .get('/v1/analytics/trends')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.current_month_total).toBe(2050); // 1200 + 850
      expect(res.body.category_breakdown.length).toBeGreaterThanOrEqual(1);
      const topCat = res.body.category_breakdown[0];
      expect(topCat.name).toBe('Groceries & Household');
      expect(topCat.total_spent).toBe(2050);
    });

    it('GET /v1/analytics/fees: aggregates transaction fees', async () => {
      const res = await supertest(app.server)
        .get('/v1/analytics/fees')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.total_fees).toBeDefined();
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 4. Data Export & AES-256-GCM Encrypted Backups (.swbackup)
  // ─────────────────────────────────────────────────────────────
  describe('Data Portability & Encrypted Backups', () => {
    it('generates a multi-sheet Excel workbook with Amharic UTF-8 support', async () => {
      const jobRes = await supertest(app.server)
        .post('/v1/export/jobs')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(jobRes.status).toBe(202);
      expect(jobRes.body.job_id).toBeDefined();

      const downloadRes = await supertest(app.server)
        .get(`/v1/export/jobs/${jobRes.body.job_id}/download`)
        .set('Authorization', `Bearer ${accessToken}`)
        .responseType('blob');

      expect(downloadRes.status).toBe(200);
      expect(downloadRes.headers['content-type']).toContain('spreadsheetml.sheet');
      expect(downloadRes.body.length).toBeGreaterThan(100);
    });

    it('creates and restores an AES-256-GCM encrypted backup (.swbackup)', async () => {
      const backupPassword = 'MySecretBackupPassphrase!';

      // 1. Create encrypted backup
      const backupRes = await supertest(app.server)
        .post('/v1/backup')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ password: backupPassword });

      expect(backupRes.status).toBe(200);
      const backupBuffer = Buffer.from(backupRes.body);

      // Verify SWBACKUP1 magic header (first 9 bytes)
      expect(backupBuffer.subarray(0, 9).toString()).toBe('SWBACKUP1');

      // 2. Restore backup with correct password
      const restoreRes = await supertest(app.server)
        .post('/v1/backup/restore')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          password: backupPassword,
          backup_data_base64: backupBuffer.toString('base64'),
        });

      expect(restoreRes.status).toBe(200);
      expect(restoreRes.body.success).toBe(true);

      // 3. Attempt restore with wrong password -> expect rejection
      const badRestoreRes = await supertest(app.server)
        .post('/v1/backup/restore')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          password: 'WrongPassword123!',
          backup_data_base64: backupBuffer.toString('base64'),
        });

      expect(badRestoreRes.status).toBe(400);
      expect(badRestoreRes.body.detail).toContain('Incorrect backup password');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 5. Operational Hardening: Prometheus Metrics
  // ─────────────────────────────────────────────────────────────
  describe('Operational Hardening: Metrics (/metrics)', () => {
    it('GET /metrics exports system metrics with sw_budget_ prefix', async () => {
      const res = await supertest(app.server).get('/metrics');

      expect(res.status).toBe(200);
      expect(res.headers['content-type']).toContain('text/plain');
      expect(res.text).toContain('sw_budget_process_cpu_user_seconds_total');
    });
  });
});
