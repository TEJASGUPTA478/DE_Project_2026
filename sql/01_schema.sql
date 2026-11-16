-- ============================================================================
-- Google Pay (UPI) Database Schema: Phase 2 (CP1)
-- Database Engine: PostgreSQL 15+
-- Schema: gpay
-- 
-- Rules:
-- 1. Table names and column names match CSV seed data headers exactly.
-- 2. Constraints only: PRIMARY KEY, UNIQUE, FOREIGN KEY, NOT NULL, CHECK.
-- 3. No secondary/tuning indexes created here (baseline for Phase 3).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS gpay;
SET search_path TO gpay;

-- Clean slate: Drop existing tables in reverse dependency order
DROP TABLE IF EXISTS disputes CASCADE;
DROP TABLE IF EXISTS bill_payments CASCADE;
DROP TABLE IF EXISTS rewards CASCADE;
DROP TABLE IF EXISTS transactions CASCADE;
DROP TABLE IF EXISTS merchants CASCADE;
DROP TABLE IF EXISTS vpas CASCADE;
DROP TABLE IF EXISTS bank_accounts CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

-- ----------------------------------------------------------------------------
-- 1. cities
-- Reference master data for user residency and merchant business locations.
-- ----------------------------------------------------------------------------
CREATE TABLE cities (
    city_id     INT PRIMARY KEY,
    city_name   VARCHAR(100) NOT NULL,
    state       VARCHAR(100) NOT NULL
);

-- ----------------------------------------------------------------------------
-- 2. users
-- Registered Google Pay consumer profiles.
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    user_id     INT PRIMARY KEY,
    full_name   VARCHAR(150) NOT NULL,
    phone       VARCHAR(15) NOT NULL UNIQUE,
    email       VARCHAR(255) UNIQUE,
    city_id     INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    kyc_status  VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    is_blocked  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT chk_users_phone CHECK (phone ~ '^[0-9]{10}$'),
    CONSTRAINT chk_users_email CHECK (email IS NULL OR email ~ '^[^@]+@[^@]+\.[^@]+$'),
    CONSTRAINT chk_users_kyc_status CHECK (kyc_status IN ('PENDING', 'VERIFIED', 'REJECTED'))
);

-- ----------------------------------------------------------------------------
-- 3. bank_accounts
-- Bank accounts linked by consumers via NPCI UPI bank integration.
-- ----------------------------------------------------------------------------
CREATE TABLE bank_accounts (
    account_id    INT PRIMARY KEY,
    user_id       INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    bank_name     VARCHAR(100) NOT NULL,
    ifsc          VARCHAR(11) NOT NULL,
    account_last4 VARCHAR(4) NOT NULL,
    account_type  VARCHAR(20) NOT NULL DEFAULT 'SAVINGS',
    is_primary    BOOLEAN NOT NULL DEFAULT FALSE,
    linked_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT chk_bank_accounts_ifsc CHECK (ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
    CONSTRAINT chk_bank_accounts_last4 CHECK (account_last4 ~ '^[0-9]{4}$'),
    CONSTRAINT chk_bank_accounts_type CHECK (account_type IN ('SAVINGS', 'CURRENT'))
);

-- ----------------------------------------------------------------------------
-- 4. vpas
-- Virtual Payment Addresses (UPI handles) mapped to bank accounts.
-- Natural identifier of UPI transactions; strictly 1:1 with bank account.
-- ----------------------------------------------------------------------------
CREATE TABLE vpas (
    vpa         VARCHAR(100) PRIMARY KEY,
    user_id     INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    account_id  INT NOT NULL UNIQUE REFERENCES bank_accounts(account_id) ON DELETE CASCADE,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT chk_vpas_format CHECK (vpa ~ '^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$')
);

-- ----------------------------------------------------------------------------
-- 5. merchants
-- Verified business entities and merchants accepting QR / P2M payments.
-- ----------------------------------------------------------------------------
CREATE TABLE merchants (
    merchant_id   INT PRIMARY KEY,
    merchant_name VARCHAR(150) NOT NULL,
    mcc           VARCHAR(4) NOT NULL,
    merchant_vpa  VARCHAR(100) NOT NULL UNIQUE,
    city_id       INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    is_verified   BOOLEAN NOT NULL DEFAULT FALSE,
    onboarded_on  DATE NOT NULL,

    -- Constraints
    CONSTRAINT chk_merchants_mcc CHECK (mcc ~ '^[0-9]{4}$'),
    CONSTRAINT chk_merchants_vpa CHECK (merchant_vpa ~ '^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$')
);

-- ----------------------------------------------------------------------------
-- 6. transactions
-- Immutable ledger of all UPI payments (P2P and P2M).
-- Payee VPA is not FK constrained to vpas table to support UPI interoperability
-- (payments sent to users on external apps like PhonePe, Paytm, BHIM).
-- ----------------------------------------------------------------------------
CREATE TABLE transactions (
    txn_id        BIGINT PRIMARY KEY,
    upi_ref       VARCHAR(12) NOT NULL UNIQUE,
    txn_type      VARCHAR(10) NOT NULL,
    payer_vpa     VARCHAR(100) NOT NULL REFERENCES vpas(vpa) ON DELETE RESTRICT,
    payee_vpa     VARCHAR(100) NOT NULL,
    merchant_id   INT REFERENCES merchants(merchant_id) ON DELETE RESTRICT,
    amount        NUMERIC(12, 2) NOT NULL,
    note          VARCHAR(255),
    initiated_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at  TIMESTAMPTZ,
    status        VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    failure_code  VARCHAR(10),

    -- Constraints
    CONSTRAINT chk_transactions_upi_ref CHECK (upi_ref ~ '^[0-9]{12}$'),
    CONSTRAINT chk_transactions_amount CHECK (amount > 0 AND amount <= 100000.00),
    CONSTRAINT chk_transactions_txn_type CHECK (txn_type IN ('P2P', 'P2M')),
    CONSTRAINT chk_transactions_status CHECK (status IN ('SUCCESS', 'PENDING', 'FAILED', 'REVERSED', 'REFUNDED')),
    CONSTRAINT chk_transactions_payer_payee CHECK (payer_vpa <> payee_vpa),
    CONSTRAINT chk_transactions_p2m_merchant CHECK (
        (txn_type = 'P2M' AND merchant_id IS NOT NULL) OR
        (txn_type = 'P2P' AND merchant_id IS NULL)
    ),
    CONSTRAINT chk_transactions_failure_code CHECK (
        (status = 'FAILED' AND failure_code IS NOT NULL) OR
        (status <> 'FAILED' AND failure_code IS NULL)
    ),
    CONSTRAINT chk_transactions_pending_completed CHECK (
        (status = 'PENDING' AND completed_at IS NULL) OR
        (status <> 'PENDING' AND completed_at IS NOT NULL)
    ),
    CONSTRAINT chk_transactions_refund_p2m CHECK (
        status <> 'REFUNDED' OR txn_type = 'P2M'
    ),
    CONSTRAINT chk_transactions_completed_order CHECK (
        completed_at IS NULL OR completed_at >= initiated_at
    )
);

-- ----------------------------------------------------------------------------
-- 7. rewards
-- Promotional cashback, coupons, and scratch cards earned on payments.
-- ----------------------------------------------------------------------------
CREATE TABLE rewards (
    reward_id    INT PRIMARY KEY,
    user_id      INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    txn_id       BIGINT NOT NULL UNIQUE REFERENCES transactions(txn_id) ON DELETE RESTRICT,
    reward_type  VARCHAR(20) NOT NULL,
    amount       NUMERIC(10, 2) NOT NULL,
    status       VARCHAR(20) NOT NULL DEFAULT 'UNSCRATCHED',
    issued_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at   TIMESTAMPTZ NOT NULL,
    credited_at  TIMESTAMPTZ,

    -- Constraints
    CONSTRAINT chk_rewards_reward_type CHECK (reward_type IN ('SCRATCH_CARD', 'CASHBACK', 'COUPON')),
    CONSTRAINT chk_rewards_status CHECK (status IN ('UNSCRATCHED', 'CREDITED', 'EXPIRED')),
    CONSTRAINT chk_rewards_amount CHECK (amount >= 0),
    CONSTRAINT chk_rewards_expires CHECK (expires_at >= issued_at),
    CONSTRAINT chk_rewards_credited CHECK (
        (status = 'CREDITED' AND credited_at IS NOT NULL) OR
        (status <> 'CREDITED' AND credited_at IS NULL)
    )
);

-- ----------------------------------------------------------------------------
-- 8. bill_payments
-- Recurring utility, telecommunication, and municipal bill payments.
-- ----------------------------------------------------------------------------
CREATE TABLE bill_payments (
    bill_id          INT PRIMARY KEY,
    user_id          INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    biller_category  VARCHAR(30) NOT NULL,
    biller_name      VARCHAR(100) NOT NULL,
    consumer_number  VARCHAR(50) NOT NULL,
    amount           NUMERIC(12, 2) NOT NULL,
    due_date         DATE NOT NULL,
    status           VARCHAR(20) NOT NULL DEFAULT 'DUE',
    paid_at          TIMESTAMPTZ,

    -- Constraints
    CONSTRAINT chk_bill_payments_category CHECK (
        biller_category IN ('MOBILE', 'ELECTRICITY', 'WATER', 'GAS', 'BROADBAND', 'DTH', 'FASTAG')
    ),
    CONSTRAINT chk_bill_payments_status CHECK (status IN ('DUE', 'OVERDUE', 'PAID')),
    CONSTRAINT chk_bill_payments_amount CHECK (amount > 0),
    CONSTRAINT chk_bill_payments_paid_at CHECK (
        (status = 'PAID' AND paid_at IS NOT NULL) OR
        (status <> 'PAID' AND paid_at IS NULL)
    )
);

-- ----------------------------------------------------------------------------
-- 9. disputes
-- Grievance and chargeback complaints raised by payers on transactions.
-- ----------------------------------------------------------------------------
CREATE TABLE disputes (
    dispute_id   INT PRIMARY KEY,
    txn_id       BIGINT NOT NULL UNIQUE REFERENCES transactions(txn_id) ON DELETE RESTRICT,
    raised_by    INT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    reason       VARCHAR(50) NOT NULL,
    raised_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status       VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    resolved_at  TIMESTAMPTZ,

    -- Constraints
    CONSTRAINT chk_disputes_reason CHECK (
        reason IN ('FRAUD', 'DUPLICATE_PAYMENT', 'MERCHANT_NOT_DELIVERED', 'WRONG_PAYEE', 'MONEY_DEBITED_NOT_CREDITED')
    ),
    CONSTRAINT chk_disputes_status CHECK (status IN ('OPEN', 'RESOLVED', 'REJECTED')),
    CONSTRAINT chk_disputes_resolved CHECK (
        (status = 'OPEN' AND resolved_at IS NULL) OR
        (status <> 'OPEN' AND resolved_at IS NOT NULL)
    ),
    CONSTRAINT chk_disputes_resolved_time CHECK (
        resolved_at IS NULL OR resolved_at >= raised_at
    )
);
