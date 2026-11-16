-- ============================================================================
-- Google Pay (UPI) Data Load Script: Phase 2 (CP1)
-- Database Engine: PostgreSQL 15+
-- Schema: gpay
-- 
-- Loads the 9 CSV export files in strict foreign-key dependency order using
-- the psql \copy command (client-side file stream), followed by ANALYZE.
-- ============================================================================

SET search_path TO gpay;

-- 1. Master Reference: cities (No incoming foreign keys)
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)

-- 2. Consumer Master: users (References cities)
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true)

-- 3. Banking Data: bank_accounts (References users)
\copy bank_accounts FROM 'seed_data/bank_accounts.csv' WITH (FORMAT csv, HEADER true)

-- 4. Handles: vpas (References users, bank_accounts)
\copy vpas FROM 'seed_data/vpas.csv' WITH (FORMAT csv, HEADER true)

-- 5. Business Master: merchants (References cities)
\copy merchants FROM 'seed_data/merchants.csv' WITH (FORMAT csv, HEADER true)

-- 6. Core Ledger: transactions (References vpas, merchants)
\copy transactions FROM 'seed_data/transactions.csv' WITH (FORMAT csv, HEADER true)

-- 7. Gamification: rewards (References users, transactions)
\copy rewards FROM 'seed_data/rewards.csv' WITH (FORMAT csv, HEADER true)

-- 8. Recurring Bills: bill_payments (References users)
\copy bill_payments FROM 'seed_data/bill_payments.csv' WITH (FORMAT csv, HEADER true)

-- 9. Disputes Desk: disputes (References transactions, users)
\copy disputes FROM 'seed_data/disputes.csv' WITH (FORMAT csv, HEADER true)

-- Update PostgreSQL query planner statistics across the gpay schema
ANALYZE;
