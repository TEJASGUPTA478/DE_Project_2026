# Baseline Timings Report (CP2 / Phase 3)

**Project:** Google Pay (UPI) Digital Payments Database System  
**Team:** T0009 · **Database:** PostgreSQL 15+ · **Schema:** `gpay`  

---

## 1. Measurement Methodology

- Every query was executed with `EXPLAIN (ANALYZE, BUFFERS)` on the unindexed baseline schema (`sql/01_schema.sql` + `sql/02_load_data.sql`).
- As required by the project specifications, each query was run **3 times**, and the recorded metric is the mathematical **average** of the three `Execution Time` values.
- Write queries (`W01`–`W05`) were executed inside transactional `BEGIN; ... ROLLBACK;` blocks to ensure absolute database state immutability.
- Benchmarks were executed via `./benchmarks/run_benchmark.sh <db> baseline` on the designated benchmark environment.
- Full raw execution plans for all 3 runs per query are preserved in `benchmarks/results/baseline/` and aggregated in `benchmarks/results/baseline/summary.csv`.

---

## 2. Baseline Performance Table (All 30 Workload Queries)

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|:---|:---:|---:|---:|---:|---:|
| **R01**: Transaction history: everything user 15177 sent or received, newest first | READ | 35.337 | 27.700 | 21.354 | **28.130** |
| **R02**: "Pay to UPI ID": check that the entered VPA exists and is active | READ | 0.057 | 0.053 | 0.041 | **0.050** |
| **R03**: UPI limit check: total successfully sent by user 15177 on 30 June 2026 (limit ₹1,00,000/day) | READ | 16.043 | 13.914 | 13.447 | **14.468** |
| **R04**: Reconciliation: payments still PENDING more than 15 minutes after 23:59 on 30 Jun 2026 | READ | 8.017 | 7.834 | 7.648 | **7.833** |
| **R05**: Google Pay for Business: hourly collections of merchant 2 on 29 June 2026 | READ | 7.401 | 7.292 | 6.865 | **7.186** |
| **R06**: Settlement: amount to settle to every merchant for 29 June 2026 | READ | 7.242 | 6.893 | 6.757 | **6.964** |
| **R07**: Bank health: failure codes per payer bank in the last 7 days | READ | 7.344 | 6.990 | 7.272 | **7.202** |
| **R08**: Fraud: VPAs that received P2P money from 5+ different people on the same day | READ | 345.424 | 348.475 | 351.740 | **348.546** |
| **R09**: Fraud: repeated payments—same payer to the same payee within 10 minutes of the previous one | READ | 857.090 | 850.276 | 862.078 | **856.481** |
| **R10**: Rewards tab: user 15177's unscratched cards that have not expired | READ | 1.824 | 2.027 | 1.944 | **1.932** |
| **R11**: Notification job: unscratched rewards that expire in the first 3 days of July | READ | 1.885 | 2.001 | 1.975 | **1.954** |
| **R12**: Bill reminders: user 1072's unpaid bills due in the next 7 days | READ | 1.808 | 2.890 | 2.532 | **2.410** |
| **R13**: Merchant success team: merchants who have never received a payment (to call and help them) | READ | 36.761 | 26.188 | 24.169 | **29.039** |
| **R14**: Spend analysis: user 15177's 2026 spending per merchant category code (MCC) | READ | 19.363 | 17.713 | 18.045 | **18.374** |
| **R15**: Business insights: top 10 merchants by June 2026 GMV in each city | READ | 9.283 | 9.038 | 9.152 | **9.158** |
| **R16**: Disputes desk: disputes open for more than 7 days (SLA breached) | READ | 0.326 | 0.331 | 0.337 | **0.331** |
| **R17**: Merchant risk: refund rate per merchant (at least 30 payments) | READ | 13.998 | 12.882 | 12.571 | **13.150** |
| **R18**: Compliance: users without verified KYC who have successfully sent ₹10,000+ in total | READ | 24.496 | 24.556 | 24.822 | **24.625** |
| **R19**: Merchant report: last payment time and successful payment count of every verified Bengaluru merchant | READ | 4416.962 | 4482.683 | 4497.387 | **4465.677** |
| **R20**: Platform health: daily success rate in June 2026 | READ | 10.086 | 10.206 | 9.837 | **10.043** |
| **R21**: "Search businesses": merchants with "chai" in their name | READ | 0.908 | 0.924 | 0.883 | **0.905** |
| **R22**: Payment screen: user 15177's primary bank account and all their UPI IDs | READ | 1.882 | 2.091 | 1.910 | **1.961** |
| **R23**: Operations console: all transactions, newest first, page 8,001 (25 per page) | READ | 69.329 | 61.417 | 61.538 | **64.095** |
| **R24**: Customer support: find a payment by its UPI reference number | READ | 0.042 | 0.038 | 0.049 | **0.043** |
| **R25**: Bank health: average seconds from initiation to completion per payer bank (June 2026) | READ | 24.543 | 22.441 | 25.184 | **24.056** |
| **W01**: Pay: user 15177 starts a ₹250 payment to merchant 2 (PENDING until the bank confirms) | WRITE | 0.522 | 0.568 | 0.808 | **0.633** |
| **W02**: Bank callback: mark the oldest PENDING payment as successful | WRITE | 21.624 | 20.164 | 19.906 | **20.565** |
| **W03**: Scratch card: user 15177 scratches their oldest unscratched card | WRITE | 1.901 | 1.689 | 1.606 | **1.732** |
| **W04**: Nightly job (run at 00:00 on 4 Jul 2026): expire every reward whose time is up | WRITE | 2.182 | 2.225 | 2.361 | **2.256** |
| **W05**: Nightly job: bills past their due date and still unpaid become OVERDUE | WRITE | 2.042 | 2.550 | 2.525 | **2.372** |
| **Total (sum of all 30)** | | | | | **5972.171** |

---

## 3. Query Plan Analysis & Execution Bottlenecks

| Query | Execution Time (Avg ms) | Primary Scan Type(s) in Plan | Root Cause Analysis (Why Fast / Slow) |
|:---:|---:|:---|:---|
| **R01** | 28.130 | `Seq Scan on transactions | Seq Scan on vpas` | Parallel Seq Scan on transactions (250k rows) and Seq Scan on vpas due to OR condition across payer_vpa and payee_vpa subqueries. |
| **R02** | 0.050 | `Index Scan using vpas_pkey on vpas | Index Scan using users_pkey on users` | Fast (0.050 ms) because it performs an Index Scan on vpas_pkey (VPA is PK) and Index Scan on users_pkey. |
| **R03** | 14.468 | `Seq Scan on transactions | Seq Scan on vpas` | Slow (14.47 ms) because of Seq Scan on transactions and un-sargable DATE(initiated_at) function call filtering all rows. |
| **R04** | 7.833 | `Seq Scan on transactions` | Slow (7.83 ms) due to full Seq Scan on transactions filtering for rare status='PENDING'; lacks partial index on status. |
| **R05** | 7.186 | `Seq Scan on transactions` | Slow (7.19 ms) due to Seq Scan on transactions filtering by merchant_id and timestamp range without composite index. |
| **R06** | 6.964 | `Seq Scan on transactions | Index Scan using merchants_pkey on merchants` | Slow (6.96 ms) due to Seq Scan on transactions filtering 250k rows for single day SUCCESS payments before grouping. |
| **R07** | 7.202 | `Seq Scan on transactions | Index Scan using vpas_pkey on vpas | Index Scan using bank_accounts_pkey on bank_accounts` | Slow (7.20 ms) due to Seq Scan on transactions for status='FAILED' and 7-day date range, joined with vpas and bank_accounts. |
| **R08** | 348.546 | `Seq Scan on transactions` | Very slow (348.55 ms) due to Seq Scan on transactions, large hash aggregation for count(DISTINCT payer_vpa) grouped by payee and date. |
| **R09** | 856.481 | `Seq Scan on transactions` | Extremely slow (856.48 ms) due to full Seq Scan, window function lag() over partition by payer_vpa, payee_vpa, and sort across all rows. |
| **R10** | 1.932 | `Seq Scan on rewards` | Moderate (1.93 ms) due to Seq Scan on rewards table (40k rows) filtering by user_id and status; lacks index on user_id. |
| **R11** | 1.954 | `Seq Scan on rewards` | Moderate (1.95 ms) due to Seq Scan on rewards filtering status='ISSUED' and timestamp range expires_at. |
| **R12** | 2.410 | `Seq Scan on bill_payments` | Moderate (2.41 ms) due to Seq Scan on bill_payments (30k rows) filtering user_id, status='DUE', and due_date range. |
| **R13** | 29.039 | `Seq Scan on merchants | Seq Scan on transactions` | Slow (29.04 ms) due to nested loop with Seq Scan on merchants and NOT IN (SELECT merchant_id FROM transactions) which fails on NULLs and causes subquery scan. |
| **R14** | 18.374 | `Seq Scan on transactions | Seq Scan on vpas | Index Scan using merchants_pkey on merchants` | Slow (18.37 ms) due to Seq Scan on transactions, Seq Scan on vpas, and join on merchants_pkey for single user analysis. |
| **R15** | 9.158 | `Seq Scan on transactions | Seq Scan on merchants` | Slow (9.16 ms) due to Seq Scan on transactions, join with merchants, window function DENSE_RANK() and aggregation. |
| **R16** | 0.331 | `Seq Scan on disputes | Index Scan using transactions_pkey on transactions` | Fast (0.33 ms) because disputes is small (3.5k rows) Seq Scan joined with Index Scan on transactions_pkey. |
| **R17** | 13.150 | `Seq Scan on transactions` | Slow (13.15 ms) due to Seq Scan on 250k transactions aggregating refund/reversal rates per merchant. |
| **R18** | 24.625 | `Seq Scan on transactions | Seq Scan on vpas | Seq Scan on users` | Slow (24.63 ms) due to Seq Scan on transactions, Seq Scan on vpas, and Seq Scan on users to find unverified accounts. |
| **R19** | 4465.677 | `Seq Scan on merchants | Seq Scan on transactions` | Catastrophically slow (4,465.68 ms) due to correlated scalar subqueries executed for every single merchant, each doing a full Seq Scan on transactions. |
| **R20** | 10.043 | `Seq Scan on transactions` | Slow (10.04 ms) due to Seq Scan on transactions aggregating success/failure counts across entire month of June. |
| **R21** | 0.905 | `Seq Scan on merchants` | Moderate (0.91 ms) due to Seq Scan on merchants table using ILIKE '%chai%' (no trigram GIN index). |
| **R22** | 1.961 | `Seq Scan on bank_accounts | Index Scan using vpas_account_id_key on vpas` | Moderate (1.96 ms) due to Seq Scan on bank_accounts filtering user_id and is_primary, joined with vpas. |
| **R23** | 64.095 | `Seq Scan on transactions` | Slow (64.10 ms) due to sorting 250k transactions and executing high OFFSET 200000 LIMIT 25 on unindexed initiated_at. |
| **R24** | 0.043 | `Index Scan using transactions_upi_ref_key on transactions` | Extremely fast (0.043 ms) because upi_ref has a UNIQUE constraint which creates an automatic unique B-tree index. |
| **R25** | 24.056 | `Seq Scan on transactions | Seq Scan on vpas | Seq Scan on bank_accounts` | Slow (24.06 ms) due to 3-table Seq Scan across transactions, vpas, and bank_accounts computing epoch duration differences. |
| **W01** | 0.633 | `(no scan)` | Fast (0.63 ms) single-row INSERT into transactions checking PK/FK constraints. |
| **W02** | 20.565 | `Index Scan using transactions_pkey on transactions` | Slow (20.57 ms) for a single-row update because subquery SELECT txn_id WHERE status='PENDING' ORDER BY initiated_at requires a full Seq Scan on transactions. |
| **W03** | 1.732 | `Seq Scan on rewards | Index Scan using rewards_pkey on rewards` | Moderate (1.73 ms) due to Seq Scan on rewards table to locate oldest ISSUED card for user. |
| **W04** | 2.256 | `Seq Scan on rewards` | Moderate (2.26 ms) due to Seq Scan on rewards table updating status of expired cards. |
| **W05** | 2.372 | `Seq Scan on bill_payments` | Moderate (2.37 ms) due to Seq Scan on bill_payments table finding unpaid past-due bills. |

---

## 4. Key Architectural Observations

1. **Correlated Subquery Disaster (R19):** R19 accounts for over 74% of the total baseline workload execution time (4,465.68 ms out of 5,972.17 ms). Because it executes two correlated scalar subqueries for each of the verified Bengaluru merchants without indexes on `transactions(merchant_id)`, it repeatedly parallel-scans the 250,468-row transaction table thousands of times.
2. **Large Aggregations & Window Functions (R08, R09):** R08 (348.55 ms) and R09 (856.48 ms) suffer from massive in-memory hash aggregation and window partitioning on unindexed text VPAs and timestamp attributes across the entire table.
3. **Missing Foreign Key Indexes:** PostgreSQL does not automatically index foreign keys. Lookups by `user_id` on `vpas`, `bank_accounts`, `rewards`, and `bill_payments`, or by `merchant_id` on `transactions` result in sequential scans table-wide.
4. **Non-Sargable Predicates (R03):** R03 calls `DATE(initiated_at) = '2026-06-30'`. Even if an index on `initiated_at` existed, expression wrapping prevents standard B-tree index usage.
5. **High Offset Pagination (R23):** Scanning and sorting 250k rows to discard the first 200,000 (`OFFSET 200000 LIMIT 25`) takes 64.10 ms.
6. **Fast Queries (R02, R24):** Only queries matching unique keys (Primary Key `vpa` on `vpas`, Unique `upi_ref` on `transactions`) execute sub-millisecond (< 0.05 ms) due to automatic unique B-tree indexes.
