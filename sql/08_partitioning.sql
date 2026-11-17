-- ============================================================================
-- Phase 5 (CP4): Table Partitioning Architecture for Google Pay Ledger
-- Database Engine: PostgreSQL 15+
-- Schema: gpay
-- 
-- Architecture:
-- The `transactions` table contains millions of rows (250k seed, 5M+ large,
-- projected 25M+ at 100x scale). Because queries predominantly filter by time
-- (e.g. daily settlement, recent payments, monthly health dashboards),
-- RANGE partitioning on `initiated_at` is the optimal partitioning strategy.
-- 
-- PostgreSQL Constraint Rule for Partitioned Tables:
-- Under PostgreSQL DDL rules, any UNIQUE or PRIMARY KEY constraint on a
-- partitioned table MUST include all partition key columns.
-- Therefore, the primary key becomes composite: (txn_id, initiated_at).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS gpay;
SET search_path TO gpay;

-- ----------------------------------------------------------------------------
-- 1. Partitioned Master Table Definition
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transactions_partitioned (
    txn_id        BIGINT NOT NULL,
    upi_ref       VARCHAR(12) NOT NULL,
    txn_type      VARCHAR(10) NOT NULL,
    payer_vpa     VARCHAR(100) NOT NULL,
    payee_vpa     VARCHAR(100) NOT NULL,
    merchant_id   INT,
    amount        NUMERIC(12,2) NOT NULL,
    note          VARCHAR(255),
    initiated_at  TIMESTAMPTZ NOT NULL,
    completed_at  TIMESTAMPTZ,
    status        VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    failure_code  VARCHAR(10),

    -- Primary key must include the partition key
    CONSTRAINT pk_transactions_partitioned PRIMARY KEY (txn_id, initiated_at),
    CONSTRAINT chk_ptxn_amount CHECK (amount > 0 AND amount <= 100000.00),
    CONSTRAINT chk_ptxn_type CHECK (txn_type IN ('P2P', 'P2M')),
    CONSTRAINT chk_ptxn_status CHECK (status IN ('SUCCESS', 'PENDING', 'FAILED', 'REVERSED', 'REFUNDED'))
) PARTITION BY RANGE (initiated_at);

-- ----------------------------------------------------------------------------
-- 2. Monthly Partitions (2025 – 2026)
-- ----------------------------------------------------------------------------
-- 2025 Partitions
CREATE TABLE IF NOT EXISTS transactions_y2025m01 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-02-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m02 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-02-01 00:00:00+05:30') TO ('2025-03-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m03 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-03-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m04 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-05-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m05 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-05-01 00:00:00+05:30') TO ('2025-06-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m06 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-06-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m07 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-08-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m08 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-08-01 00:00:00+05:30') TO ('2025-09-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m09 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-09-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m10 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2025-11-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m11 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-11-01 00:00:00+05:30') TO ('2025-12-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2025m12 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2025-12-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

-- 2026 Partitions
CREATE TABLE IF NOT EXISTS transactions_y2026m01 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-02-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2026m02 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-02-01 00:00:00+05:30') TO ('2026-03-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2026m03 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-03-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2026m04 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-05-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2026m05 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-05-01 00:00:00+05:30') TO ('2026-06-01 00:00:00+05:30');

CREATE TABLE IF NOT EXISTS transactions_y2026m06 PARTITION OF transactions_partitioned
    FOR VALUES FROM ('2026-06-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

-- Default fallback partition for future/unmapped transactions
CREATE TABLE IF NOT EXISTS transactions_default PARTITION OF transactions_partitioned DEFAULT;

-- ----------------------------------------------------------------------------
-- 3. Local Partition Indexes
-- Index definitions created on partitioned tables automatically propagate
-- to all existing and future child partitions.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_ptxn_payer_time
    ON transactions_partitioned (payer_vpa, initiated_at DESC);

CREATE INDEX IF NOT EXISTS idx_ptxn_payee_time
    ON transactions_partitioned (payee_vpa, initiated_at DESC);

CREATE INDEX IF NOT EXISTS idx_ptxn_payer_status_time
    ON transactions_partitioned (payer_vpa, status, initiated_at)
    INCLUDE (merchant_id, amount);

CREATE INDEX IF NOT EXISTS idx_ptxn_pending_time
    ON transactions_partitioned (initiated_at)
    WHERE status = 'PENDING';

CREATE INDEX IF NOT EXISTS idx_ptxn_merchant_time_success
    ON transactions_partitioned (merchant_id, initiated_at)
    INCLUDE (amount)
    WHERE status = 'SUCCESS';

