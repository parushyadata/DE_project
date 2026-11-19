# CP3: Query Optimization Report

## 1. Summary

All 30 workload queries were benchmarked **before and after optimization on the same laptop, same PostgreSQL build and same freshly loaded seed data**, using `benchmarks/run_benchmark.sh` (3 runs each, average reported).

- Workload total: **1,657.758 ms → 217.772 ms (−86.9%, 7.6×)**. R19 alone accounts for 1,345 ms of the saving; without R19 the total goes 307.090 → 212.160 ms (−30.9%).
- **18 queries are measurably faster**: every optimized run is below every baseline run *and* the plan changed because of an index or rewrite.
- **12 queries show no attributable change**. 9 have overlapping run ranges; R12, R14 and R15 are slightly lower with an identical plan, so the difference is run-to-run variance, not an optimization.
- **R13 returned a wrong answer** (0 rows) because of `NOT IN` with NULLs; the rewrite returns the correct 10 rows.
- Every other query returns exactly the same output as the original (byte-identical result, md5 compared).

## 2. Changes in this revision

An earlier version of this report compared the CP2 baseline numbers (measured by three members on different laptops) with optimized numbers measured on a fourth setup. That mixes machine speed into the "improvement": for example R15 and R12 were reported 56% and 27% faster with **no change applied**, and on the same machine they are not measurably faster. This revision:

1. **Re-measures the baseline on the same machine as the optimized run** (`benchmarks/results/baseline_rerun/`). The CP2 deliverable in `benchmarks/results/baseline/` is unchanged; §12 shows both.
2. **R25 rewrite made exactly equivalent.** The previous rewrite added `departure_at >= booked_at`, which changes the query's meaning (a booking made after departure would drop out). It returned the same rows only because the seed data has no such booking. Now: `departure_at < booked_at + interval '24 hours'`, identical to the original condition.
3. **`sql/06_optimized_queries.sql` safety fix.** Its `ROLLBACK;` had been moved to directly after `BEGIN;`, so running the file with `psql -f` would have **committed** W01–W05. `ROLLBACK;` and the `-- @END` marker are back at the end.
4. **New index for W04** (`idx_flights_open_departure`), which also speeds up R08 and R10.
5. Corrected index comments (R21's partial index covers ~23% of passengers, not ~8%; there are 40,000 customers, not 50,000).

## 3. Method and environment

| Item | Value |
|---|---|
| PostgreSQL | 18.6 (conda-forge build), **default server settings**, throwaway local cluster |
| Machine | Apple M4, 16 GB (Sriharsha's laptop) |
| Data | `seed_data.zip` loaded with `sql/01_schema.sql` + `sql/02_load_data.sql` (ends with `ANALYZE`) into a fresh database |
| Baseline | `./benchmarks/run_benchmark.sh mmt baseline 3 queries/workload_30.sql` on the fresh database, PK/UNIQUE indexes only |
| Optimized | database rebuilt from scratch, then `sql/05_indexes.sql`, then `./benchmarks/run_benchmark.sh mmt optimized 3 sql/06_optimized_queries.sql` |
| Timing | `EXPLAIN (ANALYZE, BUFFERS)` `Execution Time`, 3 runs, average; writes inside `BEGIN … ROLLBACK` |

Both runs used the unmodified project script. No `VACUUM` was run in either (it is not in `05_indexes.sql`; see §9). The README's example uses 5 runs; CHECKPOINTS.md specifies 3, which is what both runs used.

**"Measurably faster"** in this report means all three optimized runs are below all three baseline runs *and* the plan changed. Raw plans of every run: `benchmarks/results/baseline_rerun/*.txt` and `benchmarks/results/optimized/*.txt`.

## 4. Results

Before = same-machine baseline. Improvement = (before − after) / before × 100. Positive = lower time; for "no measurable change" rows the sign only shows which way the averages moved.

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R01 | 5.110 | Seq Scan on all 84,899 `flight_bookings` rows to join the matching flights | `idx_flight_bookings_flight_booking (flight_id, booking_id)`: index lookups per flight | 1.095 | **78.6%** (4.7×) | ✅ identical |
| R02 | 0.737 | Seq Scan on `flights` (13,848 rows), already < 1 ms | None | 0.760 | no measurable change (-3.1%, runs overlap) | ✅ identical |
| R03 | 0.234 | Seq Scan on `hotels` (3,000 rows), already < 1 ms | None | 0.229 | no measurable change (+2.3%, runs overlap) | ✅ identical |
| R04 | 1.998 | Seq Scan on `hotel_bookings` for hotel 208 | None | 1.897 | no measurable change (+5.0%, runs overlap) | ✅ identical |
| R05 | 6.547 | Seq Scan on `bookings` for customer 1021 (no index on `customer_id`) | None | 6.027 | no measurable change (+7.9%, runs overlap) | ✅ identical |
| R06 | 0.026 | Already an Index Scan on the UNIQUE `booking_ref` index | None | 0.025 | no measurable change (+3.9%, runs overlap) | ✅ identical |
| R07 | 2.231 | Seq Scan on `flight_bookings` to find the 9 bookings of flight 13047 | `idx_flight_bookings_flight_booking` → Index Only Scan | 0.097 | **95.6%** (22.9×) | ✅ identical |
| R08 | 5.897 | Seq Scans on `flights` and `flight_bookings` | `idx_flights_open_departure` (partial, added for W04; `status = 'SCHEDULED'` is implied by its predicate) + `idx_flight_bookings_flight_booking` | 1.223 | **79.3%** (4.8×) | ✅ identical |
| R09 | 14.212 | Seq Scan on `bookings` for a June 2026 range | `idx_bookings_booked_at_desc` → Index Scan on the date range | 7.735 | **45.6%** (1.8×) | ✅ identical |
| R10 | 0.677 | Seq Scan on `flights` for `status = 'DELAYED'` + sort | `idx_flights_open_departure` → Index Scan, already in `departure_at` order | 0.062 | **90.8%** (10.9×) | ✅ identical |
| R11 | 4.805 | Parallel Seq Scan on 144,792 `bookings` for 92 pending rows | `idx_bookings_pending_booking_id` (partial, 97 rows) | 0.041 | **99.1%** (117.2×) | ✅ identical |
| R12 | 24.079 | Seq Scan on `bookings`; `EXTRACT(YEAR FROM booked_at)` is not sargable | None | 22.465 | 6.7% lower, same plan: not attributed | ✅ identical |
| R13 | 12.085 | `NOT IN` against a column with NULLs → returns **0 rows (wrong)** | Rewrite to `NOT EXISTS` (hash anti-join) → correct 10 rows | 7.988 | **33.9%** (1.5×) | ✅ fixed: 0 → 10 rows |
| R14 | 28.383 | Seq Scans + hash joins over most of 4 tables | None (plan unchanged) | 27.750 | 2.2% lower, same plan: not attributed | ✅ identical |
| R15 | 15.205 | Seq Scans + hash joins over `bookings`, `hotel_bookings`, `hotels` | None (plan unchanged) | 14.339 | 5.7% lower, same plan: not attributed | ✅ identical |
| R16 | 62.806 | Seq Scans on 5 tables; aggregates most rows | None (plan unchanged) | 62.177 | no measurable change (+1.0%, runs overlap) | ✅ identical |
| R17 | 16.668 | Seq Scan on `bookings` for completed 2026 bookings | Index Scan on `idx_bookings_booked_at_desc` (the covering partial index built for R17 is not chosen on a freshly loaded table; see §9) | 13.195 | **20.8%** (1.3×) | ✅ identical |
| R18 | 2.127 | Seq Scan on `hotel_reviews` evaluating `ILIKE '%breakfast%'` on every row | `idx_hotel_reviews_text_trgm` (GIN, `pg_trgm`) → Bitmap Index Scan | 1.009 | **52.6%** (2.1×) | ✅ identical |
| R19 | 1350.668 | Correlated subquery: Seq Scan on `flight_bookings` repeated 720 times (84,892 rows removed per loop) | `idx_flight_bookings_flight_booking` → Index Only Scan per loop | 5.612 | **99.6%** (240.7×) | ✅ identical |
| R20 | 7.157 | `booked_at::date BETWEEN …` cast prevents index use; Seq Scan | Rewrite to a half-open `timestamptz` range + `idx_bookings_booked_at_desc` → Index Only Scan | 1.323 | **81.5%** (5.4×) | ✅ identical |
| R21 | 19.694 | Seq Scan on all 163,380 `passengers` to filter `age >= 60` | `idx_passengers_senior_booking` (partial, 36,837 rows) → Index Only Scan; the flight_bookings/flights hash join remains | 15.213 | **22.8%** (1.3×) | ✅ identical |
| R22 | 36.843 | Seq Scan + top-N sort of all 144,792 `bookings` for `OFFSET 100000` | `idx_bookings_booked_at_desc` → Index Scan that stops after 100,025 entries | 8.903 | **75.8%** (4.1×) | ✅ identical |
| R23 | 4.045 | Seq Scan evaluating `lower(email)` on all 40,000 customers | `idx_customers_lower_email` (expression index) | 0.028 | **99.3%** (144.5×) | ✅ identical |
| R24 | 1.629 | Seq Scans on small inputs (15,913 reviews, 450 Goa hotels), ~1.6 ms | None (candidate indexes tested and rejected, §9) | 1.539 | no measurable change (+5.5%, runs overlap) | ✅ identical |
| R25 | 20.153 | Seq Scan on `bookings` for the 2026 filter; the 24-hour condition compares two tables, so it can only be a join filter | `idx_bookings_booked_at_desc` for `booked_at >= '2026-01-01'`; exact-equivalent rewrite of the 24-hour condition (no timing effect) | 15.529 | **22.9%** (1.3×) | ✅ identical |
| W01 | 0.349 | Single-row INSERT, no read part | None (new `bookings` indexes add maintenance cost) | 0.384 | no measurable change (-10.1%, runs overlap) | ✅ same rows affected |
| W02 | 9.781 | `min(booking_id)` over pending rows walks `bookings_pkey`, filtering out 144,695 rows | `idx_bookings_pending_booking_id` → Index Only Scan, 1 entry | 0.169 | **98.3%** (57.9×) | ✅ same rows affected |
| W03 | 0.155 | Already an Index Scan on the UNIQUE `booking_ref` index | None | 0.165 | no measurable change (-6.2%, runs overlap) | ✅ same rows affected |
| W04 | 0.945 | Seq Scan on `flights` to find 10 open flights before 1 July | `idx_flights_open_departure` (partial, 754 rows) → Index Scan | 0.174 | **81.6%** (5.4×) | ✅ same rows affected |
| W05 | 2.512 | Seq Scan on `hotel_bookings` for unassigned 1 July check-ins | `idx_hotel_bookings_unassigned_checkin` (partial) → Index Scan | 0.618 | **75.4%** (4.1×) | ✅ same rows affected |
| **Total** | **1657.758** | | | **217.772** | **86.9%** (7.6×) | |

## 5. Indexes (`sql/05_indexes.sql`)

| Index | Type | Definition | Measurably faster | Size |
|---|---|---|---|---:|
| `idx_flight_bookings_flight_booking` | B-tree, composite | `flight_bookings (flight_id, booking_id)` | R01, R07, R08, R19 | 2.6 MB |
| `idx_bookings_completed_date_customer` | B-tree, partial, covering | `bookings (booked_at, customer_id) INCLUDE (total_amount) WHERE status = 'COMPLETED'` | none in this run (see §9) | 5.0 MB |
| `idx_hotel_reviews_text_trgm` | GIN (`pg_trgm`) | `hotel_reviews USING gin (review_text gin_trgm_ops)` | R18 | 504 kB |
| `idx_passengers_senior_booking` | B-tree, partial | `passengers (booking_id) WHERE age >= 60` | R21 | 776 kB |
| `idx_bookings_booked_at_desc` | B-tree | `bookings (booked_at DESC)` | R09, R17, R20, R22, R25 | 3.1 MB |
| `idx_customers_lower_email` | B-tree, expression | `customers (lower(email))` | R23 | 2.0 MB |
| `idx_bookings_pending_booking_id` | B-tree, partial | `bookings (booking_id) WHERE status = 'PENDING_PAYMENT'` | R11, W02 | 16 kB |
| `idx_hotel_bookings_unassigned_checkin` | B-tree, partial | `hotel_bookings (check_in, booking_id) WHERE room_number IS NULL` | W05 | 232 kB |
| `idx_flights_open_departure` | B-tree, partial | `flights (departure_at) WHERE status IN ('SCHEDULED', 'DELAYED')` | W04, R08, R10 | 40 kB |

Total: **14 MB of new indexes** against 44 MB of table data.

Why these shapes:
- **Equality column first, then the join/range column.** `flight_bookings (flight_id, booking_id)` answers "bookings of flight X" and hands `booking_id` to the next join without reading the table.
- **Partial indexes for rare states.** Pending payments are 97 of 144,792 bookings; open flights are 754 of 13,848. These indexes are tiny, and rows leave them when their status changes (W02 and W04 move rows out).
- **Expression index for R23**, because the existing UNIQUE index on `email` cannot answer `lower(email) = …`.
- **GIN trigram index for R18**: a B-tree cannot serve a leading-wildcard `ILIKE`.

## 6. Query rewrites (`sql/06_optimized_queries.sql`)

Only three queries were rewritten; the other 27 are copied unchanged from `queries/workload_30.sql`.

### R13: `NOT IN` → `NOT EXISTS` (the wrong-answer query)

```sql
-- original
WHERE c.coupon_code NOT IN (SELECT b.coupon_code FROM bookings b);
-- rewrite
WHERE NOT EXISTS (SELECT 1 FROM bookings b WHERE b.coupon_code = c.coupon_code)
ORDER BY c.coupon_code;
```

127,144 bookings have `coupon_code IS NULL`. `x NOT IN (…, NULL)` is never TRUE: for a coupon that was never used, every comparison is FALSE except the comparison with NULL, which is UNKNOWN, so the whole predicate is UNKNOWN and the row is filtered out. The original therefore returns **0 rows**. `NOT EXISTS` only asks whether a matching row exists, so NULLs cannot match and the query returns the **10 coupons** that were never used. This was cross-checked with `NOT IN (SELECT coupon_code FROM bookings WHERE coupon_code IS NOT NULL)`, which also gives 10. The rewrite also runs as a hash anti-join: 12.085 → 7.988 ms.

### R20: sargable date range

`booked_at::date BETWEEN '2026-06-01' AND '2026-06-30'` casts every row, so no index on `booked_at` can be used. The rewrite `booked_at >= TIMESTAMPTZ '2026-06-01' AND booked_at < TIMESTAMPTZ '2026-07-01'` selects the same rows (identical output) and runs as an Index Only Scan on `idx_bookings_booked_at_desc`: 7.157 → 1.323 ms.

### R25: exact-equivalent form of the 24-hour condition

`f.departure_at - b.booked_at < interval '24 hours'` was rewritten to `f.departure_at < b.booked_at + interval '24 hours'`, which is the same condition. Because it compares columns from two tables, no index can apply it and the plan keeps it as a hash-join filter. A side test showed no timing difference from the rewrite on its own (15.1 → 14.9 ms, within noise). The measured R25 improvement (20.153 → 15.529 ms) comes from `idx_bookings_booked_at_desc` serving `booked_at >= '2026-01-01'`.

## 7. Proof that results are unchanged

On the optimized database, every original query (from `queries/workload_30.sql`) and its optimized version (from `sql/06_optimized_queries.sql`) were run and their full output compared:

- **Reads:** the complete result, in the order returned, was compared byte for byte. **24 of the 25 reads are identical**, including order, for example R25: 2,935 rows; R19: 720; R17: 3,072; R22: the same 25 rows. **R13 differs intentionally** (0 → 10 rows, §6).
- **Order:** where a query has `ORDER BY`, identical output means identical order. R22's page is deterministic because `booked_at` is unique (144,792 distinct values).
- **R25 both directions:** `EXCEPT ALL` original vs rewrite = 0 rows, and rewrite vs original = 0 rows.
- **Writes:** W01–W05 are unchanged SQL; each affects the same number of rows (1, 1, 1, 10, 89) and is rolled back.

## 8. Before/after plans: 5 biggest improvements

Excerpts from run 3 of each benchmark (costs and buffer lines trimmed).

### R19: 1,350.668 → 5.612 ms (240.7×)

```
-- before
->  Seq Scan on flights f (actual time=2.827..1353.166 rows=720 loops=1)
      SubPlan 1
        ->  Seq Scan on flight_bookings fb (actual time=1.660..1.868 rows=6.64 loops=720)
              Filter: (flight_id = f.flight_id)
              Rows Removed by Filter: 84892
Execution Time: 1353.385 ms
-- after
->  Seq Scan on flights f (actual time=0.536..5.506 rows=720 loops=1)
      SubPlan 1
        ->  Index Only Scan using idx_flight_bookings_flight_booking on flight_bookings fb (actual time=0.001..0.001 rows=6.64 loops=720)
              Index Cond: (flight_id = f.flight_id)
Execution Time: 5.681 ms
```
The correlated subquery runs once per June flight (720 times). Before, each run scanned all 84,899 flight bookings; after, each run is a single index lookup.

### R23: 4.045 → 0.028 ms (144.5×)

```
-- before
Seq Scan on customers (actual time=0.098..4.068 rows=1 loops=1)
  Filter: (lower(email) = 'siddharth.sharma1021@rediffmail.com'::text)
  Rows Removed by Filter: 39999
-- after
Bitmap Heap Scan on customers (actual time=0.007..0.007 rows=1 loops=1)
  ->  Bitmap Index Scan on idx_customers_lower_email
        Index Cond: (lower(email) = 'siddharth.sharma1021@rediffmail.com'::text)
```

### R11: 4.805 → 0.041 ms (117.2×)

```
-- before
Gather Merge  ->  Parallel Seq Scan on bookings (rows=46 loops=2)
      Filter: ((status = 'PENDING_PAYMENT') AND (booked_at < ...))
      Rows Removed by Filter: 72350
-- after
Index Scan using idx_bookings_pending_booking_id on bookings (rows=92 loops=1)
  Filter: (booked_at < ...)   Rows Removed by Filter: 5
```

### W02: 9.781 → 0.169 ms (57.9×)

```
-- before: min(booking_id) WHERE status = 'PENDING_PAYMENT'
->  Index Scan using bookings_pkey on bookings bookings_1 (actual time=9.624..9.624 rows=1)
      Filter: (status = 'PENDING_PAYMENT'::text)
      Rows Removed by Filter: 144695
-- after
->  Index Only Scan using idx_bookings_pending_booking_id on bookings bookings_1 (actual time=0.011..0.011 rows=1)
```
Before, PostgreSQL walked the primary key in order until it reached the first pending booking, near the end of the table. The partial index contains only pending bookings, so its first entry is the answer.

### R07: 2.231 → 0.097 ms (22.9×)

```
-- before
->  Seq Scan on flight_bookings fb (actual time=1.822..2.049 rows=9 loops=1)
      Filter: (flight_id = 13047)
      Rows Removed by Filter: 84890
-- after
->  Index Only Scan using idx_flight_bookings_flight_booking on flight_bookings fb (actual time=0.008..0.017 rows=9 loops=1)
      Index Cond: (flight_id = 13047)
```

## 9. Options tested and rejected

These were measured in a side test (median of 7 runs, same machine) and left out because the gain did not justify the extra index or the change.

| Query | Option | Result | Decision |
|---|---|---|---|
| R22 | Replace `idx_bookings_booked_at_desc` with a covering `(booked_at DESC) INCLUDE (booking_id, booking_ref, booking_type, status, total_amount)` | R22 8.8 → 5.9 ms, but R20 4.4 → 6.6 ms; index 10 MB vs 3.1 MB, on the most-written table | Rejected: net ≈ 0.7 ms for +7 MB and more write cost |
| R22 | Keyset pagination | Needs the last `booked_at` of page 4,000 as input; the query as specified only has the offset | Not applicable without changing the query's input |
| R24 | `hotel_reviews (hotel_id) INCLUDE (rating)` + `hotels (city_name)` | 1.45 → 1.35 ms | Rejected: 0.1 ms for two indexes |
| R21 | Covering `flights (departure_at) INCLUDE (flight_id, origin, destination)` | 12.7 → 12.2 ms | Rejected: within noise |
| R21 | Pre-aggregate seniors per booking before joining | 12.6 → 15.1 ms (slower) | Rejected |
| all | `VACUUM ANALYZE` after loading (sets the visibility map) | No measurable change for R21/R22/R24 | Not added |

**R17 note:** `idx_bookings_completed_date_customer` was designed to give R17 an Index Only Scan. On a freshly loaded table the visibility map is not set, so an index-only scan would still visit the heap. The planner therefore picks the smaller `idx_bookings_booked_at_desc`, and R17 improves 16.668 → 13.195 ms through that index instead. The covering index is kept, since it is expected to win once autovacuum has set the visibility map on `bookings`. That was not measured here, and this run shows no benefit from it.

## 10. Write overhead

- **W01** (INSERT into `bookings`): 0.349 → 0.384 ms. The runs overlap, so this is not a measurable slowdown, but it is the expected direction: `bookings` now has three more indexes, and a new pending row is added to two of them (`idx_bookings_booked_at_desc`, `idx_bookings_pending_booking_id`).
- **W03**: 0.155 → 0.165 ms, overlapping runs; no measurable change.
- **W02, W04, W05** got much faster. Their cost was finding the rows, and the partial indexes make that cheap. Index maintenance on the 1–89 changed rows is included in the "after" times.

## 11. Queries not sped up, and why

- **R02, R03, R06, W03**: already sub-millisecond, or already using a unique index.
- **R04, R05**: a few ms of seq scan on one table. An index on `bookings(customer_id)` (R05) or `hotel_bookings(hotel_id, …)` (R04) might help, but was not tested. Those queries belong to other members and are unchanged.
- **R12, R14, R15, R16**: reports that aggregate most of a table, where hash joins over seq scans are the right plan. R12 could be made sargable (`booked_at >= '2026-01-01' AND booked_at < '2027-01-01'` instead of `EXTRACT(YEAR …)`), but it still reads most rows. Their small measured differences come with identical plans and are not claimed as improvements.
- **R24**: only 1.6 ms on small inputs; candidate indexes gave about 0.1 ms (§9).

## 12. CP2 baseline vs same-machine baseline

`docs/03_baseline_timings.md` (CP2) reports the baseline from three different laptops. The same queries re-run on the machine used for this report:

| Query | CP2 avg (ms) | Same-machine baseline (ms) |
|---|---:|---:|
| R01 | 8.588 | 5.110 |
| R02 | 0.853 | 0.737 |
| R03 | 0.268 | 0.234 |
| R04 | 2.360 | 1.998 |
| R05 | 6.194 | 6.547 |
| R06 | 0.037 | 0.026 |
| R07 | 2.080 | 2.231 |
| R08 | 6.937 | 5.897 |
| R09 | 16.017 | 14.212 |
| R10 | 0.676 | 0.677 |
| R11 | 15.151 | 4.805 |
| R12 | 32.013 | 24.079 |
| R13 | 155.227 | 12.085 |
| R14 | 70.712 | 28.383 |
| R15 | 33.995 | 15.205 |
| R16 | 134.060 | 62.806 |
| R17 | 41.631 | 16.668 |
| R18 | 6.289 | 2.127 |
| R19 | 2867.697 | 1350.668 |
| R20 | 13.101 | 7.157 |
| R21 | 19.945 | 19.694 |
| R22 | 33.906 | 36.843 |
| R23 | 3.675 | 4.045 |
| R24 | 1.607 | 1.629 |
| R25 | 20.164 | 20.153 |
| W01 | 0.364 | 0.349 |
| W02 | 9.741 | 9.781 |
| W03 | 0.166 | 0.155 |
| W04 | 0.953 | 0.945 |
| W05 | 2.537 | 2.512 |
| **Total** | **3506.944** | **1657.758** |

The CP2 total (3,506.944 ms) is about twice the same-machine baseline (1,657.758 ms); for example R19 2,867.697 vs 1,350.668 ms and R13 155.227 vs 12.085 ms. Comparing CP2 "before" numbers with "after" numbers from another laptop would overstate most improvements, so only same-machine pairs are used above.

## 13. Reproduce

```bash
createdb mmt
psql -d mmt -f sql/01_schema.sql
psql -d mmt -f sql/02_load_data.sql          # from the folder containing seed_data/
./benchmarks/run_benchmark.sh mmt baseline_rerun 3 queries/workload_30.sql
psql -d mmt -f sql/05_indexes.sql
./benchmarks/run_benchmark.sh mmt optimized 3 sql/06_optimized_queries.sql
```
(For this report, the database was rebuilt from scratch between the two benchmark runs, so the optimized run also started from a fresh load.)
