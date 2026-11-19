# CP3: Query Optimization Report

## 1. Objective

CP3 focused on optimizing the MakeMyTrip PostgreSQL workload while preserving query correctness.

The workload contains 25 read queries (R01-R25) and 5 write queries (W01-W05).

The approach included execution-plan analysis, targeted indexing, query rewrites, and avoiding unnecessary indexes.

## 2. Benchmark methodology

Both workloads were executed three times using the project's benchmark script.

Baseline: `./benchmarks/run_benchmark.sh makemytrip baseline 3 queries/workload_30.sql`

Optimized: `./benchmarks/run_benchmark.sh makemytrip optimized 3 sql/06_optimized_queries.sql`

Read queries were inspected using `EXPLAIN (ANALYZE, BUFFERS)`. Write queries were wrapped in transactions and rolled back to avoid permanently changing data during benchmarking.

All execution times are in milliseconds. Speedup = baseline average / optimized average.

## 3. Benchmark results

| Query | Type | Baseline (ms) | Optimized (ms) | Speedup |
|---|---|---:|---:|---:|
| R01 | READ | 8.588 | 1.652 | 5.20x |
| R02 | READ | 0.853 | 0.918 | 0.93x |
| R03 | READ | 0.268 | 0.251 | 1.07x |
| R04 | READ | 2.360 | 2.489 | 0.95x |
| R05 | READ | 6.194 | 6.221 | 1.00x |
| R06 | READ | 0.037 | 0.036 | 1.03x |
| R07 | READ | 2.080 | 0.098 | 21.22x |
| R08 | READ | 6.937 | 1.837 | 3.78x |
| R09 | READ | 16.017 | 7.711 | 2.08x |
| R10 | READ | 0.676 | 0.662 | 1.02x |
| R11 | READ | 15.151 | 0.044 | 344.34x |
| R12 | READ | 32.013 | 23.488 | 1.36x |
| R13 | READ | 155.227 | 7.949 | 19.53x |
| R14 | READ | 70.712 | 25.627 | 2.76x |
| R15 | READ | 33.995 | 14.881 | 2.28x |
| R16 | READ | 134.060 | 59.370 | 2.26x |
| R17 | READ | 41.631 | 11.295 | 3.69x |
| R18 | READ | 6.289 | 1.455 | 4.32x |
| R19 | READ | 2867.697 | 4.381 | 654.58x |
| R20 | READ | 13.101 | 1.042 | 12.57x |
| R21 | READ | 19.945 | 12.445 | 1.60x |
| R22 | READ | 33.906 | 8.818 | 3.85x |
| R23 | READ | 3.675 | 0.026 | 141.35x |
| R24 | READ | 1.607 | 1.581 | 1.02x |
| R25 | READ | 20.164 | 15.119 | 1.33x |
| W01 | WRITE | 0.364 | 0.465 | 0.78x |
| W02 | WRITE | 9.741 | 0.221 | 44.08x |
| W03 | WRITE | 0.166 | 0.195 | 0.85x |
| W04 | WRITE | 0.953 | 1.007 | 0.95x |
| W05 | WRITE | 2.537 | 0.822 | 3.09x |

Values below 1.0x indicate a small performance regression.

## 4. Indexes introduced

All indexes are defined in `sql/05_indexes.sql`.

| Index | Table | Purpose |
|---|---|---|
| `idx_flight_bookings_flight_booking` | flight_bookings | Flight filtering and booking joins, especially R19 |
| `idx_bookings_completed_date_customer` | bookings | Completed-booking aggregation in R17 |
| `idx_hotel_reviews_text_trgm` | hotel_reviews | Substring review searches in R18 |
| `idx_passengers_senior_booking` | passengers | Senior-passenger filtering in R21 |
| `idx_bookings_booked_at_desc` | bookings | Date filtering and newest-first pagination in R20 and R22 |
| `idx_customers_lower_email` | customers | Case-insensitive email lookup in R23 |
| `idx_bookings_pending_booking_id` | bookings | Oldest pending-payment lookup in W02 and R11 |
| `idx_hotel_bookings_unassigned_checkin` | hotel_bookings | Unassigned room lookup in W05 |

The review-text index uses PostgreSQL's `pg_trgm` extension and a GIN index because a normal B-tree index is unsuitable for a leading-wildcard search such as `ILIKE '%breakfast%'`.

Partial indexes were used where queries consistently filter on specific conditions, such as completed bookings, senior passengers, pending payments, or unassigned rooms.

## 5. Important query rewrites

### R13: Unused coupons

The original query used `NOT IN` against booking coupon codes. Since the bookings table contains NULL coupon codes, `NOT IN` could produce UNKNOWN comparisons and return incorrect results.

It was rewritten using `NOT EXISTS`, comparing coupon codes directly. This fixes the NULL-related correctness issue.

Execution time decreased from 155.227 ms to 7.949 ms.

### R20: Booking counts by day

The original filter applied a date cast to `booked_at`. It was rewritten as a half-open timestamp range:

- `booked_at >= TIMESTAMPTZ '2026-06-01'`
- `booked_at < TIMESTAMPTZ '2026-07-01'`

This allows the booking-date index to support the filter and includes all timestamps in June.

Execution time decreased from 13.101 ms to 1.042 ms.

### R25: Last-minute flight bookings

The original condition `departure_at - booked_at < interval '24 hours'` also allowed negative differences.

It was corrected to require departure to be at or after booking and strictly before booking plus 24 hours.

A check on the current dataset found no departures before their booking timestamps for the relevant records.

Execution time decreased from 20.164 ms to 15.119 ms.

## 6. Decisions not to add more indexes

Not every query needs another index.

- R14 and R16 benefit from the shared flight-booking composite index.
- R15 already uses sequential scans and hash joins efficiently for its data volume.
- R24 already has an efficient plan. Its hotel-review join uses `hotel_id`, so the trigram text index is not relevant.
- W01 is a small insert and does not justify another index.
- W03 already uses the unique index on `booking_ref`.
- W04 updates a small number of rows in a relatively small flights table, making a sequential scan reasonable.

Small regressions occurred in R02, R04, W01, W03, and W04. Their absolute execution times are low. Adding indexes indiscriminately would increase storage and write-maintenance costs without necessarily improving performance.

## 7. Validation and reproducibility

The index script was successfully executed using:

`psql -v ON_ERROR_STOP=1 -d makemytrip -f sql/05_indexes.sql`

PostgreSQL confirmed that the extension and indexes already existed and skipped recreating them. The script uses `IF NOT EXISTS`, making it safe to execute repeatedly.

The final optimized benchmark was executed using:

`./benchmarks/run_benchmark.sh makemytrip optimized 3 sql/06_optimized_queries.sql`

The benchmark summaries are stored in:

- `benchmarks/results/baseline/summary.csv`
- `benchmarks/results/optimized/summary.csv`

Raw optimized execution plans are stored in the optimized results directory.

## 8. Conclusion

The largest improvements were:

- R19: 654.58x faster.
- R11: 344.34x faster.
- R23: 141.35x faster.
- W02: 44.08x faster.
- R13: 19.53x faster.
- R20: 12.57x faster.

CP3 demonstrates that database optimization requires understanding query access patterns, data distribution, execution plans, and the trade-off between read performance and index-maintenance overhead. Targeted indexes and carefully chosen query rewrites produced substantial improvements without adding unnecessary indexes everywhere.
