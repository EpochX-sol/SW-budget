# SW-budget: Full-Stack Modernization & Feature Expansion Specification

> **Comprehensive Blueprint for Elevating SW-budget Beyond Totals with Production Ingestion, Adaptive Spending Limits, Advanced Financial Tooling, and AI Augmentation.**

---

## 1. Metadata
- **Status:** Proposed (v2.0 - Adaptive Spending Limit Integrated)
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-10
- **Type:** Architectural Specification & System Upgrade Plan
- **Confidence:** High (99%) — Synthesized from live codebase analysis of `backend/`, `mobile/`, `reference_repos/totals`, and the Adaptive Spending Limit specification.
- **Related Documents:**
  - [.agent/docs/design/2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - [.agent/docs/design/2026-10-10-sw-budget-totals-gap-analysis-and-roadmap.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-10-sw-budget-totals-gap-analysis-and-roadmap.md)
  - [docs/TOTALS_ARCHITECTURE_AND_FEATURES.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/docs/TOTALS_ARCHITECTURE_AND_FEATURES.md)

---

## 2. Summary
SW-budget will be upgraded into an industry-leading personal finance system for Ethiopia that **combines all battle-tested offline capabilities of Totals with SW-budget's exclusive cloud-sync, AI coach advantages, and a dynamic Adaptive Spending Limit engine**.

By integrating:
1. Totals' **3,238-line regex engine**, **8-bank coverage**, and **headless background Dart isolate**;
2. Totals' advanced ledger tools: **Reimbursements**, **Loans & Debts**, **Account Reparse Wizard**, and **Bank Statement PDF Generator**;
3. The **Adaptive Spending Limit Feature**: custom-period spending plans that dynamically recalculate daily and weekly allowances from real spending;
4. SW-budget's **Fastify + PostgreSQL cloud sync**, **pgvector episodic memory**, and **deterministic AI tools**;

SW-budget will establish complete feature superiority over Totals while resolving all existing SMS ingestion failures.

---

## 3. Problem / Motivation
1. **Current Ingestion Failures:** SW-budget's custom Android SMS channel crashes on Android 11+ (`LIMIT` in `sortOrder`) and lacks a headless background isolate when the app is closed.
2. **Static Budgeting Pitfall:** Traditional budget apps freeze daily spending limits. In reality, if a user overspends on Monday, their allowance for Tuesday through Sunday must adapt so they still hit their target by the end of the period.
3. **Totals' Blind Spots:** Totals has no adaptive allowance engine, no scenario forecasting, zero AI capability, and no multi-device cloud synchronization.
4. **The Solution:** A unified system where transactions parsed automatically from 8 Ethiopian banks feed directly into an **Adaptive Spending Limit engine**, verified by a double-checking balance-chain, synchronized to the cloud, and surfaced to an AI coach.

---

## 4. Goals & Non-Goals

### 4.1 Goals
- **100% Reliable Ingestion:** Headless background SMS & notification capture across Android 10 through 15 and aggressive OEM battery killers (Transsion, Xiaomi, Samsung).
- **8 Ethiopian Banks Supported:** CBE, Telebirr, BoA, Awash, Dashen, Amhara, Nib, Zemen.
- **Adaptive Spending Limits:**
  - Dynamic daily and weekly allowances recalculated on every transaction or day boundary.
  - Variance tracking: "You spent 22% more than today's allowance; tomorrow you can spend 964 ETB".
  - Rollover modes: `SPREAD_EVENLY`, `NEXT_DAY`, `WEEK_ONLY`, `TO_SAVINGS`.
  - Fixed commitments (rent, bills) reserved up front; emergency reserves excluded from allowances.
  - Weighted days (e.g. higher budget on weekends).
- **Advanced Ledger Tools:**
  - Reimbursements (credits linked to debits so net spending is accurate).
  - Loans & Debts (person-by-person lending, borrowing, and repayment tracker).
  - Historical Account Reparse Wizard and "Other Transactions" quarantine.
  - On-Device Vector Bank Statement PDF Generator.
- **AI Coach Augmentation:**
  - Chat grounded with live `PlanSnapshot` JSON, deterministic scenario simulations, and debt queries.
- **Platform Integrations:**
  - Android Home Screen AppWidgets (Live Allowance, Spent Today, Status Color).
  - App-icon shortcuts and local Wi-Fi web dashboard (`shelf`).

### 4.2 Non-Goals
- Direct open-banking write APIs (debits or payments initiation) — Ethiopian banks do not offer open write APIs.
- Multi-currency conversion in v1 (ETB only).
- iOS automated background SMS reading (Apple iOS sandboxing restricts SMS interception; iOS will support manual CSV/data import only).

---

## 5. Architectural Topology

```
┌─────────────────────────────────────── ANDROID CLIENT (Flutter) ───────────────────────────────────────┐
│                                                                                                       │
│  Presentation Layer (Riverpod 2.6, GoRouter):                                                         │
│  ├── Plan Dashboard Screen (Today Allowance, Variance %, Tomorrow Card, Week & Period Cards)         │
│  ├── Plan Setup Screen (Period, Total Budget B, Fixed Expenses F, Reserve R, Rollover Mode)          │
│  ├── Simulator Screen (Dynamic spend slider, Projected end-of-period outcome)                         │
│  ├── Activity Ledger (with Gap Detector & Other Txns Quarantine)                                      │
│  ├── Reimbursements Linking (Expense Deductions)                                                      │
│  ├── Loans & Debts Hub (People, Timelines, Settlements)                                               │
│  ├── Bank Statement PDF Generator (Local Vector PDF)                                                  │
│  ├── Reparse & Repair Wizard (Historical SMS Cleaner)                                                 │
│  └── AI Financial Coach (SSE Streaming Chat)                                                         │
│  ───────────────────────────────────────────────────────────────────────────────────────────────────  │
│  Android System Extensions:                                                                           │
│  ├── Headless Background Dart Isolate (@pragma('vm:entry-point') onBackgroundMessage via another_telephony) │
│  ├── Android Home Screen AppWidgets (Live Allowance & Safe-to-Spend Gauge via home_widget)           │
│  ├── App-Icon Shortcuts (Add Expense, Add Income, Quick Accounts, Verify)                            │
│  └── Local Wi-Fi Web Dashboard (Embedded shelf HTTP Server on port 8080)                              │
│  ───────────────────────────────────────────────────────────────────────────────────────────────────  │
│  Data & Domain Core:                                                                                  │
│  ├── Drift (SQLCipher) Encrypted Database                                                             │
│  ├── Deterministic computeSnapshot Engine (Local offline calculation & caching)                      │
│  ├── 3,238-Line Named Regex Parser + Heuristic Fallback Parser                                        │
│  ├── Account Ownership & Masked Account Solver                                                        │
│  └── Resumable Chunked Sync Client (change_seq protocol)                                              │
└───────────────────────────────────────────────────┬───────────────────────────────────────────────────┘
                                                    │ HTTPS / TLS 1.3
                                                    │ Bearer JWT + Device UUID
┌───────────────────────────────────────────────────▼───────────────────────────────────────────────────┐
│ FASTIFY + NODE.JS 22 BACKEND (Modular Monolith)                                                       │
│                                                                                                       │
│  Modules:                                                                                             │
│  ├── Spending Plans Module (BudgetPlan, FixedExpense, CategoryLimit, Snapshot Engine)                 │
│  ├── Reimbursements Module (Sync, Link Tracking, Net-Spend Rollups)                                   │
│  ├── Loans & Debts Module (Contacts, Debt Records, Repayments Sync)                                   │
│  ├── Finance Core (Accounts, Categories, Transactions, Monotonic Sync Engine)                         │
│  ├── Template & Pattern Engine (OTA Pattern Bundle API with ETag Caching)                             │
│  └── AI Gateway & Deterministic Tools:                                                                │
│      ├── get_active_plan_snapshot, simulate_plan_spending, query_loans_debts                           │
│      └── pgvector Long-Term Episodic Memory (text-embedding-004)                                      │
│  ───────────────────────────────────────────────────────────────────────────────────────────────────  │
│  Transactional Outbox ──► BullMQ Workers (Redis 7)                                                    │
│                            ├── Plan Snapshot Rebuilder Worker                                         │
│                            ├── Notification Scheduler (Morning Allowance, 80% Alert, Evening Recap)   │
│                            └── Aggregates Worker (Daily Category Totals)                              │
└─────────────────────────────────────────┬───────────────────────────────────┬─────────────────────────┘
                                          │                                   │
                                   PostgreSQL 16                           Redis 7
                              (pgvector, Prisma ORM)                 (BullMQ, PubSub, Cache)
```

---

## 6. The Adaptive Spending Limit System in Depth

### 6.1 Mathematical Formulation
All amounts are in ETB. Day boundaries use the **Africa/Addis_Ababa** timezone (UTC+3).

#### Base Setup Values
$$N = \text{Total days in plan (inclusive)}$$
$$X = B - F - R \quad (\text{Flexible Budget where } B = \text{Budget}, F = \text{Fixed Expenses}, R = \text{Emergency Reserve})$$
$$\text{BaseDaily} = \frac{X}{N}$$

#### Daily Values on Day $d$ (1-indexed)
$$S_{\text{prev}} = \sum_{i=1}^{d-1} \text{Spent}(i), \quad S_{\text{today}} = \text{Spent}(d), \quad S_{\text{total}} = S_{\text{prev}} + S_{\text{today}}$$
$$\text{DaysLeftInclToday} = N - d + 1, \quad \text{DaysLeftAfterToday} = N - d$$

$$\text{AllowanceToday} = \max\left(0, \frac{X - S_{\text{prev}}}{\text{DaysLeftInclToday}}\right)$$
$$\text{TodayVarianceVsAllowance\%} = \frac{S_{\text{today}} - \text{AllowanceToday}}{\text{AllowanceToday}} \times 100$$
$$\text{Remaining} = X - S_{\text{total}}$$
$$\text{TomorrowAllowance} = \begin{cases} \max\left(0, \frac{\text{Remaining}}{\text{DaysLeftAfterToday}}\right) & \text{if } \text{DaysLeftAfterToday} > 0 \\ \text{null} & \text{if } d = N \end{cases}$$
$$\text{TomorrowPctOfBase} = \frac{\text{TomorrowAllowance}}{\text{BaseDaily}} \times 100$$

#### Pacing & Projections
$$\text{ExpectedToDate} = \text{BaseDaily} \times d$$
$$\text{PaceRatio} = \frac{S_{\text{total}}}{\text{ExpectedToDate}}$$
$$\text{AvgDailySpend} = \frac{S_{\text{total}}}{d}$$
$$\text{ProjectedTotal} = \text{AvgDailySpend} \times N$$
$$\text{ProjectedOverspend} = \text{ProjectedTotal} - X$$
$$\text{DaysUntilBroke} = \begin{cases} \frac{\text{Remaining}}{\text{AvgDailySpend}} & \text{if } \text{AvgDailySpend} > 0 \\ \text{null} & \text{otherwise} \end{cases}$$

#### Status Color Indicators
- **GREEN:** $S_{\text{total}} \le 0.90 \times \text{ExpectedToDate}$ (Under plan)
- **YELLOW:** $0.90 \times \text{ExpectedToDate} < S_{\text{total}} \le 1.00 \times \text{ExpectedToDate}$ (On track)
- **ORANGE:** $S_{\text{total}} > \text{ExpectedToDate}$ (Pacing slightly hot)
- **RED:** $\text{Remaining} \le 0$ OR $\text{ProjectedTotal} > 1.20 \times X$ (Severe overspend / exhausted)

### 6.2 Rollover Modes
The user chooses how overspending/underspending is redistributed:
1. **`SPREAD_EVENLY` (Default):** Balance is distributed equally across all remaining days: $\frac{\text{Remaining}}{\text{DaysLeftAfterToday}}$.
2. **`NEXT_DAY`:** Tomorrow absorbs the entire variance: $\text{BaseDaily} - (S_{\text{today}} - \text{BaseDaily})$, floored at 0. Subsequent days stay at base.
3. **`WEEK_ONLY`:** Variance is absorbed by the remainder of the current week: $\frac{\text{WeekBaseTarget} - \text{WeekSpent}}{\text{DaysLeftInWeek}}$. The next week starts fresh at base.
4. **`TO_SAVINGS`:** Underspending is automatically transferred to a linked Saving Plan. Overspending is spread evenly.

### 6.3 Integration with Reimbursements
When a transaction is linked to a **Reimbursement** credit:
$$\text{NetSpent}(\text{Txn}) = \text{Amount} - \sum \text{ReimbursedAmount}$$
This prevents money returned by friends from counting as gross income and accurately restores the flexible budget $X$.

---

## 7. Data Models (Prisma & Drift)

### 7.1 Backend Prisma Schema Additions

```prisma
// ==================== SPENDING PLANS ====================

model BudgetPlan {
  id              String          @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  userId          String          @map("user_id") @db.Uuid
  name            String          @default("My Spending Plan")
  totalAmount     Decimal         @map("total_amount") @db.Decimal(14, 2)
  startDate       DateTime        @map("start_date") @db.Date
  endDate         DateTime        @map("end_date") @db.Date
  rolloverMode    RolloverMode    @default(SPREAD_EVENLY) @map("rollover_mode")
  reservePercent  Decimal         @default(0) @map("reserve_percent") @db.Decimal(5, 2)
  savingGoal      Decimal         @default(0) @map("saving_goal") @db.Decimal(14, 2)
  minDailyFloor   Decimal         @default(0) @map("min_daily_floor") @db.Decimal(14, 2)
  dayWeights      Json?           @map("day_weights") // {"mon":1.0, "tue":1.0, ..., "sun":1.4}
  active          Boolean         @default(true)
  changeSeq       BigInt          @map("change_seq")
  createdAt       DateTime        @default(now()) @map("created_at") @db.Timestamptz(6)
  updatedAt       DateTime        @default(now()) @updatedAt @map("updated_at") @db.Timestamptz(6)
  deletedAt       DateTime?       @map("deleted_at") @db.Timestamptz(6)

  user            User            @relation(fields: [userId], references: [id], onDelete: Cascade)
  fixedExpenses   FixedExpense[]
  categoryLimits  CategoryLimit[]
  snapshots       PlanSnapshot[]

  @@index([userId, active])
  @@map("budget_plans")
}

model FixedExpense {
  id        String     @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  planId    String     @map("plan_id") @db.Uuid
  title     String
  amount    Decimal    @db.Decimal(14, 2)
  dueDate   DateTime?  @map("due_date") @db.Date
  paid      Boolean    @default(false)
  changeSeq BigInt     @map("change_seq")
  createdAt DateTime   @default(now()) @map("created_at") @db.Timestamptz(6)

  plan      BudgetPlan @relation(fields: [planId], references: [id], onDelete: Cascade)

  @@index([planId])
  @@map("fixed_expenses")
}

model CategoryLimit {
  id        String     @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  planId    String     @map("plan_id") @db.Uuid
  category  String
  amount    Decimal    @db.Decimal(14, 2)
  changeSeq BigInt     @map("change_seq")
  createdAt DateTime   @default(now()) @map("created_at") @db.Timestamptz(6)

  plan      BudgetPlan @relation(fields: [planId], references: [id], onDelete: Cascade)

  @@unique([planId, category])
  @@map("category_limits")
}

model PlanSnapshot {
  id           String     @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  planId       String     @map("plan_id") @db.Uuid
  snapshotDate DateTime   @map("snapshot_date") @db.Date
  payload      Json       // Complete computed snapshot object
  computedAt   DateTime   @default(now()) @map("computed_at") @db.Timestamptz(6)

  plan         BudgetPlan @relation(fields: [planId], references: [id], onDelete: Cascade)

  @@unique([planId, snapshotDate])
  @@map("plan_snapshots")
}

enum RolloverMode {
  SPREAD_EVENLY
  NEXT_DAY
  WEEK_ONLY
  TO_SAVINGS
}

// ==================== REIMBURSEMENTS ====================

model Reimbursement {
  id           String      @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  userId       String      @map("user_id") @db.Uuid
  expenseTxnId String      @map("expense_txn_id") @db.Uuid
  creditTxnId  String      @map("credit_txn_id") @db.Uuid
  amount       Decimal     @db.Decimal(14, 2)
  note         String?
  changeSeq    BigInt      @map("change_seq")
  createdAt    DateTime    @default(now()) @map("created_at") @db.Timestamptz(6)
  updatedAt    DateTime    @default(now()) @updatedAt @map("updated_at") @db.Timestamptz(6)
  deletedAt    DateTime?   @map("deleted_at") @db.Timestamptz(6)

  user         User        @relation(fields: [userId], references: [id], onDelete: Cascade)
  expenseTxn  Transaction @relation("ExpenseReimbursements", fields: [expenseTxnId], references: [id], onDelete: Cascade)
  creditTxn   Transaction @relation("CreditReimbursements", fields: [creditTxnId], references: [id], onDelete: Cascade)

  @@index([userId])
  @@index([expenseTxnId])
  @@index([creditTxnId])
  @@map("reimbursements")
}

// ==================== LOANS & DEBTS ====================

model ContactPerson {
  id          String      @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  userId      String      @map("user_id") @db.Uuid
  name        String
  phoneNumber String?     @map("phone_number")
  changeSeq   BigInt      @map("change_seq")
  createdAt   DateTime    @default(now()) @map("created_at") @db.Timestamptz(6)
  updatedAt   DateTime    @default(now()) @updatedAt @map("updated_at") @db.Timestamptz(6)
  deletedAt   DateTime?   @map("deleted_at") @db.Timestamptz(6)

  user        User        @relation(fields: [userId], references: [id], onDelete: Cascade)
  loansDebts  LoanDebt[]

  @@index([userId])
  @@map("contact_persons")
}

model LoanDebt {
  id             String          @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  userId         String          @map("user_id") @db.Uuid
  personId       String          @map("person_id") @db.Uuid
  type           String          // "lent" | "borrowed"
  initialAmount  Decimal         @map("initial_amount") @db.Decimal(14, 2)
  currentBalance Decimal         @map("current_balance") @db.Decimal(14, 2)
  dueDate        DateTime?       @map("due_date") @db.Date
  status         String          @default("active") // "active" | "settled" | "forgiven"
  note           String?
  changeSeq      BigInt          @map("change_seq")
  createdAt      DateTime        @default(now()) @map("created_at") @db.Timestamptz(6)
  updatedAt      DateTime        @default(now()) @updatedAt @map("updated_at") @db.Timestamptz(6)
  deletedAt      DateTime?       @map("deleted_at") @db.Timestamptz(6)

  user           User            @relation(fields: [userId], references: [id], onDelete: Cascade)
  person         ContactPerson   @relation(fields: [personId], references: [id], onDelete: Cascade)
  repayments     LoanRepayment[]

  @@index([userId])
  @@index([personId])
  @@map("loans_debts")
}

model LoanRepayment {
  id         String       @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  userId     String       @map("user_id") @db.Uuid
  loanDebtId String       @map("loan_debt_id") @db.Uuid
  txnId      String?      @map("txn_id") @db.Uuid
  amount     Decimal      @db.Decimal(14, 2)
  repaidAt   DateTime     @map("repaid_at") @db.Timestamptz(6)
  note       String?
  changeSeq  BigInt       @map("change_seq")
  createdAt  DateTime     @default(now()) @map("created_at") @db.Timestamptz(6)

  user       User         @relation(fields: [userId], references: [id], onDelete: Cascade)
  loanDebt   LoanDebt     @relation(fields: [loanDebtId], references: [id], onDelete: Cascade)
  transaction Transaction? @relation(fields: [txnId], references: [id], onDelete: SetNull)

  @@index([userId])
  @@index([loanDebtId])
  @@map("loan_repayments")
}
```

---

## 8. Backend API Specifications

### 8.1 Spending Plans Endpoints
- `POST /v1/plans`: Create new plan with dates, budget, fixed expenses, reserve, and rollover mode.
- `GET /v1/plans/active`: Returns active plan and precomputed `PlanSnapshot`.
- `GET /v1/plans/:id/snapshot?date=YYYY-MM-DD`: Historical snapshot inspection.
- `POST /v1/plans/:id/simulate`: Scenario simulator endpoint ("What if I spend 800 ETB/day?").
- `POST /v1/plans/:id/fixed-expenses`: Add fixed commitment to active plan.

### 8.2 Patterns OTA Endpoint
- `GET /v1/templates/patterns`: Serves latest 3,238-line regex pattern bundle with `ETag` and hash caching.

### 8.3 AI Gateway Tools Expansion
- `get_active_plan_snapshot`: Returns current allowance, spent today, remaining today, tomorrow's allowance, and pace status.
- `simulate_plan_spending({ dailySpendAmount })`: Returns projected overspend and days until broke.
- `query_loans_debts({ status, personName })`: Queries lent/borrowed balances.
- `query_reimbursements({ timeframe })`: Tracks linked repayments.

---

## 9. Mobile Implementation Specification

### 9.1 Ingestion & Telephony Core (P0)
- Add `another_telephony: ^0.4.1` to [mobile/pubspec.yaml](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/mobile/pubspec.yaml).
- Register `@pragma('vm:entry-point') onBackgroundMessage` in [main.dart](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/mobile/lib/main.dart).
- Remove `LIMIT` from ContentResolver sort order in Android Kotlin to fix Android 11+ crash.
- Import Totals' `sms_patterns.json` (3,238 lines) and `fallback_sms_parser.dart` to support all 8 banks.

### 9.2 Plan Dashboard & Experience (P1)
- **PlanDashboardScreen:**
  - **Today Card:** Big numerical allowance, spent today, remaining today, status badge.
  - **Variance Line:** "You are 12% over today's plan" (amber) or "8% under plan" (green).
  - **Tomorrow Card:** "Spend up to 961 ETB tomorrow (96% of base daily limit)".
  - **Week Card:** Spent vs weekly target, % elapsed, % used.
  - **Period Card:** Total spent, remaining, days left, projected end total.
  - **Pace Chart:** Cumulative spend line vs straight-line ideal trajectory.
- **SimulatorScreen:** Slider for daily spend, showing real-time projected outcome.
- **WeekDetailScreen:** Day-by-day table for current week.

### 9.3 Ledger & Extensions (P2)
- **Reimbursements Flow:** Link incoming credit to prior debit; subtract from category spend.
- **Loans & Debts Hub:** Person-by-person ledger with bank transfer linking.
- **Reparse Wizard:** Re-read inbox from any date, clean duplicates, fix directions.
- **Bank Statement PDF:** Generate branded vector PDF locally.
- **Android Home Widgets:** Live Allowance & Safe-to-Spend widgets via `home_widget`.
- **Local Wi-Fi Server:** Embedded `shelf` HTTP server on port 8080.

---

## 10. Implementation Plan & Phases

```mermaid
graph TD
    subgraph Phase 1: Ingestion & Bank Overhaul
        A1["Adopt another_telephony & headless isolate"] --> A2["Port 3,238-line regex patterns"]
        A2 --> A3["Fix Android ContentResolver LIMIT bug"]
        A3 --> A4["Remove 7-day limit & expand 8 banks"]
    end

    subgraph Phase 2: Adaptive Spending Plan Core
        B1["Prisma schema: BudgetPlan, Snapshots, FixedExpenses"] --> B2["Deterministic computeSnapshot function"]
        B2 --> B3["Plan API endpoints & BullMQ rebuilder"]
        B3 --> B4["Flutter Plan Setup & Dashboard screens"]
    end

    subgraph Phase 3: Advanced Ledger & AI Augmentation
        C1["Reimbursements Linking in DB & Math"] --> C2["Loans & Debts Ledger UI & API"]
        C2 --> C3["Account Reparse & Repair Wizard"]
        C3 --> C4["AI Coach tools: get_active_plan_snapshot, simulate"]
    end

    subgraph Phase 4: Platform Extensions
        D1["Bank Statement PDF Generator"] --> D2["Android Home Screen Widgets"]
        D2 --> D3["Local Wi-Fi Server & App Shortcuts"]
    end

    Phase 1 --> Phase 2 --> Phase 3 --> Phase 4
```

### Build Order:
1. **Phase 1 (P0):** Fix Android SMS Ingestion + 8-Bank Regex Patterns.
2. **Phase 2 (P1):** Prisma Schema Migrations + Backend & Mobile `computeSnapshot` Engine + Plan Dashboard UI.
3. **Phase 3 (P1):** Reimbursements Linking + Loans & Debts + Reparse Wizard + AI Gateway Plan Tools.
4. **Phase 4 (P2):** Vector Bank Statement PDF + Home Screen Widgets + Local Wi-Fi Dashboard.

---

## 11. Decision Log
- **2026-10-10:** Initial upgrade plan drafted from Totals analysis.
- **2026-10-10 (Revision 2.0):** Incorporated **Adaptive Spending Limit Feature** (dynamic daily/weekly allowances, rollover modes, fixed expenses, pace charts, and deterministic snapshots) into master design document. Confirmed that reimbursements subtract from spend before computing daily allowance.
