# SW-Budget: Complete Product & Domain Design Brief
> **Target Audience for this Document:** UI/UX Designers and AI Design Generators (e.g., Figma AI, Galileo, v0, Relume).  
> **Goal:** Provide exhaustive context on all financial entities, data models, workflows, and domain signals in SW-Budget without imposing rigid wireframe constraints, empowering the designer to craft an optimal, modern user experience.

---

## 1. Executive Summary & Product Vision

**SW-Budget** is a privacy-first, next-generation personal finance, liquidity tracking, and AI budgeting platform built specifically for the Ethiopian financial landscape.

In Ethiopia, traditional Open Banking APIs do not exist. Financial life is split across state and private commercial banks (**CBE, BoA, Awash**) and mobile money super-apps (**Telebirr, CBE Birr**), with financial events arriving via real-time SMS notifications, USSD receipts, and push notifications. 

SW-Budget automatically ingests, cryptographically verifies, deduplicates, and reconstructs the user's complete financial ledger and liquidity state entirely on-device, offering proactive daily guidance rather than passive retrospective reports.

* **Primary Currency:** ETB (Ethiopian Birr).
* **Target Audience:** Ethiopian urban professionals, freelancers, students, and businesses who manage multiple bank accounts, wallets, and cash on hand.
* **Key Design Ethos:** Premium, calm, authoritative, privacy-respecting, and modern (comparable to Linear, Revolut, Copilot, or Apple Card, but rooted in Ethiopian realities).

---

## 2. Core Domain Sections & Data Specifications

---

### Section 1: User Identity, Security & System Health

#### Available Data Fields & State:
* **User Profile:**
  * `Full Name` / `Display Name` (e.g., "Samuel Tefera", "Selam, Samuel").
  * `Email` / `Phone Number` (Ethiopian format: `+251 9...`).
  * `Profile Avatar` / Initials badge.
* **Security & Privacy Controls:**
  * `Biometric Lock State` (Face ID / Fingerprint enabled, app locked/unlocked).
  * `Privacy Mode Toggle` (Global eye mask that blinds balances and amounts to `ETB ••••••` when in public).
  * `Local Encryption State` (Encrypted on-device SQLite ledger via SQLCipher with device-bound AES-256 keys).
* **System & Synchronization Diagnostics:**
  * `Sync Engine Status` (`Idle`, `Syncing`, `Offline`, `Error`).
  * `Last Cloud Sync Timestamp` (e.g., "Synced 2 minutes ago").
  * `SMS / Notification Access Permission` (`Granted`, `Restricted`, `Background Battery Optimization Exempt`).
  * `Unsynced Local Mutations Count` (Pending offline actions waiting to push to backend).

---

### Section 2: Financial Institutions & Liquidity Portfolio (Accounts)

The user does not hold money in an abstract vacuum—wealth is held across specific institutions with distinct characteristics.

#### Institutions Supported:
1. **Commercial Bank of Ethiopia (CBE):** Premier national bank. Purple/Wine brand accent (`#8B1538`). High-volume transactions, salary deposits, transfers.
2. **Telebirr (Ethio Telecom):** Ubiquitous mobile money wallet. Sky Blue brand accent (`#0284C7`). Frequent micro-transactions, merchant QR payments, airtime, utilities.
3. **Bank of Abyssinia (BoA / Apollo):** Progressive modern bank. Warm Gold/Amber brand accent (`#F59E0B`). High digital adoption, card payments.
4. **Awash Bank:** Leading private bank. Navy Blue accent (`#1E3A8A`).
5. **CBE Birr:** USSD & mobile wallet companion to CBE.
6. **Physical Cash Wallet:** On-hand physical banknotes. Untethered from SMS, updated manually or when ATM withdrawals occur.
7. **Unlinked / Detected Candidate Banks:** Institutions detected in incoming messages (e.g., "312 messages detected from CBE Birr", "73 messages from Apollo") waiting for 1-tap onboarding.

#### Data Models & Fields per Account:
* `Account ID` (UUID).
* `Provider Code` (`CBE`, `TELEBIRR`, `BOA`, `AWASH`, `CASH_WALLET`).
* `Account Name` (e.g., "Main Salary Account", "Telebirr Personal", "Pocket Cash").
* `Account Mask / Identifier` (e.g., `•••• 4892` or mobile number).
* `Reconciled Balance` (Current verified net balance in ETB, e.g., `ETB 15,167.31`).
* `Account Type`:
  * `Transactional / Liquid` (Included in active safe-to-spend allowance).
  * `Savings / Locked` (Excluded from daily liquid spending, e.g., fixed-deposit or emergency fund).
* `Candidate Indicator`: Boolean flag if this bank is discovered in SMS inbox but not yet activated.
* `Unprocessed Message Count`: Number of raw messages awaiting parsing for this provider.

#### Aggregate Liquidity Metrics:
* **Total Portfolio Net Worth / Liquid Balance:** Sum of all active accounts in ETB.
* **Institutional Breadth:** Total number of connected banks, accounts, and lifetime processed transactions.
* **Cashflow Aggregates:** Total historical inflows (`+ETB 1.64M`) vs total historical outflows (`-ETB 1.65M`).
* **Cash vs. Digital Split:** % of liquidity held in bank accounts vs mobile money vs physical cash.

---

### Section 3: Financial Events, Ledger & Activity (Transactions)

Every movement of money is a transactional event parsed from natural language notifications or logged manually.

#### Data Models & Fields per Transaction:
* `Transaction ID` & `Deduplication Key` (Ensures SMS + Push notification for the same transaction is never counted twice).
* `Direction / Type`:
  * `Debit / Expense / Outflow` (Money leaves the user).
  * `Credit / Income / Inflow` (Money received by the user).
  * `Transfer` (Money moving between user's own accounts, e.g., Bank -> Telebirr).
* `Amount`: Value in ETB (e.g., `ETB 1,450.00`).
* `Counterparty / Merchant`: Name of the sender, recipient, or store (e.g., "Abebe Kebede", "Total Bole Station", "Ethio Telecom Package", "Café Tomoca", "Addis Supermarket").
* `Timestamp`: Exact event date and time (`YYYY-MM-DD HH:mm:ss`).
* `Account Source`: Which bank or wallet was debited or credited.
* `Running Balance`: Post-transaction balance explicitly stated by the bank in the notification (e.g., "Your current balance is ETB 12,450.20").
* `Verification State`:
  * `Verified`: The computed transaction mathematically matches the preceding and subsequent running balances.
  * `Unverified`: Single notification without consecutive running balance confirmation.
* `Balance Gap Detection (Audit Signal)`:
  * `has_gap`: Boolean flag indicating a missing event occurred (e.g., cash spent or unparsed transaction occurred between event A and event B).
  * `gap_amount`: The exact discrepancy (e.g., `100.00 ETB unaccounted before this event`).
* `Category`:
  * Standard taxonomy: *Food & Groceries, Transport & Fuel, Utilities & Telecom, Shopping, Housing & Rent, Health & Fitness, Entertainment, Salary & Wages, Business / Freelance, Family Support, Miscellaneous*.
* `Categorization Origin`: `AI Auto-categorized`, `User Manually Set`, `Uncategorized`.
* `Needs Review Flag`: Boolean indicating user attention is required.
* `Raw Notification Body`: The original Amharic or English SMS text from the bank (accessible for audit transparency).
* `Reference Number`: Bank reference string (e.g., `FT24098Z98K`, `B2C20241010`).
* `User Note`: Optional text memo or description added by the user.

---

### Section 4: Triage & Audit (Review Inbox)

A dedicated triage system ensuring 100% data integrity with minimal cognitive friction.

#### Data Models & Pending Items:
* **Uncertain Transaction Categorization:** Transactions where merchant is ambiguous (e.g., individual transfer that could be rent, loan repayment, or dinner split).
* **Missing Gap Events:** Prompts asking the user if an ATM cash withdrawal was spent on cash items.
* **Unparsed / New Bank Senders:** Unrecognized SMS formats from regional or newly launched fintechs allowing user confirmation.
* **Pending Count Badge:** Total number of items requiring a 1-tap confirmation (e.g., `3 items to review`).
* **Resolution Actions:**
  * Accept suggested category.
  * Reclassify as "Internal Transfer" (neutralizing impact on budget).
  * Mark as "Reimbursable" / "Split with friend".
  * Dismiss or ignore.

---

### Section 5: Adaptive Budgeting & Dynamic Safe-To-Spend (Plan)

Unlike rigid budgeting apps that fail when an unexpected expense occurs, SW-Budget uses **adaptive burn-rate math**:

$$\text{Daily Safe Spend} = \frac{\text{Remaining Unallocated Budget} - \text{Known Upcoming Bills}}{\text{Days Remaining in Cycle}}$$

#### Data Models & Metrics:
* **Dynamic Daily Allowance ("Safe Today"):**
  * The exact amount the user can spend today without exceeding their targets (e.g., `ETB 540.00 / day`).
  * Updates in real-time as transactions occur throughout the day.
* **Budget Health / Velocity Status:**
  * `AHEAD`: Spending significantly slower than planned capacity (Surplus accumulating).
  * `ON TRACK`: Spending within $\pm 5\%$ of target burn rate.
  * `CAUTION`: Spending 5%–25% faster than planned daily capacity.
  * `DEFICIT`: Over-budget or burn rate exceeds remaining capacity before cycle end.
* **Cycle Tracking:**
  * `Cycle Type`: Monthly (1st to 30th/31st), Custom Paycheck Cycle (e.g., 25th to 24th).
  * `Days Elapsed` vs. `Days Remaining` in period (e.g., "12 days passed • 18 days left").
* **Financial Capacity Breakdown:**
  * `Total Planned Monthly Budget` (e.g., `ETB 25,000.00`).
  * `Total Spent So Far` (e.g., `ETB 14,585.00`).
  * `Remaining Unallocated Budget` (e.g., `ETB 10,415.00`).
  * `Burn Ratio`: Ratio of actual expenditure vs expected linear expenditure to date.
* **Category Envelopes:**
  * Target limit per category (e.g., Food: `ETB 8,000`, Transport: `ETB 3,500`).
  * Current spend progress: Spent amount, remaining amount, percentage consumed.
  * Mode: `Soft Limit` (gentle notification) vs `Hard Limit` (strict budget boundary).
  * Threshold warnings: Crossed 50%, 80%, 100% of envelope.
* **Saving Goal Jars:**
  * `Goal Name` (e.g., "Emergency Fund", "New Laptop", "Meskel Holiday Trip").
  * `Target Goal Amount` (e.g., `ETB 50,000`).
  * `Saved So Far` (e.g., `ETB 18,500`).
  * `Target Completion Date`.
  * `Required Monthly Savings Contribution` (e.g., `ETB 3,500 / month`).
  * `Progress Percentage & Milestones`.

---

### Section 6: Financial Intelligence, Trends & AI Coach (Insights)

Transforms raw transaction rows into actionable strategic understanding.

#### Data Models & Analytical Dimensions:
* **Time Windows:** `7 Days`, `30 Days`, `This Month vs Last Month`, `Annual / Year-to-Date`.
* **Cashflow Velocity Vectors:**
  * Daily Inflow time-series curve (Income peaks).
  * Daily Outflow time-series curve (Spending trajectory).
  * Net Cashflow delta (Surplus / Deficit).
  * Savings Rate Percentage: $\frac{\text{Net Income} - \text{Total Expenses}}{\text{Net Income}} \times 100$.
* **Spending Composition & Distribution:**
  * Categorical breakdown (Percentage distribution across food, utilities, transport, etc.).
  * Top Merchants & Counterparties ranked by volume and transaction frequency.
* **Proactive AI Financial Insights:**
  * Contextual insight cards with urgency ranking (`Info`, `Positive Celebration`, `Warning Alert`).
  * Examples of insight signals:
    * *"You have spent 28% less on Telebirr airtime this week compared to last week."*
    * *"You've saved ETB 10,415.00 this month, 184% better than your 3-month baseline."*
    * *"Rent payment of ETB 12,000 expected in 4 days. Safe daily spend adjusted accordingly."*
* **Conversational AI Financial Coach:**
  * Natural language chat assistant with full access to user's local ledger context.
  * Capabilities:
    * Answering questions ("How much have I spent on coffee and restaurants this month?").
    * Scenario simulations ("Can I afford to buy a 15,000 ETB camera this weekend?").
    * Generating instant PDF / CSV export statements for embassy or loan applications.

---

### Section 7: Peer Debts, Reimbursements & Shared Expenses

Ethiopian social and commercial life heavily involves informal lending, group meals (Gursha/splits), and workplace expense fronting.

#### Data Models:
* **Owed to Me (Receivables / Lendings):**
  * Debtor Name / Contact.
  * Amount in ETB.
  * Due Date / Date Lent.
  * Linked Transaction (e.g., an outgoing 500 ETB dinner payment converted to a loan).
  * Settlement Status (`Unpaid`, `Partially Paid`, `Settled`).
* **Owed by Me (Payables / Borrowings):**
  * Creditor Name / Lender.
  * Amount, Due Date, Repayment notes.
* **Reimbursement Workflow:**
  * Work-related expense fronted by employee awaiting company refund.
  * Status: `Pending Refund`, `Claim Submitted`, `Reimbursed`.

---

## 3. Key Quantitative Entities & Sample Data Ranges

To help the design tool visualize realistic typography and component density, here are typical realistic values:

| Data Point | Typical Range / Realistic Example | Formatting Convention |
|---|---|---|
| **Total Balance** | `ETB 15,707.62` to `ETB 1,450,200.00` | `ETB 15,707.62` (Commas, 2 decimals) |
| **Masked Balance** | `ETB ••••••••` | Uniform privacy dots |
| **Daily Safe Spend** | `ETB 340.00 / day` to `ETB 2,500.00 / day` | Integer or 2 decimals |
| **Small Transaction** | `ETB 5.00` (Telebirr airtime) to `ETB 65.00` (Macchiato) | Signed: `- ETB 65.00` / `+ ETB 50.00` |
| **Medium Transaction** | `ETB 450.00` (Taxi) to `ETB 3,200.00` (Groceries) | Counterparty bold, category pill |
| **Large Transaction** | `ETB 15,000.00` (Salary) to `ETB 45,000.00` (Rent) | High-contrast visual emphasis |
| **Aggregate Volume** | `+ETB 1.64M` / `-ETB 1.65M` | Abbreviated K / M format for cards |
| **Transaction Counts** | `1,595 Transactions` across `4 Banks` | Clean metadata row |
| **Time Formats** | `Today, 08:13`, `Yesterday, 14:22`, `Oct 8, 2026` | Relative or compact absolute |

---

## 4. Design Guidelines & Freedom for the AI Designer

> [!TIP]
> **Instructions for the AI Designer:**
> 1. **Do not copy legacy tables or plain list views.** Design with hierarchy, depth, and intentional visual weight.
> 2. **Prioritize Immediate Clarity:** When a user opens their financial cockpit, they should immediately answer three questions:
>    * *How much liquid money do I have right now?*
>    * *How much can I safely spend today?*
>    * *Did any unexpected event or gap occur that needs my attention?*
> 3. **Honor the Ethiopian Banking Context:** The user operates across multiple distinct banking identities (CBE, Telebirr, BoA, Awash, Cash). Treat each institution as an authentic, first-class financial hub with recognizable branding and clear distinction between bank deposits, mobile money, and physical cash.
> 4. **Emphasize Proactive Guidance Over Dead History:** The Adaptive Safe-To-Spend allowance and AI coaching insights should feel like a personal CFO sitting in the user's pocket.
> 5. **Privacy by Design:** Seamless, tactile privacy controls (eye toggles, biometric lock shields) should feel organic and effortless.
> 6. **Visual Tone:** Sophisticated dark mode (Obsidian / Navy Slate), high-contrast readability, glassmorphic elevation, and deliberate semantic color coding (Emerald for inflows, Coral for outflows, Warm Ethiopian Amber for insights and warnings).
