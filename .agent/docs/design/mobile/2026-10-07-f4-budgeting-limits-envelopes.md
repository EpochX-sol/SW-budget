# Milestone F4 Design: Budgeting, Limits, Envelopes & Local Push

> **Part of SW-budget Mobile Architecture Series**  
> **Focus:** Safe-to-Spend dynamic arithmetic, circular gauge UI, envelope budgeting, liquid goal jars, and on-device offline threshold notifications (`flutter_local_notifications`).

---

## 1. Metadata
- **Status:** Approved
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-07
- **Type:** Feature Design & Implementation Specification
- **Related Links:**
  - Master Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - Backend Limits API: [api-documentation.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/api-documentation.md#budget-limits)
- **Confidence Level:** High (99%)

---

## 2. Summary
Milestone F4 delivers the financial intelligence and budgeting user experience of SW-budget. It introduces the daily **Safe-to-Spend** circular ring, envelope budgeting across overall, category, and account limits, animated liquid saving goal jars, and instant on-device threshold alerting (50%, 80%, 100%) that triggers immediately upon transaction ingestion even without internet connectivity.

---

## 3. Problem / Motivation
1. **The "Static Budget" Failure:** Traditional budgeting apps tell users they have 10,000 ETB for the month, but do not provide an actionable daily allowance that dynamically recalculates when spending spikes or dips.
2. **Late Cloud Alerts:** Cloud-based push notifications arrive minutes or hours after a transaction occurred if the user is in an area with poor connectivity.
3. **Lock-Screen Financial Leakage:** Sensitive balance amounts flashing on lock screens risk personal privacy in crowded public transport (e.g. Addis Ababa light rail or minibuses).

---

## 4. Goals
- **Safe-to-Spend Arithmetic:** Dynamically compute daily allowance accounting for elapsed days, recurring bills, and savings contributions.
- **Glanceable Circular Ring:** Interactive animated gauge with pace markers (Green = Ahead of pace, Amber = Approaching limit, Red = Deficit).
- **Envelope Budgeting:** Soft limits (informational warning) and Hard limits (strict alert) across categories and accounts.
- **Visual Goal Jars:** Animated liquid wave level representing progress towards saving targets.
- **Offline Instant Alerts:** Local notifications triggered in <50ms following transaction capture, respecting quiet hours and lock-screen privacy masking (`show_amounts: false`).

---

## 5. Non-Goals
- AI conversational recommendations (Milestone F5).
- Cloud scheduled morning allowance notifications (handled by backend BullMQ in B4).

---

## 6. Proposed Design

### 6.1 Safe-to-Spend Formula

$$\text{SafeToday} = \frac{\text{PeriodLimit} - \text{SpentInPeriod} - \text{UpcomingBills} - \text{SavingsTargetRemaining}}{\max(1, \text{DaysLeftInPeriod})}$$

- **Dynamic Daily Adjustment:** If a user overspends on Monday, the denominator spreads the difference across the remaining days of the month automatically.

### 6.2 Threshold Evaluation Pipeline

```
           New Transaction Recorded in Drift DB
                            │
                            ▼
           Query total spend in category / account
                            │
            Check active Limits for matching scope
                            │
              Percentage = (TotalSpent / LimitAmount) * 100
                            │
       ┌────────────────────┼────────────────────┐
       ▼                    ▼                    ▼
   >= 50% & < 80%       >= 80% & < 100%        >= 100%
       │                    │                    │
  Level 1 Alert        Level 2 Alert        Over-Budget Alert
       │                    │                    │
       └────────────────────┬────────────────────┘
                            │
             Check Quiet Hours (e.g. 22:00 - 07:00)
                            │
             Check Privacy Masking (show_amounts)
                            │
                            ▼
          flutter_local_notifications Display
```

---

## 7. Interface Changes & API Handshake

### 7.1 Backend Alignment
- **Limits CRUD**: `GET /v1/limits`, `POST /v1/limits`, `PATCH /v1/limits/:id`, `DELETE /v1/limits/:id`.
- **Saving Plans CRUD**: `GET /v1/saving-plans`, `POST /v1/saving-plans`, `PATCH /v1/saving-plans/:id`.
- **Preferences**: `GET /v1/notifications/preferences` to sync quiet hours and privacy mask settings.

---

## 8. Data Model: Local Drift Tables

```dart
class LocalLimits extends Table {
  TextColumn get id => text()();
  TextColumn get scopeType => text()(); // overall, category, account
  TextColumn get scopeId => text().nullable()();
  TextColumn get periodType => text()(); // daily, weekly, monthly
  RealColumn get amount => real()();
  TextColumn get mode => text()(); // soft, hard
  BoolColumn get rollover => boolean().withDefault(const Constant(false))();
  TextColumn get alertThresholdsJson => text()(); // "[50, 80, 100]"
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalSavingPlans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get periodType => text()();
  RealColumn get targetAmount => real()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get ruleType => text()(); // fixed, percent_of_income, leftover
  RealColumn get ruleValue => real().nullable()();
  TextColumn get linkedAccountId => text().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(3))();
  TextColumn get status => text()(); // active, completed, paused
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

---

## 9. Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| **1. Cloud-Triggered Budget Alerts** | Server has all historical records. | Completely fails offline; delayed by minutes if user has spotty cellular reception. | **Adopted:** Instant on-device local notifications with cloud fallback. |
| **2. Plain Horizontal Progress Bars** | Standard UI pattern. | Low glanceability; does not convey day-by-day pace context. | **Adopted:** Dual interface: Safe-to-Spend circular gauge on Home + Liquid Goal Jars on Plan tab. |

---

## 10. Impact & Risks
- **Notification Fatigue:** Multiple alerts if user conducts multiple micro-transactions in quick succession.
  - *Mitigation:* Daily alert quota cap (default max 5 alerts/day); suppresses re-alerts for the same threshold tier within 24 hours.

---

## 11. Implementation Plan
- **F4.1:** Build `BudgetMathService` implementing Safe-to-Spend formula.
- **F4.2:** Build animated Safe-to-Spend circular ring widget on Home tab.
- **F4.3:** Build Budget Envelopes list and creation dialog.
- **F4.4:** Build Liquid Goal Jars with animated wave shaders for Saving Plans.
- **F4.5:** Implement on-device threshold evaluation with `flutter_local_notifications`.

---

## 12. Testing Strategy
- **Math Edge Cases:** Month transitions (Feb 28/29 to March 1), negative Safe-to-Spend calculations, zero limit handling.
- **Quiet Hours Tests:** Simulate transaction at 23:30; verify notification is silenced.

---

## 13. Rollout & Rollback Plan
- Pure client-side mathematical evaluation and notification triggering backed by existing Drift database tables and sync protocol.
- Rollback: Revert to previous UI and mathematical providers without database migration overhead.

---

## 14. Open Questions
- None. Daily burn arithmetic and quiet hours notification suppression operate deterministically on device.

---

## 15. References
- Master Architecture: `.agent/docs/design/2026-10-07-sw-budget-app-design.md`
- Backend Limits API: `.agent/docs/api-documentation.md#budget-limits`
- Milestone F2 SQLCipher: `.agent/docs/design/mobile/2026-10-07-f2-skeleton-sqlcipher-api-client.md`

---

## 16. Decision Log
- **2026-10-07 (Safe-to-Spend Dynamic Spreading):** Overspending in any given day adjusts the daily burn rate automatically by dividing the updated remaining balance by the remaining days in the cycle, providing instant feedback without penalizing the user with rigid static budgets.
- **2026-10-07 (Privacy-Masked Notifications):** Implemented lock-screen privacy masking (`showAmountsOnLockScreen: false`) to display percentage-based warnings rather than revealing explicit Birr balances in crowded environments.
- **2026-10-07 (On-Device Threshold Evaluation):** Evaluated 50%, 80%, and 100% threshold crossings directly in pure Dart upon local transaction insert to achieve <50ms alerts regardless of mobile connectivity.

---

## 17. Change Log
- **2026-10-07:** Completed implementation of Milestone F4:
  - Domain Engine: `BudgetMathService` computing daily Safe-to-Spend allowances, spending pace categorization (Ahead, On Track, Caution, Deficit), and limit progress.
  - On-Device Alerts: `LocalNotificationService` using `flutter_local_notifications` with `budget_alerts` Android channel, quiet hours check (22:00–07:00), daily deduplication cooldown, and lock-screen privacy masking.
  - State Management: `plan_providers.dart` providing `limitsStreamProvider`, `savingPlansStreamProvider`, `currentMonthSpendSummaryProvider`, `safeToSpendProvider`, and `PlanController`.
  - User Interface: `SafeToSpendGauge` animated radial ring widget with pace badges, updated `HomeScreen`, and tabbed `PlanScreen` with Budget Envelopes, Liquid Goal Jars, and creation modals.
  - Unit Tests: `budget_math_test.dart` testing formulas, mid-month recalculations, deficits, and threshold crossings.

