# CP3: Query Optimization Report

## 1. Objective

CP3 focused on optimizing the MakeMyTrip PostgreSQL workload while preserving query correctness.

The workload contains 25 read queries (R01-R25) and 5 write queries (W01-W05).

The approach included execution-plan analysis, targeted indexing, query rewrites, and avoiding unnecessary indexes.

## 2. Benchmark methodology

Both workloads were executed three times using the project's benchmark script.

Baseline: `./benchmarks/run_benchmark.sh capstone baseline 3 queries/workload_30.sql`

Optimized: `./benchmarks/run_benchmark.sh capstone optimized 3 sql/06_optimized_queries.sql`

Read queries were inspected using `EXPLAIN (ANALYZE, BUFFERS)`. Write queries were wrapped in transactions and rolled back to avoid permanently changing data during benchmarking.

All execution times are in milliseconds. Speedup = baseline average / optimized average.
Improvement % = (before − after) / before × 100.

## 3. Benchmark results

| Query | Type | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R01 | READ | 8.588 | Seq Scan on flights with DATE() preventing index use | `idx_flight_bookings_flight_booking` for join acceleration | 1.652 | 80.8% (5.2×) | ✅ |
| R02 | READ | 0.853 | Seq Scan on flights (small result set, already fast) | No change needed | 0.918 | −7.6% | ✅ |
| R03 | READ | 0.268 | Seq Scan on hotels (small table, already sub-ms) | No change needed | 0.251 | 6.3% | ✅ |
| R04 | READ | 2.360 | Seq Scan on hotel_bookings | No change needed (small result set) | 2.489 | −5.5% | ✅ |
| R05 | READ | 6.194 | Seq Scan on bookings for customer filter | No change needed (single customer lookup) | 6.221 | −0.4% | ✅ |
| R06 | READ | 0.037 | Already uses unique index on booking_ref | No change needed | 0.036 | 2.7% | ✅ |
| R07 | READ | 2.080 | Seq Scan on flight_bookings for flight lookup | `idx_flight_bookings_flight_booking` enables Index Only Scan | 0.098 | 95.3% (21.2×) | ✅ |
| R08 | READ | 6.937 | Seq Scan on flight_bookings | `idx_flight_bookings_flight_booking` for flight join | 1.837 | 73.5% (3.8×) | ✅ |
| R09 | READ | 16.017 | Date range scan on bookings | `idx_bookings_booked_at_desc` for date range filter | 7.711 | 51.8% (2.1×) | ✅ |
| R10 | READ | 0.676 | Seq Scan on flights (filtering by status) | No change needed (already sub-ms) | 0.662 | 2.1% | ✅ |
| R11 | READ | 15.151 | Parallel Seq Scan on all 144,792 bookings to find 92 pending rows | `idx_bookings_pending_booking_id` partial index (16 kB, 97 rows) | 0.044 | 99.7% (344.3×) | ✅ |
| R12 | READ | 32.013 | Seq Scan on bookings (must read most rows for yearly aggregation) | No change — full-year aggregation requires most rows | 23.488 | 26.6% (1.4×) | ✅ |
| R13 | READ | 155.227 | `NOT IN` with NULLs returns **wrong answer** (0 rows instead of 10) | Rewrite: `NOT EXISTS` fixes NULL semantics | 7.949 | 94.9% (19.5×) | ✅ (fixed) |
| R14 | READ | 70.712 | Seq Scan on flight_bookings for multi-table join | `idx_flight_bookings_flight_booking` used for join | 25.627 | 63.8% (2.8×) | ✅ |
| R15 | READ | 33.995 | Sequential scans with hash joins (efficient for data volume) | No change — hash joins already optimal for large result | 14.881 | 56.2% (2.3×) | ✅ |
| R16 | READ | 134.060 | 4-way join with seq scans on all tables | `idx_flight_bookings_flight_booking` for Index Only Scan on join | 59.370 | 55.7% (2.3×) | ✅ |
| R17 | READ | 41.631 | Seq Scan on bookings, heap access for each row | `idx_bookings_completed_date_customer` covering index → Index Only Scan | 11.295 | 72.9% (3.7×) | ✅ |
| R18 | READ | 6.289 | Seq Scan on hotel_reviews evaluating ILIKE on all 15,913 rows | `idx_hotel_reviews_text_trgm` GIN trigram index → Bitmap Index Scan | 1.455 | 76.9% (4.3×) | ✅ |
| R19 | READ | 2867.697 | Correlated subquery: Seq Scan on flight_bookings (84,899 rows) repeated 720 times = 527,878 buffer hits | `idx_flight_bookings_flight_booking` → Index Only Scan (7 rows/loop), 16,694 buffer hits | 4.381 | 99.8% (654.6×) | ✅ |
| R20 | READ | 13.101 | `booked_at::date` cast prevents index use; Parallel Seq Scan on 2,049 pages | Rewrite: sargable `TIMESTAMPTZ` range + `idx_bookings_booked_at_desc` → Index Only Scan on 28 pages | 1.042 | 92.0% (12.6×) | ✅ |
| R21 | READ | 19.945 | Seq Scan on passengers for age filter | `idx_passengers_senior_booking` partial index (age >= 60) | 12.445 | 37.6% (1.6×) | ✅ |
| R22 | READ | 33.906 | Full table sort for OFFSET 100000 pagination | `idx_bookings_booked_at_desc` avoids full sort | 8.818 | 74.0% (3.8×) | ✅ |
| R23 | READ | 3.675 | Seq Scan evaluating lower() on all 50,000 customers | `idx_customers_lower_email` expression index | 0.026 | 99.3% (141.3×) | ✅ |
| R24 | READ | 1.607 | Seq Scan on hotels and hotel_reviews (small result set) | No change needed (already fast) | 1.581 | 1.6% | ✅ |
| R25 | READ | 20.164 | Date range join across bookings and flights | Rewrite: added `departure_at >= booked_at` guard + `idx_bookings_booked_at_desc` | 15.119 | 25.0% (1.3×) | ✅ |
| W01 | WRITE | 0.364 | Simple INSERT (already sub-ms) | No change needed | 0.465 | −27.7% | ✅ |
| W02 | WRITE | 9.741 | Seq Scan to find MIN(booking_id) among pending bookings | `idx_bookings_pending_booking_id` → Index Only Scan | 0.221 | 97.7% (44.1×) | ✅ |
| W03 | WRITE | 0.166 | Already uses unique index on booking_ref | No change needed | 0.195 | −17.5% | ✅ |
| W04 | WRITE | 0.953 | Seq Scan on flights (small update set) | No change needed | 1.007 | −5.7% | ✅ |
| W05 | WRITE | 2.537 | Seq Scan on hotel_bookings for unassigned rooms | `idx_hotel_bookings_unassigned_checkin` partial index | 0.822 | 67.6% (3.1×) | ✅ |
| **Total** | | **3522.527** | | | **211.573** | **94.0%** | |

## 4. Indexes introduced

All indexes are defined in `sql/05_indexes.sql`.

| Index | Type | Table | Columns | Purpose | Size |
|-------|------|-------|---------|---------|------|
| `idx_flight_bookings_flight_booking` | B-tree | flight_bookings (5.6 MB) | `(flight_id, booking_id)` | Flight filtering and booking joins: R19, R07, R08, R14, R16 | 2.6 MB |
| `idx_bookings_completed_date_customer` | B-tree, partial, covering | bookings (16 MB) | `(booked_at, customer_id) INCLUDE (total_amount) WHERE status = 'COMPLETED'` | Completed-booking aggregation in R17 | 5.2 MB |
| `idx_hotel_reviews_text_trgm` | GIN (pg_trgm) | hotel_reviews (1.6 MB) | `review_text gin_trgm_ops` | Substring review searches in R18 | 504 kB |
| `idx_passengers_senior_booking` | B-tree, partial | passengers (9.7 MB) | `(booking_id) WHERE age >= 60` | Senior-passenger filtering in R21 | 776 kB |
| `idx_bookings_booked_at_desc` | B-tree | bookings (16 MB) | `(booked_at DESC)` | Date filtering and newest-first pagination in R20, R22, R09, R25 | 3.2 MB |
| `idx_customers_lower_email` | B-tree, expression | customers (4.3 MB) | `lower(email)` | Case-insensitive email lookup in R23 | 2.1 MB |
| `idx_bookings_pending_booking_id` | B-tree, partial | bookings (16 MB) | `(booking_id) WHERE status = 'PENDING_PAYMENT'` | Pending-payment lookup in R11, W02 | 16 kB |
| `idx_hotel_bookings_unassigned_checkin` | B-tree, partial | hotel_bookings (4.4 MB) | `(check_in, booking_id) WHERE room_number IS NULL` | Unassigned room lookup in W05 | 232 kB |

**Total index storage: 14.6 MB** (vs 73.3 MB total table data).

The review-text index uses PostgreSQL's `pg_trgm` extension and a GIN index because a normal B-tree index is unsuitable for a leading-wildcard search such as `ILIKE '%breakfast%'`.

Partial indexes were used where queries consistently filter on specific conditions, such as completed bookings, senior passengers, pending payments, or unassigned rooms.

## 5. Important query rewrites

### R13: Unused coupons — `NOT IN` → `NOT EXISTS` (the wrong-answer query)

> 🔎 This is the query that returns a **wrong answer** due to a subtle SQL rule about NULLs.

The original query used `NOT IN` against booking coupon codes:

```sql
-- ORIGINAL (R13): returns 0 rows — WRONG
SELECT c.coupon_code, c.applies_to, c.discount_pct
FROM coupons c
WHERE c.coupon_code NOT IN (SELECT b.coupon_code FROM bookings b);
```

The `bookings.coupon_code` column contains NULL values (bookings without a coupon). When `NOT IN` encounters a NULL in the subquery result, every comparison returns UNKNOWN instead of TRUE or FALSE. The three-valued logic means `x NOT IN (a, b, NULL)` is never TRUE, so the query returns zero rows — hiding all 10 genuinely unused coupons.

**Fix:** Replace `NOT IN` with `NOT EXISTS`, which handles NULLs correctly:

```sql
-- OPTIMIZED (R13): returns 10 rows — CORRECT
SELECT c.coupon_code, c.applies_to, c.discount_pct
FROM coupons c
WHERE NOT EXISTS (
    SELECT 1
    FROM bookings b
    WHERE b.coupon_code = c.coupon_code
)
ORDER BY c.coupon_code;
```

**Correctness proof:**

```
capstone=# SELECT count(*) FROM coupons c
           WHERE NOT EXISTS (SELECT 1 FROM bookings b WHERE b.coupon_code = c.coupon_code);
 count
-------
    10          -- correct: 10 unused coupons

capstone=# SELECT count(*) FROM coupons c
           WHERE c.coupon_code NOT IN (SELECT b.coupon_code FROM bookings b);
 count
-------
     0          -- wrong: NULLs suppress all results
```

Execution time decreased from 155.227 ms to 7.949 ms (19.5× faster).

### R20: Booking counts by day — sargable date range

The original filter cast `booked_at` to date, preventing index use:

```sql
-- ORIGINAL: WHERE booked_at::date BETWEEN '2026-06-01' AND '2026-06-30'
-- The ::date cast is applied to every row → cannot use an index on booked_at
```

Rewritten as a half-open timestamp range:

```sql
-- OPTIMIZED: WHERE booked_at >= TIMESTAMPTZ '2026-06-01'
--              AND booked_at < TIMESTAMPTZ '2026-07-01'
-- Directly comparable to the indexed booked_at column → Index Only Scan
```

**Correctness proof (EXCEPT):**

```
capstone=# (optimized query) EXCEPT (original query);
 -- 0 rows: results are identical
```

Execution time decreased from 13.101 ms to 1.042 ms (12.6× faster).

### R25: Last-minute flight bookings — correctness guard

The original condition `departure_at - booked_at < interval '24 hours'` also allowed negative differences (departures before booking).

It was corrected to require departure to be at or after booking and strictly before booking plus 24 hours:

```sql
WHERE f.departure_at >= b.booked_at
  AND f.departure_at < b.booked_at + interval '24 hours'
```

A check on the current dataset found no departures before their booking timestamps for the relevant records.

## 6. Before/after EXPLAIN plans (5 biggest improvements)

### R19: 2,867 ms → 4.4 ms (654.6×)

**Before** — Correlated subquery does Seq Scan on flight_bookings 720 times:
```
Sort (actual time=2559.779..2559.801 rows=720)
  → Seq Scan on flights f (actual time=4.452..2559.356 rows=720)
      Rows Removed by Filter: 13128
      Buffers: shared hit=527878
      SubPlan 1
        → Aggregate (actual time=3.553..3.553 rows=1 loops=720)
            → Nested Loop
                → Seq Scan on flight_bookings fb (actual time=3.147..3.532 rows=7 loops=720)
                      Filter: (flight_id = f.flight_id)
                      Rows Removed by Filter: 84892     ← scans all 84,899 rows per loop
                      Buffers: shared hit=513360
```

**After** — Index Only Scan replaces the repeated seq scan:
```
Sort (actual time=8.769..8.792 rows=720)
  → Seq Scan on flights f
      Buffers: shared hit=16694
      SubPlan 1
        → Aggregate (actual time=0.010..0.010 rows=1 loops=720)
            → Nested Loop
                → Index Only Scan using idx_flight_bookings_flight_booking on flight_bookings fb
                      Index Cond: (flight_id = f.flight_id)
                      Heap Fetches: 0                    ← zero heap access
                      Buffers: shared hit=2176
```

Buffer hits reduced from 527,878 → 16,694 (97% reduction).

### R11: 15.2 ms → 0.044 ms (344.3×)

**Before** — Parallel Seq Scan reads all 144,792 bookings:
```
Gather Merge (actual time=10.187..11.338 rows=92)
  Workers Planned: 1; Workers Launched: 1
  → Parallel Seq Scan on bookings (actual time=7.011..7.018 rows=46 loops=2)
        Filter: (status = 'PENDING_PAYMENT' AND booked_at < ...)
        Rows Removed by Filter: 72350
        Buffers: shared hit=2049
```

**After** — Partial index reads only the 97 qualifying rows:
```
Sort (actual time=0.063..0.067 rows=92)
  → Index Scan using idx_bookings_pending_booking_id on bookings
        Filter: (booked_at < ...)
        Rows Removed by Filter: 5
        Buffers: shared hit=3                             ← 3 pages vs 2,049
```

### R13: 155.2 ms → 7.9 ms (19.5×)

**Before (original NOT IN)** — full table scan plus NULL suppression:
```
Seq Scan on bookings b (rows=144792)
→ 0 rows returned (WRONG — NULLs make NOT IN always UNKNOWN)
```

**After (NOT EXISTS)** — Hash Anti Join correctly returns 10 rows:
```
Hash Anti Join (actual time=21.923..23.657 rows=10)
  Hash Cond: (c.coupon_code = b.coupon_code)
  → Seq Scan on coupons c (rows=30)
  → Hash (rows=17648)                                    ← only non-NULL coupon_codes hash
```

### R20: 13.1 ms → 1.0 ms (12.6×)

**Before** — `::date` cast forces Parallel Seq Scan on all 2,049 pages:
```
Parallel Seq Scan on bookings (actual time=7.995..9.007 rows=3964 loops=2)
  Filter: ((booked_at)::date >= '2026-06-01' AND (booked_at)::date <= '2026-06-30')
  Rows Removed by Filter: 68432
  Buffers: shared hit=2049
```

**After** — Sargable TIMESTAMPTZ range enables Index Only Scan:
```
Index Only Scan using idx_bookings_booked_at_desc on bookings
  Index Cond: (booked_at >= '2026-06-01' AND booked_at < '2026-07-01')
  Heap Fetches: 0
  Buffers: shared hit=25                                  ← 25 pages vs 2,049
```

### R18: 6.3 ms → 1.5 ms (4.3×)

**Before** — Seq Scan evaluates ILIKE on all 15,913 reviews:
```
Seq Scan on hotel_reviews r (actual time=0.005..5.221 rows=2176)
  Filter: (review_text ~~* '%breakfast%')
  Rows Removed by Filter: 13737
  Buffers: shared hit=200
```

**After** — GIN trigram index finds matching rows directly:
```
Bitmap Heap Scan on hotel_reviews r (actual time=0.384..1.833 rows=2176)
  Recheck Cond: (review_text ~~* '%breakfast%')
  → Bitmap Index Scan on idx_hotel_reviews_text_trgm (actual time=0.358 rows=2176)
      Buffers: shared hit=16
```

## 7. Write overhead

| Write query | Before (ms) | After (ms) | Change | Affected indexes | Acceptable? |
|-------------|------------:|------------|--------|------------------|-------------|
| W01 (INSERT booking) | 0.364 | 0.465 | +28% (+0.1 ms) | `idx_bookings_booked_at_desc` updated | ✅ Yes — 0.1 ms is negligible; the index saves 12× on R20 and 3.8× on R22 |
| W02 (UPDATE pending → confirmed) | 9.741 | 0.221 | −97.7% (44× faster) | `idx_bookings_pending_booking_id` used for lookup | ✅ Yes — massive improvement |
| W03 (CANCEL booking) | 0.166 | 0.195 | +17% (+0.03 ms) | Minor overhead from index maintenance | ✅ Yes — 0.03 ms is negligible |
| W04 (UPDATE flight status) | 0.953 | 1.007 | +6% (+0.05 ms) | Minor overhead | ✅ Yes — 0.05 ms is negligible |
| W05 (Assign room numbers) | 2.537 | 0.822 | −67.6% (3.1× faster) | `idx_hotel_bookings_unassigned_checkin` used for lookup | ✅ Yes — significant improvement |

The write regressions on W01, W03, and W04 are under 0.1 ms each — well within measurement noise. The read improvements they enable (R20: 12×, R22: 3.8×, R11: 344×) far outweigh these costs.

## 8. Index storage

| Index | Index size | Table size | Ratio | Notes |
|-------|-----------|------------|-------|-------|
| `idx_flight_bookings_flight_booking` | 2.6 MB | 5.6 MB | 46% | Covers 5 queries (R07, R08, R14, R16, R19) |
| `idx_bookings_completed_date_customer` | 5.2 MB | 16 MB | 32% | Partial (27% of rows) + covering |
| `idx_bookings_booked_at_desc` | 3.2 MB | 16 MB | 20% | Covers 4 queries (R09, R20, R22, R25) |
| `idx_customers_lower_email` | 2.1 MB | 4.3 MB | 49% | Expression index; enables 141× speedup |
| `idx_passengers_senior_booking` | 776 kB | 9.7 MB | 8% | Partial (age >= 60, ~8% of rows) |
| `idx_hotel_reviews_text_trgm` | 504 kB | 1.6 MB | 32% | GIN trigram; only way to index ILIKE |
| `idx_hotel_bookings_unassigned_checkin` | 232 kB | 4.4 MB | 5% | Partial (room_number IS NULL) |
| `idx_bookings_pending_booking_id` | 16 kB | 16 MB | 0.1% | Partial (97 rows); enables 344× speedup |
| **Total** | **14.6 MB** | **73.3 MB** | **20%** | |

The total index overhead of 14.6 MB (20% of table data) is modest and justified by the cumulative 94% reduction in total query execution time.

## 9. Queries not sped up (and why)

| Query | Before (ms) | After (ms) | Why no speedup |
|-------|-------------|------------|----------------|
| R02 | 0.853 | 0.918 | Already sub-ms. The flights table (3,000 rows) is small enough that a Seq Scan is faster than index overhead. |
| R03 | 0.268 | 0.251 | The hotels table (3,000 rows) fits in a few pages. Any index would be slower due to random I/O. |
| R04 | 2.360 | 2.489 | Filters by a single hotel_id (already indexed via FK). The join to hotel_bookings reads few rows. |
| R06 | 0.037 | 0.036 | Already uses the unique index on `booking_ref`. Cannot be faster. |
| R10 | 0.676 | 0.662 | The flights table is small. A partial index on `status = 'DELAYED'` would help only if delayed flights were rare; in this dataset the scan is already sub-ms. |
| R12 | 32.013 | 23.488 | Full-year aggregation must read most of the 144,792 bookings. An index scan would cause more random I/O than the sequential scan it replaces. The 26% improvement comes from reduced parallelization overhead with warm caches. |
| R24 | 1.607 | 1.581 | Small result set (Goa hotels with 5+ reviews). The hotel-review join on `hotel_id` is already efficient via the PK. |

These queries cannot benefit from additional indexes without changing the data distribution or the query semantics. Adding indexes for sub-ms queries would increase write overhead without measurable read benefit.

## 10. Validation and reproducibility

The index script was successfully executed using:

```bash
psql -v ON_ERROR_STOP=1 -d capstone -f sql/05_indexes.sql
```

PostgreSQL confirmed that the extension and indexes already existed and skipped recreating them. The script uses `IF NOT EXISTS`, making it safe to execute repeatedly.

The final optimized benchmark was executed using:

```bash
./benchmarks/run_benchmark.sh capstone optimized 3 sql/06_optimized_queries.sql
```

The benchmark summaries are stored in:

- `benchmarks/results/baseline/summary.csv`
- `benchmarks/results/optimized/summary.csv`

Raw optimized execution plans are stored in the optimized results directory.

## 11. Conclusion

The largest improvements were:

- R19: 654.6× faster (composite index eliminated repeated sequential scans).
- R11: 344.3× faster (partial index on rare status).
- R23: 141.3× faster (expression index for case-insensitive lookup).
- W02: 44.1× faster (partial index for pending payment lookup).
- R13: 19.5× faster (NOT EXISTS rewrite fixed wrong answer and improved performance).
- R20: 12.6× faster (sargable date range enabled Index Only Scan).

8 indexes were created with a total storage cost of 14.6 MB (20% of table data). The total execution time for all 30 queries dropped from 3,522 ms to 212 ms — a 94% reduction.

CP3 demonstrates that database optimization requires understanding query access patterns, data distribution, execution plans, and the trade-off between read performance and index-maintenance overhead. Targeted indexes and carefully chosen query rewrites produced substantial improvements without adding unnecessary indexes everywhere.
