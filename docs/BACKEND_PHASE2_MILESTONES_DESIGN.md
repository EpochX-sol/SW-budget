# SW-budget: Backend Phase 2 Milestones Specification

> **Full Architectural Blueprint for Upgrading the Fastify/Node.js/Prisma Backend to Support Adaptive Spending Plans, Totals-Parity Financial Tooling (Reimbursements, Loans & Debts, OTA Patterns), and AI Augmentation.**

---

## 1. Metadata
- **Status:** Proposed (Awaiting Approval)
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-10
- **Type:** Backend System Architecture & Milestone Roadmap
- **Confidence:** High (99%) — Verified against current `backend/src/` modules, Prisma schemas, BullMQ queue topology, and the Adaptive Spending Limit specification.
- **Related Documents:**
  - [.agent/docs/design/backend/2026-10-07-b2-finance-api-sync-outbox.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/backend/2026-10-07-b2-finance-api-sync-outbox.md)
  - [.agent/docs/design/backend/2026-10-07-b3-ai-gateway-memory-tools.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/backend/2026-10-07-b3-ai-gateway-memory-tools.md)
  - [.agent/docs/design/2026-10-10-sw-budget-full-system-upgrade-spec.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-10-sw-budget-full-system-upgrade-spec.md)

---

## 2. Summary
Phase 2 elevates the SW-budget backend from basic transaction/limits management to an **advanced financial calculation, multi-entity sync, and AI-grounded platform**. 

The backend will be upgraded across **5 distinct milestones**:
1. **Milestone B2-P2.1:** Database Schema Migrations & Monotonic Sync Protocol Expansion (`budget_plans`, `reimbursements`, `loans_debts`).
2. **Milestone B2-P2.2:** The Adaptive Spending Engine & Pure Calculation Service (`computeSnapshot`, rollover strategies, deterministic simulation).
3. **Milestone B2-P2.3:** REST API Endpoints & OTA Pattern Distribution (`/plans`, `/reimbursements`, `/debts`, `/templates/patterns`).
4. **Milestone B2-P2.4:** BullMQ Background Schedulers & Snapshot Rebuilder Worker (midnight Addis Ababa tick, notification thresholds, transaction recomputation).
5. **Milestone B2-P2.5:** AI Gateway Expansion with Deterministic Snapshot & Debt Tools (`get_active_plan_snapshot`, `simulate_plan_spending`, `query_loans_debts`).

---

## 3. Problem / Motivation
1. **Static Limits Fallacy:** The existing backend only supports static budget limits (`limits` table) with basic thresholds (50%, 80%, 100%). It cannot dynamically recompute daily and weekly allowances when a user overspends or underspends.
2. **Missing Totals Financial Primitives:** The backend has no concept of:
   - **Reimbursements:** Linking incoming credit transactions to prior expenses to accurately reflect net spending without inflating income.
   - **Loans & Debts:** Tracking who owes the user money vs. who the user owes, along with partial repayments and bank transfer links.
3. **Static SMS Patterns:** The mobile app's regex templates are bundled as static assets. When Ethiopian banks alter their SMS wording, the backend cannot deliver updated regex patterns over-the-air.
4. **AI Context Limitations:** The AI Coach currently lacks real-time awareness of adaptive allowances, days until budget exhaustion, and active debts.

---

## 4. Goals
- **Deterministic Math:** Implement pure TypeScript calculation functions (`computeSnapshot`) with zero floating-point errors, adhering strictly to Addis Ababa UTC+3 day boundaries.
- **Support 4 Rollover Strategies:** `SPREAD_EVENLY`, `NEXT_DAY`, `WEEK_ONLY`, `TO_SAVINGS`.
- **Full Sync Support:** Extend the `change_seq` monotonic synchronization protocol to cleanly sync all new entities across mobile and web.
- **Over-The-Air Pattern Delivery:** Serve 3,238+ bank regex patterns with HTTP ETag caching.
- **AI Tool Calling:** Expose deterministic tools to the LLM so it answers budget and debt questions using real calculated numbers.

---

## 5. Non-Goals
- Multi-currency conversion in v1 (all math operates strictly in `ETB`).
- Complex multi-party shared debt reconciliation (focuses on 1-to-1 loans and debts between user and contacts).

---

## 6. Proposed Design (Architecture & Milestones)

```
┌─────────────────────────────────────── FASTIFY BACKEND ───────────────────────────────────────┐
│                                                                                               │
│  HTTP / REST Layer:                                                                           │
│  ├── /v1/plans             (Create, Read Active, Historical Snapshots, Simulators)            │
│  ├── /v1/reimbursements    (Link Credits to Debits, Query Net Spending)                       │
│  ├── /v1/debts             (Contacts, Lent/Borrowed Ledgers, Repayment Links)                 │
│  ├── /v1/templates         (OTA Patterns with ETag / 304 Caching)                             │
│  └── /v1/sync              (Push & Pull across 10 distinct entities via change_seq)          │
│  ───────────────────────────────────────────────────────────────────────────────────────────  │
│  Service Layer:                                                                               │
│  ├── SpendingPlanService   (computeSnapshot, Rollover Strategies, Invariant Enforcement)      │
│  ├── ReimbursementService  (Credit-to-Debit Allocation, Net-Spend Rollups)                    │
│  ├── LoanDebtService       (Contact Management, Settlement Tracking)                          │
│  ├── SyncService           (Monotonic Atomic Sequencing, Last-Write-Wins Resolution)          │
│  └── AiService             (Tools: get_active_plan_snapshot, simulate_plan_spending, etc.)     │
│  ───────────────────────────────────────────────────────────────────────────────────────────  │
│  Asynchronous Outbox & Workers (BullMQ + Redis 7):                                            │
│  ├── PlanSnapshotRebuilderWorker (Rebuilds cached snapshots upon transaction writes)          │
│  ├── AddisMidnightTickWorker     (Advances day d at 00:00 UTC+3, triggers morning allowances) │
│  └── NotificationSchedulerWorker (80% threshold, evening recaps, burn-rate warnings)          │
└──────────────────────────────────────┬────────────────────────────────┬───────────────────────┘
                                       │                                │
                                PostgreSQL 16                        Redis 7
                         (pgvector, Prisma ORM,            (BullMQ Queues, PubSub,
                          Atomic Sequences)                 Rate Limits, Locks)
```

### Milestone Breakdown

```
┌───────────────────────────────────────────────────────────────────────────────────────────┐
│                               BACKEND PHASE 2 MILESTONES                                  │
├──────────────────────────┬────────────────────────────────────────────────────────────────┤
│ Milestone B2-P2.1        │ Database Schema Migrations & Monotonic Sync Protocol           │
│ Milestone B2-P2.2        │ Adaptive Spending Engine & Pure Calculation Service            │
│ Milestone B2-P2.3        │ Core Finance REST API Endpoints & OTA Pattern Server           │
│ Milestone B2-P2.4        │ BullMQ Schedulers, Snapshot Rebuilder & Notification Engine    │
│ Milestone B2-P2.5        │ AI Gateway Augmentation & Deterministic Financial Tools        │
└──────────────────────────┴────────────────────────────────────────────────────────────────┘
```

---

## 7. Interface Changes (APIs & Endpoints)

### 7.1 Spending Plans
- `POST /v1/plans`: Validates dates, budget amount, creates plan, triggers initial snapshot.
- `GET /v1/plans/active`: Returns active plan and current day's cached `PlanSnapshot`.
- `GET /v1/plans/:id/snapshot?date=YYYY-MM-DD`: Returns historical snapshot.
- `POST /v1/plans/:id/simulate`: Scenario simulator endpoint ("What if I spend X per day?").
- `POST /v1/plans/:id/fixed-expenses`: Add fixed commitment to active plan.

### 7.2 Reimbursements & Debts
- `POST /v1/finance/reimbursements`: Creates credit-to-debit link with amount validation.
- `GET /v1/finance/debts` & `POST /v1/finance/debts`: Loans and debts CRUD.
- `POST /v1/finance/debts/:id/repayments`: Records repayment linked to bank transaction.

### 7.3 OTA Pattern Distribution
- `GET /v1/templates/patterns`: Serves compiled 3,238-line regex pattern bundle with `ETag` and `If-None-Match` 304 response.

---

## 8. Data Model Changes (Prisma)

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

## 9. Alternatives Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **1. Compute snapshots dynamically on every HTTP request** | No cached snapshots table needed | Degrades request latency for active dashboards; scales poorly with hundreds of transactions per user. | ❌ Rejected — Precomputed cached `PlanSnapshot` with async BullMQ invalidation provides instantaneous `<10ms` response times. |
| **2. Client-only adaptive calculation without backend sync** | Less backend code | Loses web companion access, prevents AI Coach from knowing budget numbers, cannot send server-side scheduled push notifications. | ❌ Rejected — Multi-device cloud sync and AI grounding require backend state. |
| **3. Dual-Execution Engine (Pure math shared between TS and Dart, precomputed in DB)** | Instant offline mobile reads + instantaneous cloud API reads + AI coach access. | Requires maintaining calculation math in both TypeScript and Dart. | ✅ **Selected Approach**. |

---

## 10. Impact & Risks

1. **Timezone Invariance:** Day boundaries must strictly use `Africa/Addis_Ababa` (UTC+3) rather than the server's local time or UTC. Handled using `date-fns-tz` with explicit timezone casting.
2. **Snapshot Invalidation on Out-of-Order Transactions:** If a backdated SMS is ingested, snapshots for that day and all subsequent days must be recomputed. Handled by recomputing from raw transactions rather than patching.
3. **Concurrency:** Multiple transactions arriving concurrently could trigger duplicate snapshot computations. Handled via Redis advisory locks on `plan:snapshot:${planId}` with debouncing.

---

## 11. Implementation Plan (Ordered Commit-Sized Steps)

### Milestone B2-P2.1: Data Schema & Sync Engine Expansion
- **Step 1.1:** Update `schema.prisma` with `BudgetPlan`, `FixedExpense`, `CategoryLimit`, `PlanSnapshot`, `Reimbursement`, `ContactPerson`, `LoanDebt`, and `LoanRepayment`.
- **Step 1.2:** Run `npx prisma db push` and verify client generation.
- **Step 1.3:** Update `sync.repository.ts` to support atomic upserts and deletes for the new entities with monotonic `change_seq`.
- **Step 1.4:** Add integration tests for sync push/pull of new entities.

### Milestone B2-P2.2: Adaptive Spending Engine & Pure Math
- **Step 2.1:** Implement `spending-plan.math.ts` with pure `computeSnapshot` function and worked example tests.
- **Step 2.2:** Implement rollover strategy functions (`SpreadEvenly`, `NextDay`, `WeekOnly`, `ToSavings`).
- **Step 2.3:** Implement `spending-plan.service.ts` for database retrieval and snapshot caching.
- **Step 2.4:** Implement scenario simulation engine (`simulateScenario`).

### Milestone B2-P2.3: REST API Endpoints & OTA Patterns
- **Step 3.1:** Implement `/v1/plans` routes and validation schemas.
- **Step 3.2:** Implement `/v1/finance/reimbursements` linking routes.
- **Step 3.3:** Implement `/v1/finance/debts` CRUD routes.
- **Step 3.4:** Implement `GET /v1/templates/patterns` with ETag caching serving Totals' 3,238-line pattern bundle.
- **Step 3.5:** Register routes in `app.ts` and verify with integration tests.

### Milestone B2-P2.4: BullMQ Workers & Notifications
- **Step 4.1:** Register `plan-snapshots` and `plan-notifications` queues in `queues.ts`.
- **Step 4.2:** Implement `plan-snapshots.worker.ts` reacting to transaction outbox events.
- **Step 4.3:** Implement midnight Addis Ababa day boundary tick scheduler.
- **Step 4.4:** Implement `plan-notifications.worker.ts` for morning allowances, 80% alerts, and burn-rate warnings.

### Milestone B2-P2.5: AI Gateway Tools & Scenario Forecasting
- **Step 5.1:** Add `get_active_plan_snapshot` tool to `finance-tools.ts`.
- **Step 5.2:** Add `simulate_plan_spending` tool to `finance-tools.ts`.
- **Step 5.3:** Add `query_loans_debts` tool to `finance-tools.ts`.
- **Step 5.4:** Integrate tool definitions into `ai.service.ts` and test with mock conversational prompts.

---

## 12. Testing Strategy

1. **Unit Tests (`test/unit/spending-plan-math.test.ts`):**
   - Verify the Section 5.5 worked example: Day 1 allowance = 1,000, Day 2 = 961.54, Day 3 = 983.33.
   - Test all 4 rollover modes (`SPREAD_EVENLY`, `NEXT_DAY`, `WEEK_ONLY`, `TO_SAVINGS`).
   - Test edge cases: $N=1$, zero spending, budget exhausted, partial final week.
2. **Integration Tests (`test/integration/spending-plan.test.ts`):**
   - Test plan creation, transaction ingestion, and automatic snapshot recomputation.
   - Test Reimbursement linking: assert that linking 500 ETB reimbursement credit to 1,000 ETB expense reduces spent total to 500 ETB.
3. **AI Tools Tests (`test/integration/ai-plan-tools.test.ts`):**
   - Test `get_active_plan_snapshot` and `simulate_plan_spending` tool execution with mocked LLM callbacks.

---

## 13. Rollout & Rollback Plan

- **Rollout:**
  1. Apply Prisma migrations via `npx prisma db push` (additive changes only, zero downtime).
  2. Deploy Fastify routes and BullMQ workers.
  3. Validate OTA pattern endpoint (`GET /v1/templates/patterns`).
- **Rollback:**
  - If a bug is detected in `computeSnapshot`, revert the calculation service without needing database rollback (all snapshots can be safely recalculated from raw transactions at any time).

---

## 14. Open Questions
- Should unspent funds in `SPREAD_EVENLY` mode ever be swept automatically to a linked SavingPlan at the end of the period? (Deferred to user preference toggle).
- Should category limits affect global daily allowance if breached, or stay as advisory alerts? (Default: advisory alerts, with an optional toggle to reduce flexible budget).

---

## 15. References
- Adaptive Spending Limit Feature Specification (Chat Brief 2026-10-10)
- Totals Repository Reference: [reference_repos/totals](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/reference_repos/totals)
- Fastify & Prisma Documentation

---

## 16. Decision Log
- **2026-10-10:** Backend Phase 2 specification created. Decisions made to adopt 5 sequential milestones covering Prisma migrations, pure TypeScript calculation math, REST APIs, BullMQ schedulers, and AI tool calling.
