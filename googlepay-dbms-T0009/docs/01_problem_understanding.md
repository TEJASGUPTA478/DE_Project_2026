# Phase 1: Problem Understanding & Workload Characterization

**Project:** Google Pay (UPI) Digital Payments Database System  
**Course:** Database Management Systems (DE Project 2026) · **Team No.:** T0009  
**Team Members:** Tejas Gupta (Lead), Priyank Gurnani, Parth Saklani, Parth Kumawat  

---

## 1. Business Problem Analysis (P1 – P8)

| # | Problem Statement (Business Need & Root Pain Point) | Affected Stakeholders | Workload Classification | Target SLA (Large Dataset) |
|---|---------------------------------------------------|-----------------------|-------------------------|---------------------------:|
| **P1** | **Transaction History & Pay Screen Latency:** Active users experience severe latency loading their past transactions (`R01`), verifying recipient VPAs (`R02`), and fetching linked bank accounts (`R22`). High query time directly harms checkout completion and user trust. | Payer, Payee, Consumer App Team | **Customer-facing / Real-time** | **< 5 ms** |
| **P2** | **Daily UPI Limit Check Bottleneck:** On every outgoing transaction, the system aggregates daily sent volume (`R03`, `W01`) to enforce NPCI's ₹1,00,000 regulatory limit. Sequential table scans on the 250k+ ledger introduce unacceptable payment authorization latency. | Payer, Payments Core Engine, NPCI / Regulators | **Customer-facing / Real-time** | **< 5 ms** |
| **P3** | **Reconciliation & Bank Callback Lag:** Operations teams struggle to detect stalled `PENDING` payments older than 15 minutes (`R04`), while incoming bank webhook callbacks (`W02`) lag in updating transaction states, locking funds and delaying user notifications. | Ops / Reconciliation, Partner Banks, Payer, Payee | **Real-time / Operations** | **< 5 ms** |
| **P4** | **Merchant Collections, Settlement & Engagement:** Merchants require real-time hourly collection metrics (`R05`) and automated nightly batch settlement aggregations (`R06`). The merchant success team's onboarding triage query (`R13`) returns zero rows due to SQL `NULL` handling bugs. | Merchants, Merchant Success Team, Finance / Settlement Ops | **Interactive Merchant Tools (`R05`, `R13`)** / **Reporting & Analytics (`R06`)** | **< 250 ms** (`R05`, `R13`) / **< 5,000 ms** (`R06`) |
| **P5** | **Fraud & Risk Monitoring in Near Real-Time:** Risk systems must identify mule accounts receiving payments from 5+ distinct payers daily (`R08`), detect rapid velocity repeat payments within 10 minutes (`R09`), and track merchant refund anomalies (`R17`). | Fraud & Risk Team, Compliance, Merchant Risk | **Reporting / Risk & Analytics** | **< 5,000 ms** |
| **P6** | **Rewards & Bill Reminders Job Bottlenecks:** Consumer app experiences sluggish reward scratch-card rendering (`R10`) and overdue bill reminders (`R12`). Nightly batch expiration (`W04`), bill overdue marking (`W05`), and notification sweeps (`R11`) cause lock contention. | Consumer (Payer), Rewards & Growth Team, Utility Billers | **Customer-facing (`R10`, `R12`, `W03`)** / **Interactive & Batch (`R11`, `W04`, `W05`)** | **< 5 ms** (App) / **< 250 ms** (`R11`) / **< 1,000 ms** (Batch) |
| **P7** | **Compliance Reporting & Customer Dispute SLA Queues:** Regulatory compliance requires auditing unverified KYC accounts transacting ₹10,000+ (`R18`). Support desks need sub-millisecond lookup by 12-digit UPI reference (`R24`), fast queueing of SLA-breached open disputes (`R16`), and pagination (`R23`). | RBI / Regulators, Customer Support, Grievance Officer, Payer | **Customer-facing (`R24`)** / **Interactive Ops (`R16`, `R23`)** / **Regulatory Reporting (`R18`)** | **< 5 ms** (`R24`) / **< 250 ms** (`R16`, `R23`) / **< 5,000 ms** (`R18`) |
| **P8** | **Bank Health Telemetry & 20× Scale Readiness:** Partner bank health dashboards tracking failure codes (`R07`), end-to-end latency (`R25`), merchant GMV city rankings (`R15`), active merchant performance (`R19`), platform success rates (`R20`), and business searches (`R21`) time out, posing severe collapse risks under projected 20× growth. | Bank Partnerships, Infrastructure Engineers, Executive Leadership | **Interactive Search (`R21`)** / **Reporting & Analytics (`R07`, `R15`, `R19`, `R20`, `R25`)** | **< 250 ms** (`R21`) / **< 5,000 ms** (Analytics) |

---

## 2. Key Assumptions

1. **UPI Interoperability & External Payees:** In compliance with NPCI UPI interoperability guidelines, Google Pay users initiate transactions to payees registered on third-party UPI apps (e.g., PhonePe `@ybl`, Paytm `@paytm`, Axis `@axl`). Hence, while `payer_vpa` strictly references Google Pay's internal `vpas` table, `payee_vpa` stores external handles and cannot enforce an internal foreign key.
2. **Transaction Immutability:** Financial ledger entries (`transactions`) are append-only and immutable once transitioned to terminal states (`SUCCESS`, `FAILED`, `REVERSED`, `REFUNDED`). Deletions are forbidden (`ON DELETE RESTRICT`).
3. **Statutory Limits:** NPCI mandates a standard cap of ₹1,00,000 per UPI transaction and per-day cumulative debit limit for P2P transfers.
4. **Timezone Standardization:** All timestamps are recorded with timezone offsets (`TIMESTAMPTZ`) normalized to Indian Standard Time (`UTC+05:30`).
5. **Primary Bank Account Rule:** Every registered user has exactly one active primary bank account used as the default debit source for outward payments.
