# Baseline Timings Report

This document records the baseline performance metrics for the queries defined in the project. All timings were obtained using the `run_benchmark.sh baseline` script, which executes each query three times and records the average execution time.

## Methodology
- Each query was run with `EXPLAIN (ANALYZE, BUFFERS)` in PostgreSQL.
- The `run_benchmark.sh baseline` script records the `avg_ms` for each query in `benchmarks/results/baseline/summary.csv`.
- Write queries were wrapped in `BEGIN; ... ROLLBACK;` to avoid persisting changes.

## Summary Table
| Query ID | Description | Avg Execution Time (ms) |
|----------|-------------|--------------------------|
| Q1 | Get user by email | 0.050 |
| Q2 | List recent transactions for a merchant | 28.130 |
| Q3 | Insert new transaction | 0.633 |

*Replace `TBD` with the actual average times from the CSV after running the benchmark.*

## Observations
- Provide any noteworthy observations here after the benchmarks are completed.
