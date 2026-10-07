import { randomUUID } from 'node:crypto';
import { env } from '../src/config/env.js';

const BASE_URL = `http://127.0.0.1:${env.PORT}`;

interface ApiResponse {
  status: number;
  data: any;
}

async function request(path: string, options: RequestInit = {}): Promise<ApiResponse> {
  const url = `${BASE_URL}${path}`;
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string> || {}),
  };

  const res = await fetch(url, {
    ...options,
    headers,
  });

  let data = null;
  const contentType = res.headers.get('content-type') || '';
  if (contentType.includes('application/json')) {
    data = await res.json();
  }

  return { status: res.status, data };
}

async function runE2e() {
  console.log(`\n======================================================`);
  console.log(`🚀 STARTING LIVE END-TO-END BACKEND API VERIFICATION`);
  console.log(`Target: ${BASE_URL}`);
  console.log(`======================================================\n`);

  let step = 1;

  // Step 1: Health Check
  console.log(`[Step ${step++}] Testing GET /health...`);
  const health = await request('/health');
  if (health.status !== 200 || health.data.status !== 'ok') {
    throw new Error(`Health check failed: ${JSON.stringify(health)}`);
  }
  console.log(`  ✔ Health check OK: DB=${health.data.services.database}, Vector=${health.data.services.vector_extension}`);

  // Test data with unique timestamp
  const timestamp = Date.now();
  const testEmail = `e2e_user_${timestamp}@example.com`;
  const testPassword = 'E2E_SecurePassword123!';
  const deviceId = randomUUID();

  // Step 2: Register User
  console.log(`\n[Step ${step++}] Testing POST /v1/auth/register...`);
  const register = await request('/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      email: testEmail,
      password: testPassword,
      display_name: 'E2E Test User',
      currency: 'ETB',
      timezone: 'Africa/Addis_Ababa',
      month_start_day: 1,
      device: {
        id: deviceId,
        device_name: 'Pixel 8 Pro E2E',
        platform: 'android',
        app_version: '1.0.0',
      },
    }),
  });

  if (register.status !== 201 || !register.data.access_token) {
    throw new Error(`Registration failed: ${JSON.stringify(register)}`);
  }
  console.log(`  ✔ User registered: id=${register.data.user.id}, email=${register.data.user.email}`);
  const initialAccessToken = register.data.access_token;
  const initialRefreshToken = register.data.refresh_token;

  // Step 3: Duplicate Registration Rejection
  console.log(`\n[Step ${step++}] Testing duplicate registration rejection (409 Conflict)...`);
  const duplicate = await request('/v1/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      email: testEmail,
      password: testPassword,
      device: {
        id: randomUUID(),
        device_name: 'Secondary Device',
        platform: 'android',
        app_version: '1.0.0',
      },
    }),
  });
  if (duplicate.status !== 409) {
    throw new Error(`Expected 409 Conflict, got: ${duplicate.status}`);
  }
  console.log(`  ✔ Duplicate registration rejected correctly with HTTP 409 Conflict`);

  // Step 4: Login with Valid Credentials
  console.log(`\n[Step ${step++}] Testing POST /v1/auth/login...`);
  const login = await request('/v1/auth/login', {
    method: 'POST',
    body: JSON.stringify({
      email: testEmail,
      password: testPassword,
      device: {
        id: deviceId,
        device_name: 'Pixel 8 Pro E2E',
        platform: 'android',
        app_version: '1.0.1',
      },
    }),
  });
  if (login.status !== 200 || !login.data.access_token) {
    throw new Error(`Login failed: ${JSON.stringify(login)}`);
  }
  console.log(`  ✔ Login successful, token issued`);
  const loginAccessToken = login.data.access_token;
  const loginRefreshToken = login.data.refresh_token;

  // Step 5: Login with Wrong Password Rejection
  console.log(`\n[Step ${step++}] Testing login with bad password (401 Unauthorized)...`);
  const badLogin = await request('/v1/auth/login', {
    method: 'POST',
    body: JSON.stringify({
      email: testEmail,
      password: 'IncorrectPassword!',
      device: {
        id: deviceId,
        device_name: 'Pixel 8 Pro E2E',
        platform: 'android',
        app_version: '1.0.1',
      },
    }),
  });
  if (badLogin.status !== 401) {
    throw new Error(`Expected 401 Unauthorized, got: ${badLogin.status}`);
  }
  console.log(`  ✔ Bad password rejected with HTTP 401 Unauthorized`);

  // Step 6: Authenticated Profile (GET /v1/me)
  console.log(`\n[Step ${step++}] Testing GET /v1/me with Bearer token...`);
  const profile = await request('/v1/me', {
    headers: {
      Authorization: `Bearer ${loginAccessToken}`,
    },
  });
  if (profile.status !== 200 || profile.data.email !== testEmail) {
    throw new Error(`Profile fetch failed: ${JSON.stringify(profile)}`);
  }
  console.log(`  ✔ Protected profile accessible: email=${profile.data.email}, sync_seq=${profile.data.sync_seq}, devices=${profile.data.devices.length}`);

  // Step 7: Protected Route Rejection without Token
  console.log(`\n[Step ${step++}] Testing GET /v1/me without token (401 Unauthorized)...`);
  const unauth = await request('/v1/me');
  if (unauth.status !== 401) {
    throw new Error(`Expected 401 for unauthenticated request, got: ${unauth.status}`);
  }
  console.log(`  ✔ Unauthenticated access rejected with HTTP 401 Unauthorized`);

  // Step 8: Token Refresh with Rotation
  console.log(`\n[Step ${step++}] Testing POST /v1/auth/refresh (Token Rotation)...`);
  const refresh = await request('/v1/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({
      refresh_token: loginRefreshToken,
      device_id: deviceId,
    }),
  });
  if (refresh.status !== 200 || !refresh.data.access_token || !refresh.data.refresh_token) {
    throw new Error(`Token refresh failed: ${JSON.stringify(refresh)}`);
  }
  if (refresh.data.refresh_token === loginRefreshToken) {
    throw new Error('Refresh token was not rotated!');
  }
  console.log(`  ✔ Refresh token rotated successfully to new token`);
  const rotatedAccessToken = refresh.data.access_token;
  const rotatedRefreshToken = refresh.data.refresh_token;

  // Step 9: Replay Attack Defense (Reusing old refresh token)
  console.log(`\n[Step ${step++}] Testing replay attack defense (reusing old refresh token)...`);
  const replay = await request('/v1/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({
      refresh_token: loginRefreshToken, // Old already-rotated token!
      device_id: deviceId,
    }),
  });
  if (replay.status !== 401) {
    throw new Error(`Expected 401 for token replay attack, got: ${replay.status}`);
  }
  console.log(`  ✔ Token reuse detected: session revoked with HTTP 401`);

  // Step 10: Verify Session Invalidation after Replay Attack
  console.log(`\n[Step ${step++}] Verifying session is invalidated after replay attack...`);
  const invalidatedRefresh = await request('/v1/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({
      refresh_token: rotatedRefreshToken,
      device_id: deviceId,
    }),
  });
  if (invalidatedRefresh.status !== 401) {
    throw new Error(`Expected session to be revoked after replay, got: ${invalidatedRefresh.status}`);
  }
  console.log(`  ✔ Device session confirmed revoked`);

  // Step 11: Re-login for Milestone B2 financial operations
  console.log(`\n[Step ${step++}] Re-authenticating for Milestone B2 financial operations...`);
  const reLogin = await request('/v1/auth/login', {
    method: 'POST',
    body: JSON.stringify({
      email: testEmail,
      password: testPassword,
      device: {
        id: deviceId,
        device_name: 'Pixel 8 Pro E2E',
        platform: 'android',
        app_version: '1.0.1',
      },
    }),
  });
  const activeToken = reLogin.data.access_token;
  const authHeaders = { Authorization: `Bearer ${activeToken}` };

  // Step 12: Accounts Creation & Listing (POST & GET /v1/accounts)
  console.log(`\n[Step ${step++}] Testing POST /v1/accounts...`);
  const createAccount = await request('/v1/accounts', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({
      name: 'Primary CBE Account',
      provider: 'CBE',
      account_number_mask: '...9876',
      initial_balance: 15000.0,
      currency: 'ETB',
    }),
  });
  if (createAccount.status !== 201 || !createAccount.data.id) {
    throw new Error(`Create account failed: ${JSON.stringify(createAccount)}`);
  }
  const accountId = createAccount.data.id;
  console.log(`  ✔ Account created: id=${accountId}, provider=${createAccount.data.provider}`);

  console.log(`\n[Step ${step++}] Testing GET /v1/accounts...`);
  const listAccounts = await request('/v1/accounts', {
    headers: authHeaders,
  });
  if (listAccounts.status !== 200 || !Array.isArray(listAccounts.data) || listAccounts.data.length === 0) {
    throw new Error(`List accounts failed: ${JSON.stringify(listAccounts)}`);
  }
  console.log(`  ✔ Accounts retrieved: count=${listAccounts.data.length}`);

  // Step 13: Categories (GET & POST /v1/categories)
  console.log(`\n[Step ${step++}] Testing GET /v1/categories (seeded defaults)...`);
  const listCategories = await request('/v1/categories', {
    headers: authHeaders,
  });
  if (listCategories.status !== 200 || !Array.isArray(listCategories.data) || listCategories.data.length === 0) {
    throw new Error(`List categories failed: ${JSON.stringify(listCategories)}`);
  }
  const defaultCategory = listCategories.data[0];
  console.log(`  ✔ Categories retrieved: total=${listCategories.data.length}, first=${defaultCategory.name}`);

  console.log(`\n[Step ${step++}] Testing POST /v1/categories (custom category)...`);
  const createCategory = await request('/v1/categories', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({
      name: 'Traditional Coffee Ceremony',
      icon: 'coffee',
      color_hex: '#8B4513',
    }),
  });
  if (createCategory.status !== 201 || !createCategory.data.id) {
    throw new Error(`Create category failed: ${JSON.stringify(createCategory)}`);
  }
  const customCatId = createCategory.data.id;
  console.log(`  ✔ Custom category created: id=${customCatId}, name=${createCategory.data.name}`);

  // Step 14: Limits (POST & PATCH /v1/limits)
  console.log(`\n[Step ${step++}] Testing POST /v1/limits...`);
  const createLimit = await request('/v1/limits', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({
      scope_type: 'category',
      scope_id: customCatId,
      period_type: 'monthly',
      amount: 4500.0,
    }),
  });
  if (createLimit.status !== 201 || !createLimit.data.id) {
    throw new Error(`Create limit failed: ${JSON.stringify(createLimit)}`);
  }
  const limitId = createLimit.data.id;
  console.log(`  ✔ Limit created: id=${limitId}, amount=${createLimit.data.amount}`);

  console.log(`\n[Step ${step++}] Testing PATCH /v1/limits/:id...`);
  const updateLimit = await request(`/v1/limits/${limitId}`, {
    method: 'PATCH',
    headers: authHeaders,
    body: JSON.stringify({
      amount: 5500.0,
    }),
  });
  if (updateLimit.status !== 200 || !updateLimit.data.success) {
    throw new Error(`Update limit failed: ${JSON.stringify(updateLimit)}`);
  }
  console.log(`  ✔ Limit updated successfully: success=${updateLimit.data.success}`);

  // Step 15: Sequence Sync Push (POST /v1/sync/push)
  console.log(`\n[Step ${step++}] Testing POST /v1/sync/push (Monotonic Sync Engine)...`);
  const clientTxId = randomUUID();
  const syncPushKey = `sync-key-${timestamp}`;
  const syncPayload = {
    device_id: deviceId,
    batch_index: 1,
    total_batches: 1,
    changes: [
      {
        entity: 'transaction' as const,
        op: 'upsert' as const,
        id: clientTxId,
        client_updated_at: new Date().toISOString(),
        data: {
          account_id: accountId,
          category_id: customCatId,
          type: 'expense',
          amount: 280.5,
          occurred_at: new Date().toISOString(),
          source: 'sms',
          counterparty: 'Buna Tetu',
          dedupe_key: `dedupe_${timestamp}`,
        },
      },
    ],
  };

  const syncPush = await request('/v1/sync/push', {
    method: 'POST',
    headers: {
      ...authHeaders,
      'Idempotency-Key': syncPushKey,
    },
    body: JSON.stringify(syncPayload),
  });
  if (syncPush.status !== 200 || !syncPush.data.accepted_ids.includes(clientTxId)) {
    throw new Error(`Sync push failed: ${JSON.stringify(syncPush)}`);
  }
  console.log(`  ✔ Sync push processed: accepted_ids=${syncPush.data.accepted_ids.join(',')}, cursor=${syncPush.data.new_cursor}`);

  // Step 16: Idempotent Sync Push Verification
  console.log(`\n[Step ${step++}] Testing duplicate sync push idempotency...`);
  const duplicatePush = await request('/v1/sync/push', {
    method: 'POST',
    headers: {
      ...authHeaders,
      'Idempotency-Key': syncPushKey,
    },
    body: JSON.stringify(syncPayload),
  });
  if (duplicatePush.status !== 200 || duplicatePush.data.new_cursor !== syncPush.data.new_cursor) {
    throw new Error(`Idempotency check failed: ${JSON.stringify(duplicatePush)}`);
  }
  console.log(`  ✔ Idempotent sync push returned cached response with cursor=${duplicatePush.data.new_cursor}`);

  // Step 17: Sequence Sync Pull (GET /v1/sync/pull)
  console.log(`\n[Step ${step++}] Testing GET /v1/sync/pull?cursor=0...`);
  const syncPull = await request('/v1/sync/pull?cursor=0&limit=50', {
    headers: authHeaders,
  });
  if (syncPull.status !== 200 || !Array.isArray(syncPull.data.changes) || syncPull.data.changes.length === 0) {
    throw new Error(`Sync pull failed: ${JSON.stringify(syncPull)}`);
  }
  console.log(`  ✔ Sync pull retrieved changes: count=${syncPull.data.changes.length}, cursor=${syncPull.data.cursor}`);

  // Step 18: Sync Status (GET /v1/sync/status)
  console.log(`\n[Step ${step++}] Testing GET /v1/sync/status...`);
  const syncStatus = await request('/v1/sync/status', {
    headers: authHeaders,
  });
  if (syncStatus.status !== 200 || syncStatus.data.current_seq < 1) {
    throw new Error(`Sync status failed: ${JSON.stringify(syncStatus)}`);
  }
  console.log(`  ✔ Sync status verified: current_seq=${syncStatus.data.current_seq}`);

  // Step 19: Ed25519 Signed SMS Templates (GET /v1/sms-templates)
  console.log(`\n[Step ${step++}] Testing GET /v1/sms-templates & Ed25519 signature...`);
  const templatesRes = await request('/v1/sms-templates');
  if (templatesRes.status !== 200 || !Array.isArray(templatesRes.data.templates)) {
    throw new Error(`Templates fetch failed: ${JSON.stringify(templatesRes)}`);
  }
  console.log(`  ✔ Signed templates retrieved: version=${templatesRes.data.bundle_version}, count=${templatesRes.data.templates.length}, sig_len=${templatesRes.data.signature.length}`);

  // Step 20: AI Thread Creation (POST /v1/ai/threads)
  console.log(`\n[Step ${step++}] Testing POST /v1/ai/threads...`);
  const createThread = await request('/v1/ai/threads', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({ title: 'Live AI Budget Consultation' }),
  });
  if (createThread.status !== 201 || !createThread.data.id) {
    throw new Error(`Create thread failed: ${JSON.stringify(createThread)}`);
  }
  const threadId = createThread.data.id;
  console.log(`  ✔ AI Thread created: id=${threadId}, title=${createThread.data.title}`);

  // Step 21: Add AI Episodic Memory (POST /v1/ai/memories)
  console.log(`\n[Step ${step++}] Testing POST /v1/ai/memories (pgvector)...`);
  const addMemory = await request('/v1/ai/memories', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({
      kind: 'goal',
      content: 'Saving for a Toyota RAV4 with a target of 4,500,000 ETB.',
      importance: 5,
      pinned: true,
    }),
  });
  if (addMemory.status !== 201 || !addMemory.data.id) {
    throw new Error(`Add memory failed: ${JSON.stringify(addMemory)}`);
  }
  console.log(`  ✔ Episodic memory created: id=${addMemory.data.id}, kind=${addMemory.data.kind}`);

  // Step 22: List Memories (GET /v1/ai/memories)
  console.log(`\n[Step ${step++}] Testing GET /v1/ai/memories...`);
  const listMemories = await request('/v1/ai/memories', {
    headers: authHeaders,
  });
  if (listMemories.status !== 200 || !Array.isArray(listMemories.data.memories) || listMemories.data.memories.length === 0) {
    throw new Error(`List memories failed: ${JSON.stringify(listMemories)}`);
  }
  console.log(`  ✔ Memories retrieved: count=${listMemories.data.memories.length}`);

  // Step 23: Live SSE Chat Streaming (POST /v1/ai/threads/:id/messages)
  console.log(`\n[Step ${step++}] Testing POST /v1/ai/threads/:id/messages (Live SSE Streaming Chat)...`);
  const sseRes = await fetch(`${BASE_URL}/v1/ai/threads/${threadId}/messages`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${activeToken}`,
    },
    body: JSON.stringify({ content: 'Can I afford to spend 1500 ETB on coffee ceremony today?' }),
  });
  if (sseRes.status !== 200) {
    throw new Error(`SSE streaming failed with status ${sseRes.status}`);
  }
  const sseBody = await sseRes.text();
  if (!sseBody.includes('event: tool_start') || !sseBody.includes('event: done')) {
    throw new Error(`Incomplete SSE response: ${sseBody}`);
  }
  console.log(`  ✔ SSE Streaming response received: tool_start & done events verified`);

  // Step 24: Check AI Token Usage (GET /v1/ai/usage)
  console.log(`\n[Step ${step++}] Testing GET /v1/ai/usage...`);
  const usage = await request('/v1/ai/usage', {
    headers: authHeaders,
  });
  if (usage.status !== 200 || usage.data.tokens_consumed <= 0) {
    throw new Error(`Usage fetch failed: ${JSON.stringify(usage)}`);
  }
  console.log(`  ✔ AI Token quota verified: consumed=${usage.data.tokens_consumed} / ${usage.data.monthly_limit}`);

  // Step 25: Notification Preferences (GET /v1/notifications/preferences)
  console.log(`\n[Step ${step++}] Testing GET /v1/notifications/preferences...`);
  const notifPrefs = await request('/v1/notifications/preferences', {
    headers: authHeaders,
  });
  if (notifPrefs.status !== 200 || notifPrefs.data.dailyCap === undefined) {
    throw new Error(`Notification preferences failed: ${JSON.stringify(notifPrefs)}`);
  }
  console.log(`  ✔ Notification preferences retrieved: dailyCap=${notifPrefs.data.dailyCap}, quiet=${notifPrefs.data.quietStart}-${notifPrefs.data.quietEnd}`);

  // Step 26: Financial Forecast (GET /v1/analytics/forecast)
  console.log(`\n[Step ${step++}] Testing GET /v1/analytics/forecast...`);
  const forecast = await request('/v1/analytics/forecast', {
    headers: authHeaders,
  });
  if (forecast.status !== 200 || !Array.isArray(forecast.data.points) || forecast.data.points.length !== 31) {
    throw new Error(`Forecast failed: ${JSON.stringify(forecast)}`);
  }
  console.log(`  ✔ Financial forecast calculated: 30-day burn rate=${forecast.data.daily_burn_rate} ETB/day, points=${forecast.data.points.length}`);

  // Step 27: Category Trends (GET /v1/analytics/trends)
  console.log(`\n[Step ${step++}] Testing GET /v1/analytics/trends...`);
  const trends = await request('/v1/analytics/trends', {
    headers: authHeaders,
  });
  if (trends.status !== 200 || !Array.isArray(trends.data.category_breakdown)) {
    throw new Error(`Trends failed: ${JSON.stringify(trends)}`);
  }
  console.log(`  ✔ Trends analyzed: current month spent=${trends.data.current_month_total} ETB, categories=${trends.data.category_breakdown.length}`);

  // Step 28: Export Job & Download (POST & GET /v1/export/jobs)
  console.log(`\n[Step ${step++}] Testing POST /v1/export/jobs (Excel Export)...`);
  const exportJob = await request('/v1/export/jobs', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({}),
  });
  if (exportJob.status !== 202 || !exportJob.data.job_id) {
    throw new Error(`Export job failed: ${JSON.stringify(exportJob)}`);
  }
  const exportDownload = await fetch(`${BASE_URL}/v1/export/jobs/${exportJob.data.job_id}/download`, {
    headers: { Authorization: `Bearer ${activeToken}` },
  });
  if (exportDownload.status !== 200) {
    throw new Error(`Download export failed: ${exportDownload.status}`);
  }
  const excelBuffer = await exportDownload.arrayBuffer();
  console.log(`  ✔ Excel workbook exported successfully: size=${excelBuffer.byteLength} bytes`);

  // Step 29: Encrypted Backup (POST /v1/backup)
  console.log(`\n[Step ${step++}] Testing POST /v1/backup (AES-256-GCM Encrypted .swbackup)...`);
  const backupPassword = 'MySecretBackupPassphrase!';
  const backupRes = await fetch(`${BASE_URL}/v1/backup`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${activeToken}`,
    },
    body: JSON.stringify({ password: backupPassword }),
  });
  if (backupRes.status !== 200) {
    throw new Error(`Backup failed: ${backupRes.status}`);
  }
  const backupBytes = Buffer.from(await backupRes.arrayBuffer());
  if (backupBytes.subarray(0, 9).toString() !== 'SWBACKUP1') {
    throw new Error('Invalid backup magic header');
  }
  console.log(`  ✔ Encrypted backup created: size=${backupBytes.length} bytes, magic=SWBACKUP1`);

  // Step 30: Restore Encrypted Backup (POST /v1/backup/restore)
  console.log(`\n[Step ${step++}] Testing POST /v1/backup/restore (Decryption & Entity Restoration)...`);
  const restore = await request('/v1/backup/restore', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({
      password: backupPassword,
      backup_data_base64: backupBytes.toString('base64'),
    }),
  });
  if (restore.status !== 200 || !restore.data.success) {
    throw new Error(`Restore failed: ${JSON.stringify(restore)}`);
  }
  console.log(`  ✔ Encrypted backup restored: success=${restore.data.success}, accounts=${restore.data.accounts_count}`);

  // Step 31: Prometheus Metrics (GET /metrics)
  console.log(`\n[Step ${step++}] Testing GET /metrics (Prometheus Observability)...`);
  const metricsRes = await fetch(`${BASE_URL}/metrics`);
  if (metricsRes.status !== 200) {
    throw new Error(`Metrics failed: ${metricsRes.status}`);
  }
  const metricsText = await metricsRes.text();
  if (!metricsText.includes('sw_budget_')) {
    throw new Error('Metrics missing sw_budget_ prefix');
  }
  console.log(`  ✔ Prometheus metrics operational: sw_budget_ metrics verified`);

  // Step 32: Clean Logout
  console.log(`\n[Step ${step++}] Testing POST /v1/auth/logout...`);
  const logout = await request('/v1/auth/logout', {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({
      device_id: deviceId,
    }),
  });
  if (logout.status !== 204) {
    throw new Error(`Logout failed: ${JSON.stringify(logout)}`);
  }
  console.log(`  ✔ Final logout succeeded with HTTP 204 No Content`);

  console.log(`\n================================================================`);
  console.log(`🎉 ALL 32 END-TO-END CHECKS (B1 + B2 + B3 + B4) PASSED WITH 100%!`);
  console.log(`================================================================\n`);
}

runE2e()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('❌ E2E Test Failure:', err);
    process.exit(1);
  });
