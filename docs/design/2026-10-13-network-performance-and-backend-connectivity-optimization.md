# Design Doc: Network Performance, Latency Optimization & Resilient Backend Connectivity

## 1. Metadata
- **Status**: Proposed
- **Author**: Antigravity Assistant & Samuel
- **Date**: 2026-10-13
- **Type**: Architecture & Performance Optimization
- **Related Links**:
  - `mobile/lib/data/remote/api_client.dart`
  - `mobile/lib/data/remote/auth_interceptor.dart`
  - `mobile/lib/data/remote/api_endpoints.dart`
  - `backend/src/jobs/redis.ts`
  - `backend/src/modules/health/health.routes.ts`
  - `backend/src/modules/sync/sync.service.ts`
- **Confidence**: High (Root causes verified by live curl probes, latency benchmarks, and code audit).

---

## 2. Summary
Users currently experience `"The request took too long to complete. Please check your network connection."` starting from the login screen and across backend calls. 

Diagnostic tracing and live HTTP probes pinpointed two primary culprits:
1. **Backend Blocking on Down/Unreachable Redis**: In `backend/src/jobs/redis.ts`, ioredis is initialized with `maxRetriesPerRequest: null` without timeouts or offline queue protection. When deployed on cloud environments (Render) where a local Redis daemon (`127.0.0.1:6379`) is absent or unreachable:
   - `/health` hangs indefinitely because `await redisConnection.ping()` never resolves or times out.
   - `/v1/sync/push` hangs indefinitely because `await redisConnection.get(cacheKey)` blocks the request pipeline.
2. **Mobile Client Configuration & Premature Timeouts**:
   - `mobile/lib/data/remote/api_client.dart` enforces tight 15s connection / 20s receive timeouts, which fail on cloud free-tier cold starts (Render takes 30–45s to wake from sleep).
   - In `mobile/lib/data/remote/auth_interceptor.dart`, `ApiEndpoints.refresh` was duplicated back-to-back: the first request consumed the single-use refresh token, and the second request immediately failed with a revoked token error.
   - The mobile app had no mechanism to inspect, test, or override the backend server URL (e.g. for testing on local Wi-Fi IP `http://192.168.x.x:3000`).
   - The app did not perform pre-emptive server wake-up/keep-alive on app launch, forcing users to wait through cold boots on user-triggered actions like Login.

This design presents an end-to-end performance and resilience upgrade across both backend and frontend layers to make backend communication fast, non-blocking, and fault-tolerant.

---

## 3. Problem / Motivation
- When users attempt to log in or sync, they receive a timeout error despite having a strong, active internet connection.
- A live curl test revealed:
  - `GET /` responds immediately in 0.44s with Fastify 404.
  - `POST /v1/auth/login` responds in 0.35s with validation error when payload is sent.
  - `GET /health` hangs for >60s because `redisConnection.ping()` waits forever for a non-existent local Redis instance.
  - `POST /v1/sync/push` with idempotency key attempts Redis operations that hang.
- Render free tier puts containers into sleep mode after 15 minutes of inactivity; waking up takes ~30–40s. The mobile app's 15s timeout cuts off requests prematurely before the server finishes waking.
- Mobile users have no visibility or control over which backend URL the app talks to.

---

## 4. Goals
1. **Zero-Hang Backend Services**: Make Redis completely non-blocking, optional, and resilient with strict 1.5s timeouts so no endpoint (`/health`, `/v1/sync/push`, etc.) ever hangs if Redis is offline.
2. **Cold-Start Resilience & Optimized Timeouts**:
   - Increase mobile HTTP timeouts to 45s connection / 60s receive to comfortably accommodate server cold starts.
   - Implement pre-warming on app launch (`GET /health` or probe) so Render wakes up immediately in the background while the user opens the app or enters credentials.
3. **Fix `auth_interceptor.dart` Bug**: Eliminate the duplicate refresh call that prematurely invalidates rotating refresh tokens.
4. **Configurable Server Address**:
   - Add persistent `api_base_url` storage in `SecureStorageService` / settings.
   - Provide an "Edit Server URL" action in Settings and on the Login screen so users/developers can switch between Render (`https://sw-budget.onrender.com`), local network (`http://192.168.1.X:3000`), or custom deployments.
5. **Connection Pooling & Keep-Alive**: Optimize Dio with HTTP/1.1 and keep-alive connection pooling to eliminate TCP/TLS renegotiation overhead on successive calls.

---

## 5. Non-Goals
- Replacing PostgreSQL or Neon database with a local database only.
- Removing Redis completely (Redis remains supported when available; it is simply made non-blocking when unavailable).

---

## 6. Proposed Design

### 6.1 Backend Architecture: Non-Blocking Redis & Fast Health
```
                +---------------------------------------+
                |         Incoming HTTP Request         |
                +---------------------------------------+
                                    |
                    +---------------+---------------+
                    |                               |
              [/health]                     [/v1/sync/push]
                    |                               |
       +------------+------------+                  |
       |                         |                  v
   [Neon DB]               [Redis Ping]     [Idempotency Check]
 (SELECT 1)           (Promise.race 1.5s)   (Non-blocking probe)
       |                         |                  |
       v                         v                  |
   db: "up"             redis: "up" | "down"        |
       \                         /                  |
        +-----------+-----------+                   |
                    |                               |
             Response: 200/503                      |
              (Within 50ms!)                        |
                                                    v
                                      +---------------------------+
                                      | Is Redis Connected?       |
                                      +---------------------------+
                                         /                    \
                                     (YES)                    (NO)
                                       /                        \
                            Check Redis cache            Direct DB execution
                                       \                        /
                                        +-----------+----------+
                                                    |
                                          Apply DB Batch in Neon
                                                    |
                                          Return 200 OK Fast!
```

1. **`backend/src/jobs/redis.ts`**:
   - Configure `enableOfflineQueue: false` for direct client commands.
   - Add `connectTimeout: 3000`, `commandTimeout: 2000`, and error event listeners so unhandled connection failures never crash the event loop or hang promises.
   - Export an `isRedisHealthy()` helper.

2. **`backend/src/modules/health/health.routes.ts`**:
   - Wrap `redisConnection.ping()` with `Promise.race([..., setTimeout(..., 1500)])`.
   - Returns 200 immediately if DB is up, reporting Redis as `'down'` or `'degraded'` without stalling the HTTP response.

3. **`backend/src/modules/sync/sync.service.ts`**:
   - Wrap Redis idempotency checks and caching in `try/catch` with fast fallback. If Redis fails or is down, bypass caching and proceed immediately with atomic DB transaction.

### 6.2 Mobile Architecture: Resilient Networking & Server Configuration
```
   +-------------------------------------------------------------+
   |                       Mobile App Launch                     |
   +-------------------------------------------------------------+
                                  |
                                  v
                  +-------------------------------+
                  | Load Active Server Base URL   |
                  | (SecureStorage -> Default)    |
                  +-------------------------------+
                                  |
                   +--------------+---------------+
                   |                              |
                   v                              v
        [Background Wakeup Probe]      [User Navigates UI]
        - Fire non-blocking ping       - Login / Home Screen
        - Wakes Render container       - Zero latency on user click!
        - Silently handled in bg
```

1. **`mobile/lib/data/remote/api_client.dart`**:
   - `connectTimeout: const Duration(seconds: 40)`
   - `receiveTimeout: const Duration(seconds: 60)`
   - `sendTimeout: const Duration(seconds: 40)`
   - Add pre-warming method `prewarmServer()`.

2. **`mobile/lib/data/remote/auth_interceptor.dart`**:
   - Remove redundant second refresh call.
   - Increase refresh client timeout to 30 seconds.

3. **`mobile/lib/features/onboarding/login_screen.dart`**:
   - Add server settings modal / chip allowing user to switch or verify the backend URL (`https://sw-budget.onrender.com` vs custom IP/URL).
   - On screen init, trigger background `prewarmServer()` so by the time user finishes typing, Render is awake.

---

## 7. API / Interface Changes
- No breaking API request/response shape changes.
- Added optional query param `?timeout=...` support on `/health`.

---

## 8. Data Model Changes
- N/A. No schema changes required.

---

## 9. Alternatives Considered
1. **Host Backend only locally on Android Emulator (`10.0.2.2`)**:
   - *Pros*: Extremely fast for local emulator.
   - *Cons*: Fails completely on real physical Android devices running over Wi-Fi/4G without USB reverse proxy.
2. **Keep strict 15s timeout and force users to retry**:
   - *Pros*: Fails fast.
   - *Cons*: Poor UX on any serverless/sleep cloud host. Render cold starts take 30s+, causing guaranteed failure on the first attempt.
3. **Resilient Non-Blocking Redis + 40s Timeout + Pre-warming (Selected)**:
   - *Pros*: Solves root cause in backend (no hangs on Redis), accommodates cold starts, wakes up server in background, and gives user control over server URL.

---

## 10. Impact & Risks
- **Performance**: High positive impact. Endpoints respond in <300ms instead of hanging for 20–60s.
- **Security**: Server URL changes are stored encrypted in Android Keystore via `FlutterSecureStorage`.
- **Backward Compatibility**: Fully compatible. Default URL remains `https://sw-budget.onrender.com`.

---

## 11. Implementation Plan
1. **Backend**:
   - Update `backend/src/jobs/redis.ts` with non-blocking timeouts (`enableOfflineQueue: false`, `commandTimeout: 2000`).
   - Update `backend/src/modules/health/health.routes.ts` with bounded race timeout on Redis ping.
   - Update `backend/src/modules/sync/sync.service.ts` with resilient Redis try/catch fallback.
   - Verify backend builds and runs tests cleanly.
2. **Mobile**:
   - Update `mobile/lib/data/remote/auth_interceptor.dart` (remove duplicate refresh call, fix single-flight queue).
   - Update `mobile/lib/data/remote/api_client.dart` (raise timeouts to 40s/60s, add prewarming).
   - Update `mobile/lib/data/remote/api_client_provider.dart` and `SecureStorageService` to support customizable `api_base_url`.
   - Add server URL configuration bottom sheet / chip in `login_screen.dart` and `settings_screen.dart`.
   - Update `main.dart` to trigger background server pre-warming on app launch.
3. **Build & Verification**:
   - Test backend with `npm run build` and live HTTP ping.
   - Run `flutter analyze`.
   - Build new release APK with `flutter build apk --release`.

---

## 12. Testing Strategy
- **Unit & Smoke Tests**: Test `/health` with Redis simulated down; verify response is returned in <100ms.
- **Mobile Integration**: Verify login and sync with 40s timeout and server pre-warming.
- **Diagnostics**: Run curl benchmarks to ensure zero-hanging endpoints.

---

## 13. Rollout / Migration Plan
- Immediate rollout into codebase.
- Rebuild release APK.
- Rollback: Revert commit if needed.

---

## 14. Open Questions
- None.

---

## 15. References
- RFC 7807 Problem Details
- ioredis offline queue and retry strategy documentation
- Render.com Web Services Spin-Down Documentation

---

## 16. Decision Log
- **2026-10-13**: Initial design formulated and submitted for approval.
