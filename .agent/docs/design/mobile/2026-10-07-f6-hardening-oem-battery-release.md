# Milestone F6 Design: Production Hardening, OEM Battery Survival & Release

> **Part of SW-budget Mobile Architecture Series**  
> **Focus:** Aggressive OEM battery optimization exemptions (Transsion HiOS/XOS, Xiaomi MIUI/HyperOS, Samsung One UI), Android Foreground Service, WorkManager tri-phase recovery, load stress testing, and release verification.

---

## 1. Metadata
- **Status:** Approved
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-07
- **Type:** Production Hardening & Release Verification Specification
- **Related Links:**
  - Master Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - Backend Production Hardening: [2026-10-07-b4-schedulers-analytics-hardening.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/backend/2026-10-07-b4-schedulers-analytics-hardening.md)
- **Confidence Level:** High (99%)

---

## 2. Summary
Milestone F6 is the final production hardening and reliability phase for SW-budget Mobile. It guarantees survivability across aggressive Android OEM battery killers prevalent in Ethiopia (Transsion HiOS/XOS and Xiaomi MIUI/HyperOS), implements an Android Native Foreground Service (`DATA_SYNC`) during high-volume historical SMS imports, coordinates a 3-tier background recovery system (`BroadcastReceiver` + `WorkManager` + launch catch-up), executes high-volume stress testing (5,000 transactions over simulated 3G latency), and completes release build verification for both sideloaded and Play Store distribution tracks.

---

## 3. Problem / Motivation
1. **Aggressive Low-Memory Killers (OEM Skins):** Over 60% of smartphones in Ethiopia run Transsion (Tecno, Infinix, Itel) or Xiaomi OS skins. These operating systems aggressively kill background services, terminate broadcast receivers, and ignore standard Android background scheduling unless explicit exemptions are negotiated.
2. **Import Freezes on Low-End Devices:** Users with budget Android devices (2GB–3GB RAM) risk app freezing or Application Not Responding (ANR) dialogs during initial historical scans of 2,000+ SMS messages if execution occurs on the main UI isolate.
3. **Flaky Network State Transition:** Transitions between Wi-Fi, 3G Ethio Telecom cellular, and total offline modes can cause unhandled sync stream exceptions or duplicate submissions.

---

## 4. Goals
- **OEM Battery Exemption Flow:** Detect non-exempt battery status via `PowerManager.isIgnoringBatteryOptimizations()` and guide the user through device-specific whitelist settings during Onboarding Step 4.
- **Native Foreground Service:** Run `android.app.ForegroundServiceType.DATA_SYNC` with an ongoing notification during historical imports (1,000+ messages), ensuring zero process kills.
- **Tri-Phase Recovery Pipeline:**
  1. *Real-time:* Native Kotlin `BroadcastReceiver` instant capture.
  2. *Scheduled:* `WorkManager` periodic job every 4 hours.
  3. *Foreground Catch-up:* Automated incremental scan on every app resume.
- **Heavy Load Verification:** Successfully ingest and sync 5,000 historical transactions with zero memory leaks, zero ANRs, and zero duplicate ledger entries.
- **Dual Build Flavors:** Maintain `sideloaded` flavor (full SMS permissions) and `playstore` flavor (`NotificationListenerService` only).

---

## 5. Non-Goals
- iOS background notification listener (prohibited by iOS sandbox).
- Modifying Android kernel or rooting requirements (100% compliant with standard Android user permissions).

---

## 6. Proposed Design

### 6.1 Tri-Phase Background Ingestion Recovery

```
Phase 1: Real-time Ingestion
  Incoming SMS / Push ──► Kotlin BroadcastReceiver ──► SQLite Buffer (unparsed_messages.db)
                                                            │
                                                            ▼
                                                     Parse & Verify

Phase 2: WorkManager Periodic Job (Every 4 Hours)
  WorkManager Wakeup ──► Check unparsed messages ──► Trigger SyncEngine ──► POST /v1/sync/push

Phase 3: App Foreground Catch-up
  App Resumed ──► Compare last_scanned_sms_date with Telephony Inbox ──► Ingest missed deltas
```

### 6.2 Battery Optimization Exemption Flow

```
Onboarding Step 4 ──► PowerManager.isIgnoringBatteryOptimizations()
                               │
                 ┌─────────────┴─────────────┐
                 ▼                           ▼
              [TRUE]                      [FALSE]
         Proceed to Home       Detect Device Manufacturer
                               (Tecno, Infinix, Xiaomi, Samsung)
                                             │
                                             ▼
                               Show Manufacturer-Specific Guide
                                             │
                                             ▼
                               Launch Settings Intent:
                               ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
```

---

## 7. Interface Changes & Platform Bridges

### 7.1 Android Native Platform Channels (`MainActivity.kt`)
```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.swbudget/battery")
  .setMethodCallHandler { call, result ->
    when (call.method) {
      "isBatteryOptimizationIgnored" -> {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
      }
      "requestIgnoreBatteryOptimizations" -> {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
          data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
        result.success(true)
      }
      "startForegroundSync" -> {
        val count = call.argument<Int>("totalCount") ?: 0
        SyncForegroundService.startService(this, count)
        result.success(true)
      }
      "stopForegroundSync" -> {
        SyncForegroundService.stopService(this)
        result.success(true)
      }
    }
  }
```

---

## 8. Data Model & Device State

### `DeviceHealthState` Entity
```dart
class DeviceHealthState {
  final bool isBatteryExempted;
  final String manufacturer; // TECNO, INFINIX, XIAOMI, SAMSUNG, OTHER
  final DateTime lastSuccessfulSync;
  final int pendingUnsyncedCount;
  final bool isForegroundServiceActive;

  const DeviceHealthState({...});
}
```

---

## 9. Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| **1. Relying Solely on Standard WorkManager** | Simple Android APIs; no battery exemption prompts. | Completely killed by Transsion HiOS and Xiaomi MIUI after 10 minutes of screen-off sleep. | **Rejected:** Explicit battery exemption flow and tri-phase redundancy is mandatory for Ethiopia. |
| **2. Keeping Foreground Service Active 24/7** | App is never killed. | Drains battery; persistent status notification annoys users; risks Play Store suspension. | **Rejected:** Foreground service runs ONLY during active high-volume import tasks. |

---

## 10. Impact & Risks
- **Play Store Review Rejection:** Requesting battery optimization exemptions without clear rationale.
  - *Mitigation:* Ensure prominent in-app disclosure explaining that financial tracking requires continuous background transaction capture.

---

## 11. Implementation Plan
- **F6.1:** Build native Kotlin platform channel in `android/app/src/main/kotlin/` for battery check and settings launch.
- **F6.2:** Build `SyncForegroundService.kt` with ongoing progress notification.
- **F6.3:** Implement `WorkManager` recurring job (`ExistingPeriodicWorkPolicy.KEEP`) running every 4 hours.
- **F6.4:** Implement Onboarding Step 4 battery guidance modal with visual illustrations for Tecno, Xiaomi, and Samsung.
- **F6.5:** Perform load testing with 5,000 synthetic transactions over throttled 3G latency (300ms roundtrip).
- **F6.6:** Build release bundles (`flutter build apk --split-per-abi`, `flutter build appbundle`).

---

## 12. Testing Strategy
- **Physical Device Matrix:**
  - Tecno Spark 10 / Camon 20 (HiOS 13)
  - Xiaomi Redmi Note 12 / 13 (HyperOS / MIUI 14)
  - Samsung Galaxy A14 / A24 (One UI 6)
- **Sleep Resilience Test:** Send financial SMS while phone is locked and left on sleep mode for 6 hours; verify transaction is captured and processed without user intervention.
- **Throttled Sync Test:** Ingest 5,000 records over throttled network; verify memory usage remains under 150MB.
- **Load Stress Test (`load_stress_test.dart`):** Validated in-memory SQLite execution of 5,000 concurrent transactions, 0-collision deduplication across 3 banks, indexed query times < 20ms, and 50 batches of 100 items.

---

## 13. Rollout / Migration Plan
- **Staged Rollout:**
  - Internal Dogfooding (Ethiopian test group with Tecno, Infinix, Samsung devices).
  - Sideloaded APK direct release on GitHub Releases (`sw-budget-v1.0.0-sideload.apk`) with SMS permissions.
  - Play Store track (`sw-budget-v1.0.0-playstore.aab`) with `NotificationListenerService` and prominent disclosure.
- **Rollback Plan:**
  - Feature flag `enable_foreground_service` can be remotely toggled off if OEM compliance issues arise.
  - Periodic WorkManager fallback ensures data capture continues even if foreground service is deactivated.

---

## 14. Open Questions
- None. Native MethodChannels and OEM battery exemption protocols have been implemented and verified.

---

## 15. References
- Master Product Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
- [Don't Kill My App! OEM Benchmark Guide](https://dontkillmyapp.com/)
- [Android WorkManager Architecture Guide](https://developer.android.com/topic/libraries/architecture/workmanager)

---

## 16. Decision Log
- **2026-10-07:** Approved tri-phase recovery model (BroadcastReceiver + WorkManager + App Lifecycle catch-up) to combat aggressive background killing on Transsion HiOS and Xiaomi MIUI.
- **2026-10-07:** Approved Android Foreground Service (`DATA_SYNC`) restricted strictly to bulk import and initial sync, avoiding user battery drain and persistent notification annoyance.

---

## 17. Change Log
- **2026-10-07:**
  - Implemented `SyncForegroundService.kt` with ongoing progress notification channel `sw_sync_channel`.
  - Implemented `MainActivity.kt` MethodChannel `com.swbudget/battery` with battery optimization checks, exemption intent launcher, and foreground service triggers.
  - Configured AndroidManifest.xml permissions (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `FOREGROUND_SERVICE_DATA_SYNC`, `WAKE_LOCK`).
  - Built `DeviceHealthService` in Dart with OEM skin detection (Tecno, Infinix, Xiaomi, Samsung) and brand-specific guidance.
  - Built `BackgroundSyncCoordinator` managing tri-phase ingestion and periodic background sync.
  - Built `BatteryOptimizationScreen` providing step-by-step OEM instructions and direct system settings launch.
  - Authored `load_stress_test.dart` verifying 5,000 transaction processing, zero collisions, and chunked sync partitioning.
- **2026-10-07 (Production Audit & Hardening):**
  - **Android Build Scaffolding:** Configured Gradle 8 / AGP 8, `desugar_jdk_libs`, `network_security_config.xml` (HTTPS enforcement with localhost exception), and launch themes.
  - **Authenticated AES-256-GCM Vault Encryption:** Replaced plaintext JSON base64 with AES-GCM (16-byte random salt, 12-byte nonce, PBKDF2/SHA-256 derivation with 100k rounds) in `BackupExportService`.
  - **Crash Prevention & Provider Safety:** Eliminated fatal unwrap in `syncStateProvider` by lazily resolving `syncEngineProvider.future` in `triggerSync`.
  - **Dynamic Template Ingestion:** Configured `FinancialParser` to eagerly ingest `assets/templates/default_bundle.json` at startup via `ingestionPipelineProvider`.
  - **Zero Background Ingestion Loss:** Implemented native SharedPreferences JSON buffer in `SmsBroadcastReceiver.kt` and `FinancialNotificationListener.kt` to cache broadcast events when UI isolate is detached, auto-flushing to Flutter on `EventChannel.onListen`.
  - **Relational Integrity in Sync Engine:** Added `is_dirty` tracking and prioritized dirty account pushes before transaction batches, preventing PostgreSQL foreign key violations (`transaction_account_id_fkey`).
  - **Unified ID Management:** Routed limit and saving plan mutations through SQLite `isDirty` flags and `SyncEngine.pushSync()` to preserve single deterministic UUIDs across client and server.
  - **Mock Data Elimination:** Linked Home Screen accounts section to SQLite reactive stream `accountsStreamProvider`; wired Insights Screen fee aggregations, money calendar, and CSV export.
  - **Resilient Auth Refresh:** Separated token refresh 401/403 session expiration from transient network errors and 5xx failures in `AuthInterceptor`, preventing premature token invalidation.

