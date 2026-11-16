-- -------------------------------------------------
-- Phase 4 Indexes – Google Pay (UPI) Database
-- Schema: gpay
-- -------------------------------------------------
-- 1.  Indexes that directly support the 30 workload queries
-- 2.  Composite, partial and covering indexes where beneficial
-- 3.  No duplicate of existing PK/UNIQUE constraints
-- -------------------------------------------------

-- -------------------------------------------------
-- 1️⃣ Transaction‑history look‑ups (R01, R22, R23)
-- -------------------------------------------------
-- Users frequently search transactions by a VPA (payer or payee)
-- and order by the most recent `initiated_at`.
CREATE INDEX IF NOT EXISTS idx_transactions_payer_vpa_ts
    ON gpay.transactions (payer_vpa, initiated_at);
CREATE INDEX IF NOT EXISTS idx_transactions_payee_vpa_desc
    ON gpay.transactions (payee_vpa, initiated_at DESC);

-- -------------------------------------------------
-- 2️⃣ Daily‑limit checks (R03)
-- -------------------------------------------------
-- Queries filter on `status` (SUCCESS/PENDING) **and** a specific date.
-- A partial index isolates the useful rows and makes the date predicate sargable.
CREATE INDEX IF NOT EXISTS idx_transactions_success_pending_date
    ON gpay.transactions (date(initiated_at))
    WHERE status IN ('SUCCESS','PENDING');

-- -------------------------------------------------
-- 3️⃣ Pending‑transaction reconciliation (R04)
-- -------------------------------------------------
-- Reconcile only rows with status = 'PENDING'.
CREATE INDEX IF NOT EXISTS idx_transactions_pending
    ON gpay.transactions (status)
    WHERE status = 'PENDING';

-- -------------------------------------------------
-- 4️⃣ Merchant‑centric reports (R05‑R07, R14‑R20)
-- -------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_transactions_merchant_id
    ON gpay.transactions (merchant_id);
CREATE INDEX IF NOT EXISTS idx_merchants_vpa
    ON gpay.merchants (merchant_vpa);

-- -------------------------------------------------
-- 5️⃣ Fraud / repeated‑payment analytics (R08‑R09)
-- -------------------------------------------------


-- -------------------------------------------------
-- 6️⃣ Rewards look‑ups (R10‑R11)
-- -------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_rewards_user_status_expiry
    ON gpay.rewards (user_id, status, expires_at)
    INCLUDE (reward_id, reward_type, amount, issued_at, credited_at);

-- -------------------------------------------------
-- 7️⃣ Unpaid bill reminders (R12)
-- -------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_billpayments_unpaid_due
    ON gpay.bill_payments (status, due_date)
    WHERE status = 'DUE';

-- -------------------------------------------------
-- 8️⃣ Write‑heavy batch jobs (W01‑W05)
-- -------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_transactions_status_date
    ON gpay.transactions (status, date(initiated_at));
CREATE INDEX IF NOT EXISTS idx_disputes_status
    ON gpay.disputes (status);

-- -------------------------------------------------
-- 9️⃣ Miscellaneous helpers
-- -------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_vpas_user_id ON gpay.vpas (user_id);
CREATE INDEX IF NOT EXISTS idx_users_city_id ON gpay.users (city_id);
CREATE INDEX IF NOT EXISTS idx_bank_accounts_user_id ON gpay.bank_accounts (user_id);
