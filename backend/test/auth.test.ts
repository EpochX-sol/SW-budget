import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { FastifyInstance } from 'fastify';
import supertest from 'supertest';
import { buildApp } from '../src/app.js';
import { prisma } from '../src/db/prisma.js';
import { hashPassword, verifyPassword, generateRefreshToken, hashToken } from '../src/utils/crypto.js';

describe('Milestone B1: Deep Authentication & Security Test Suite', { timeout: 15000 }, () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    app = await buildApp();
    await app.ready();

    // Clean up test users from previous runs
    await prisma.user.deleteMany({
      where: {
        email: {
          in: [
            'test_b1_user@example.com',
            'test_b1_user2@example.com',
            'test_b1_reuse@example.com',
          ],
        },
      },
    });
  });

  afterAll(async () => {
    // Cleanup created test records
    await prisma.user.deleteMany({
      where: {
        email: {
          in: [
            'test_b1_user@example.com',
            'test_b1_user2@example.com',
            'test_b1_reuse@example.com',
          ],
        },
      },
    });

    await app.close();
    await prisma.$disconnect();
  });

  // ─────────────────────────────────────────────────────────────
  // 1. Cryptographic Primitive Tests
  // ─────────────────────────────────────────────────────────────
  describe('Cryptographic & Hashing Primitives', () => {
    it('Argon2id hashes password securely and verifies correctly', async () => {
      const password = 'StrongPassword123!';
      const hash = await hashPassword(password);

      expect(hash).toContain('$argon2id$');
      const isValid = await verifyPassword(hash, password);
      expect(isValid).toBe(true);

      const isInvalid = await verifyPassword(hash, 'WrongPassword!');
      expect(isInvalid).toBe(false);
    });

    it('generateRefreshToken produces unique tokens and deterministic SHA-256 hashes', () => {
      const pair1 = generateRefreshToken();
      const pair2 = generateRefreshToken();

      expect(pair1.token).toMatch(/^rt_[a-f0-9]{64}$/);
      expect(pair2.token).toMatch(/^rt_[a-f0-9]{64}$/);
      expect(pair1.token).not.toBe(pair2.token);

      const calculatedHash = hashToken(pair1.token);
      expect(pair1.hash).toBe(calculatedHash);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 2. User Registration Integration Tests
  // ─────────────────────────────────────────────────────────────
  describe('User Registration (POST /v1/auth/register)', () => {
    const validDevice = {
      id: '018f3a5b-9b42-7c30-9b32-e02165849201',
      device_name: 'Tecno Camon 20 Pro',
      platform: 'android' as const,
      app_version: '1.0.0',
    };

    it('successfully registers a user, initial sync state, and bound device', async () => {
      const res = await supertest(app.server)
        .post('/v1/auth/register')
        .send({
          email: 'test_b1_user@example.com',
          password: 'ValidPassword123!',
          display_name: 'Samuel Test',
          currency: 'ETB',
          timezone: 'Africa/Addis_Ababa',
          month_start_day: 1,
          device: validDevice,
        });

      expect(res.status).toBe(201);
      expect(res.body).toHaveProperty('access_token');
      expect(res.body).toHaveProperty('refresh_token');
      expect(res.body.expires_in).toBe(900);
      expect(res.body.user.email).toBe('test_b1_user@example.com');
      expect(res.body.user.display_name).toBe('Samuel Test');

      // Verify in DB that UserSyncState initialized to 0
      const dbSyncState = await prisma.userSyncState.findUnique({
        where: { userId: res.body.user.id },
      });
      expect(dbSyncState).toBeDefined();
      expect(Number(dbSyncState?.seq)).toBe(0);

      // Verify Device record in DB
      const dbDevice = await prisma.device.findUnique({
        where: { id: validDevice.id },
      });
      expect(dbDevice).toBeDefined();
      expect(dbDevice?.userId).toBe(res.body.user.id);
      expect(dbDevice?.refreshTokenHash).toBeDefined();
    });

    it('rejects duplicate email with 409 Conflict', async () => {
      const res = await supertest(app.server)
        .post('/v1/auth/register')
        .send({
          email: 'test_b1_user@example.com',
          password: 'AnotherPassword123!',
          device: {
            id: '018f3a5b-9b42-7c30-9b32-e02165849202',
            device_name: 'Samsung Galaxy A54',
            platform: 'android',
            app_version: '1.0.0',
          },
        });

      expect(res.status).toBe(409);
      expect(res.body.title).toBe('Conflict');
      expect(res.body.detail).toContain('already exists');
    });

    it('rejects weak password with 400 Bad Request', async () => {
      const res = await supertest(app.server)
        .post('/v1/auth/register')
        .send({
          email: 'test_b1_weak@example.com',
          password: 'weak',
          device: validDevice,
        });

      expect(res.status).toBe(400);
      expect(res.body.title).toBe('Validation Error');
      expect(res.body.detail).toContain('at least 8 characters');
    });

    it('rejects invalid device UUID with 400 Bad Request', async () => {
      const res = await supertest(app.server)
        .post('/v1/auth/register')
        .send({
          email: 'test_b1_user2@example.com',
          password: 'ValidPassword123!',
          device: {
            id: 'not-a-valid-uuid',
            device_name: 'My Phone',
            platform: 'android',
            app_version: '1.0.0',
          },
        });

      expect(res.status).toBe(400);
      expect(res.body.title).toBe('Validation Error');
      expect(res.body.detail).toContain('valid UUID');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 3. User Login Integration Tests
  // ─────────────────────────────────────────────────────────────
  describe('User Login (POST /v1/auth/login)', () => {
    const loginDevice = {
      id: '018f3a5b-9b42-7c30-9b32-e02165849201',
      device_name: 'Tecno Camon 20 Pro',
      platform: 'android' as const,
      app_version: '1.0.1',
    };

    it('logs in successfully with correct credentials and issues tokens', async () => {
      const res = await supertest(app.server)
        .post('/v1/auth/login')
        .send({
          email: 'test_b1_user@example.com',
          password: 'ValidPassword123!',
          device: loginDevice,
        });

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('access_token');
      expect(res.body).toHaveProperty('refresh_token');
      expect(res.body.user.email).toBe('test_b1_user@example.com');

      // Device app_version updated in DB
      const dbDevice = await prisma.device.findUnique({
        where: { id: loginDevice.id },
      });
      expect(dbDevice?.appVersion).toBe('1.0.1');
    });

    it('rejects incorrect password with 401 Unauthorized', async () => {
      const res = await supertest(app.server)
        .post('/v1/auth/login')
        .send({
          email: 'test_b1_user@example.com',
          password: 'IncorrectPassword!',
          device: loginDevice,
        });

      expect(res.status).toBe(401);
      expect(res.body.title).toBe('Unauthorized');
      expect(res.body.detail).toContain('Invalid email or password');
    });

    it('rejects non-existent email with 401 Unauthorized', async () => {
      const res = await supertest(app.server)
        .post('/v1/auth/login')
        .send({
          email: 'does_not_exist@example.com',
          password: 'AnyPassword123!',
          device: loginDevice,
        });

      expect(res.status).toBe(401);
      expect(res.body.title).toBe('Unauthorized');
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 4. Single-Use Refresh Token Rotation & Replay Attack Defense
  // ─────────────────────────────────────────────────────────────
  describe('Refresh Token Rotation & Security (POST /v1/auth/refresh)', () => {
    let initialRefreshToken: string;
    const reuseDeviceId = '018f3a5b-9b42-7c30-9b32-e02165849999';

    beforeAll(async () => {
      // Register dedicated user for rotation tests
      const res = await supertest(app.server)
        .post('/v1/auth/register')
        .send({
          email: 'test_b1_reuse@example.com',
          password: 'ValidPassword123!',
          device: {
            id: reuseDeviceId,
            device_name: 'Infinix Note 30',
            platform: 'android',
            app_version: '1.0.0',
          },
        });
      initialRefreshToken = res.body.refresh_token;
    });

    it('successfully rotates refresh token on valid request', async () => {
      const res = await supertest(app.server)
        .post('/v1/auth/refresh')
        .send({
          refresh_token: initialRefreshToken,
          device_id: reuseDeviceId,
        });

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('access_token');
      expect(res.body).toHaveProperty('refresh_token');
      expect(res.body.refresh_token).not.toBe(initialRefreshToken);

      // Verify the new token works for the next rotation
      const nextRes = await supertest(app.server)
        .post('/v1/auth/refresh')
        .send({
          refresh_token: res.body.refresh_token,
          device_id: reuseDeviceId,
        });
      expect(nextRes.status).toBe(200);
    });

    it('detects replay attack when old refresh token is reused, revoking session', async () => {
      // Attempting to reuse initialRefreshToken (which was already rotated)
      const res = await supertest(app.server)
        .post('/v1/auth/refresh')
        .send({
          refresh_token: initialRefreshToken,
          device_id: reuseDeviceId,
        });

      expect(res.status).toBe(401);
      expect(res.body.detail).toContain('Token reuse detected');

      // Verify in DB that the device's token hash was wiped
      const device = await prisma.device.findUnique({
        where: { id: reuseDeviceId },
      });
      expect(device?.refreshTokenHash).toBeNull();
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 5. Logout & Protected Route Access
  // ─────────────────────────────────────────────────────────────
  describe('Logout & Profile Verification (GET /v1/me, POST /v1/auth/logout)', () => {
    let accessToken: string;
    const testDeviceId = '018f3a5b-9b42-7c30-9b32-e02165849201';

    beforeAll(async () => {
      // Login to get fresh valid access token
      const res = await supertest(app.server)
        .post('/v1/auth/login')
        .send({
          email: 'test_b1_user@example.com',
          password: 'ValidPassword123!',
          device: {
            id: testDeviceId,
            device_name: 'Tecno Camon 20 Pro',
            platform: 'android',
            app_version: '1.0.1',
          },
        });
      accessToken = res.body.access_token;
    });

    it('accesses GET /v1/me with valid Bearer token', async () => {
      const res = await supertest(app.server)
        .get('/v1/me')
        .set('Authorization', `Bearer ${accessToken}`);

      expect(res.status).toBe(200);
      expect(res.body.email).toBe('test_b1_user@example.com');
      expect(res.body.sync_seq).toBe(0);
      expect(Array.isArray(res.body.devices)).toBe(true);
      expect(res.body.devices.length).toBeGreaterThanOrEqual(1);
    });

    it('rejects GET /v1/me without token with 401 Unauthorized', async () => {
      const res = await supertest(app.server).get('/v1/me');
      expect(res.status).toBe(401);
      expect(res.body.title).toBe('Unauthorized');
    });

    it('rejects GET /v1/me with tampered token with 401 Unauthorized', async () => {
      const res = await supertest(app.server)
        .get('/v1/me')
        .set('Authorization', 'Bearer invalid.tampered.token');

      expect(res.status).toBe(401);
      expect(res.body.title).toBe('Unauthorized');
    });

    it('successfully logs out and revokes device session', async () => {
      const res = await supertest(app.server)
        .post('/v1/auth/logout')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          device_id: testDeviceId,
        });

      expect(res.status).toBe(204);

      // Verify in DB that refreshTokenHash was cleared
      const device = await prisma.device.findUnique({
        where: { id: testDeviceId },
      });
      expect(device?.refreshTokenHash).toBeNull();
    });
  });
});
