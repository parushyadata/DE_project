# Phase 5: Scalability and Large-Data Performance Report

## 1. Objective

This phase evaluates the MakeMyTrip database under a larger dataset, measures query execution performance, examines storage growth, and demonstrates range partitioning for booking data.

The benchmark was run against a separate PostgreSQL database named `mmt_large`. The original `makemytrip` database was not modified.

## 2. Environment and dataset

- Database: PostgreSQL 18.6 (Postgres.app)
- Architecture: Apple Silicon (aarch64)
- Benchmark database: `mmt_large`
- Dataset source: DBMS-MakeMyTrip large-data release
- Benchmark script: `benchmarks/run_benchmark.sh`
- Optimized workload: `sql/06_optimized_queries.sql`
- Runs per query: 3
- Measurement: `EXPLAIN (ANALYZE, BUFFERS)`

### Loaded table counts

| Table | Rows |
|---|---:|
| airports | 16 |
| airlines | 5 |
| hotels | 60,000 |
| customers | 800,000 |
| coupons | 30 |
| room_types | 180,000 |
| flights | 13,848 |
| bookings | 2,897,285 |
| flight_bookings | 1,698,936 |
| passengers | 3,272,394 |
| hotel_bookings | 1,198,349 |
| hotel_reviews | 318,847 |
| **Total** | **10,439,710** |

## 3. Storage measurements

Measured using PostgreSQL database and relation size functions.

| Metric | Size |
|---|---:|
| Entire mmt_large database | 1,979 MB |
| mmt.bookings including indexes | 660 MB |
| mmt.passengers including indexes | 304 MB |
| mmt.hotel_bookings including indexes | 153 MB |
| Partitioned bookings demo, tables and indexes | Approximately 356 MB |

The partitioned parent relation reports zero direct storage because rows are stored in its child partitions. The measured child totals are 238 MB + 118 MB + 216 kB, approximately 356 MB. In `mmt`, the base tables total 851 MB and their indexes total 762 MB. The 1,979 MB database total also includes other schemas and PostgreSQL overhead. The original seed database was not available locally, so seed-size measurements are not reported.

## 4. Large-data benchmark results

All 30 optimized queries were executed three times. The following values are the measured average execution times in milliseconds.

### Read queries

| Query | Average (ms) |
|---|---:|
| R01 | 5.475 |
| R02 | 1.037 |
| R03 | 5.154 |
| R04 | 17.790 |
| R05 | 46.139 |
| R06 | 0.129 |
| R07 | 6.355 |
| R08 | 18.535 |
| R09 | 56.738 |
| R10 | 0.081 |
| R11 | 0.413 |
| R12 | 279.059 |
| R13 | 161.431 |
| R14 | 464.874 |
| R15 | 114.563 |
| R16 | 1162.204 |
| R17 | 269.626 |
| R18 | 17.480 |
| R19 | 111.995 |
| R20 | 19.754 |
| R21 | 127.436 |
| R22 | 9.857 |
| R23 | 0.191 |
| R24 | 32.433 |
| R25 | 201.568 |

### Write queries

| Query | Average (ms) |
|---|---:|
| W01 | 1.170 |
| W02 | 1.468 |
| W03 | 0.418 |
| W04 | 0.440 |
| W05 | 37.608 |

The detailed execution plans for all three runs of each query are preserved in `benchmarks/results/large/`.

## 5. Phase 4 comparison and growth

The table compares each recorded Phase 4 optimized average with the large-data average. These are the values in `benchmarks/results/optimized/summary.csv` and `benchmarks/results/large/summary.csv`; each summary has 30 query rows, and each large raw plan contains three `Execution Time` measurements. The Phase 4 and Phase 5 runs used different machines/PostgreSQL builds, so the ratios are indicative rather than a controlled row-count-only experiment.

| Query | Phase 4 optimized (ms) | Large data (ms) | Large ÷ Phase 4 |
|---|---:|---:|---:|
| R01 | 1.095 | 5.475 | 5.00x |
| R02 | 0.760 | 1.037 | 1.36x |
| R03 | 0.229 | 5.154 | 22.51x |
| R04 | 1.897 | 17.790 | 9.38x |
| R05 | 6.027 | 46.139 | 7.66x |
| R06 | 0.025 | 0.129 | 5.16x |
| R07 | 0.097 | 6.355 | 65.52x |
| R08 | 1.223 | 18.535 | 15.16x |
| R09 | 7.735 | 56.738 | 7.34x |
| R10 | 0.062 | 0.081 | 1.31x |
| R11 | 0.041 | 0.413 | 10.07x |
| R12 | 22.465 | 279.059 | 12.42x |
| R13 | 7.988 | 161.431 | 20.21x |
| R14 | 27.750 | 464.874 | 16.75x |
| R15 | 14.339 | 114.563 | 7.99x |
| R16 | 62.177 | 1162.204 | 18.69x |
| R17 | 13.195 | 269.626 | 20.43x |
| R18 | 1.009 | 17.480 | 17.32x |
| R19 | 5.612 | 111.995 | 19.96x |
| R20 | 1.323 | 19.754 | 14.93x |
| R21 | 15.213 | 127.436 | 8.38x |
| R22 | 8.903 | 9.857 | 1.11x |
| R23 | 0.028 | 0.191 | 6.82x |
| R24 | 1.539 | 32.433 | 21.07x |
| R25 | 15.529 | 201.568 | 12.98x |
| W01 | 0.384 | 1.170 | 3.05x |
| W02 | 0.169 | 1.468 | 8.69x |
| W03 | 0.165 | 0.418 | 2.53x |
| W04 | 0.174 | 0.440 | 2.53x |
| W05 | 0.618 | 37.608 | 60.85x |

### Growth interpretation

The large release has approximately 20× the seed rows overall. Runtime ratios do not equal row-count growth uniformly because plans, cache state, hardware, data distribution, and PostgreSQL build differ.

- **Stayed near the same time (≤2×):** R02, R10, R22. Their measured plans can use a small lookup or ordered index path; R22 is served by the date index despite its high offset.
- **Grew by 2–10×:** R01, R04, R05, R06, R09, R15, R21, R23, W01, W02, W03, W04. These include joins/filters over larger booking tables as well as point lookups that remain relatively quick.
- **Grew around 10–25×:** R03, R08, R11, R12, R13, R14, R16, R17, R18, R19, R20, R24, R25. Queries that scan or aggregate a broad share of a larger relation tend to track data growth; index-assisted queries can still grow from increased heap/index pages and cold reads.
- **Grew more than 25×:** R07 and W05. Their large-run averages are especially affected by one slow first run: R07 runs were 17.225, 0.921, and 0.918 ms; W05 runs were 93.044, 9.983, and 9.796 ms. This points to cold-page/cache and I/O sensitivity, so the averages hide a substantial warm-versus-cold difference.

### Performance targets

Targets come from the Phase 5 brief in `README.md`. Five real-time queries miss the 5 ms average target; all interactive, reporting, and batch queries meet their respective average targets.

| Query | Target (ms) | Large average (ms) | Status |
|---|---:|---:|---|
| R01 | < 5 | 5.475 | misses |
| R02 | < 5 | 1.037 | meets |
| R03 | < 5 | 5.154 | misses |
| R04 | < 5 | 17.790 | misses |
| R05 | < 5 | 46.139 | misses |
| R06 | < 5 | 0.129 | meets |
| R07 | < 5 | 6.355 | misses |
| R08 | < 250 | 18.535 | meets |
| R09 | < 5000 | 56.738 | meets |
| R10 | < 5 | 0.081 | meets |
| R11 | < 5 | 0.413 | meets |
| R12 | < 5000 | 279.059 | meets |
| R13 | < 250 | 161.431 | meets |
| R14 | < 5000 | 464.874 | meets |
| R15 | < 5000 | 114.563 | meets |
| R16 | < 5000 | 1162.204 | meets |
| R17 | < 5000 | 269.626 | meets |
| R18 | < 250 | 17.480 | meets |
| R19 | < 5000 | 111.995 | meets |
| R20 | < 5000 | 19.754 | meets |
| R21 | < 5000 | 127.436 | meets |
| R22 | < 250 | 9.857 | meets |
| R23 | < 5 | 0.191 | meets |
| R24 | < 250 | 32.433 | meets |
| R25 | < 5000 | 201.568 | meets |
| W01 | < 5 | 1.170 | meets |
| W02 | < 5 | 1.468 | meets |
| W03 | < 5 | 0.418 | meets |
| W04 | < 1000 | 0.440 | meets |
| W05 | < 250 | 37.608 | meets |

The real-time misses are R01 (5.475 ms), R03 (5.154 ms), R04 (17.790 ms), R05 (46.139 ms), and R07 (6.355 ms). Their measured bottlenecks are discussed below. No before/after optimization on the large dataset is claimed because no correctness-preserving change was benchmarked there.

## 6. Slow-query investigation

### R01: Flight search

- Average execution time: 5.475 ms, just over the 5 ms target.
- The plan scans all 13,848 flights to find the requested route/date, then uses `idx_flight_bookings_flight_booking` and the bookings primary key for the 101 matching flight bookings.
- The index-assisted join is selective, but the route/date predicate still scans the flights table. Run 1 took 11.776 ms and read 216 buffers; runs 2 and 3 were faster, so the average also reflects cache state.

### R03: Hotel search

- Average execution time: 5.154 ms, just over the 5 ms target.
- The plan sequentially scans the 60,000-row `hotels` table. This is a small absolute overrun and reflects the larger search table; no alternate index plan was benchmarked.

### R04: Room availability

- Average execution time: 17.790 ms.
- The plan parallel-sequentially scans `hotel_bookings` for the date-overlap conditions, removing about 398,049 rows per worker, and scans all 60,000 `room_types` rows for hotel 208. Run 1 read 12,523 shared buffers.
- Those broad scans of 1.2 million hotel bookings and 180,000 room types explain the cost. A composite index aligned with date overlap is not a straightforward B-tree range lookup; a targeted index experiment would need to preserve the availability calculation and be measured against the full plan.


### R05: Customer confirmed trips

- Average execution time: 46.139 ms.
- The plan parallel-sequentially scans all 2.9 million `bookings` rows for `customer_id = 1021` and `status = CONFIRMED`; run 3 removed 965,762 rows per worker and read 34,292 shared buffers. The selected customer had no matching rows, so later joins were never executed.
- A composite or partial index matching customer and status could avoid this scan, but no such change was benchmarked or correctness-checked in this Phase 5 work.

### R07: Flight passenger manifest

- Average execution time: 6.355 ms.
- The plan uses an index-only scan on `flight_bookings` and index lookups on `bookings` and `passengers`.
- Runs were 17.225, 0.921, and 0.918 ms. The first run read 386 shared buffers; later runs hit cached buffers. This cache-sensitive spread pushes the three-run average above target even though the two warm runs are below 1 ms.
- The index lookup path is already selective; the measured bottleneck is cold-page access through its index and row lookups, not a full scan.

### Other expensive queries

- R14: 464.874 ms, involving bookings, flight bookings, flights and airlines.
- R16: 1162.204 ms, the slowest query, involving bookings, customers, hotel bookings, flight bookings and flights.
- R12: 279.059 ms, involving a sequential scan on bookings.
- R17: 269.626 ms, despite using the partial completed-bookings index.
- R25: 201.568 ms, involving flight bookings, bookings and flights.

These results identify opportunities for further query-specific investigation. No unmeasured optimization improvement is claimed in this report.

## 7. Partitioning design and pruning evidence

The experiment in `sql/08_partitioning.sql` creates an isolated range-partitioned copy of bookings using `booked_at`.

The partitions are:

- `bookings_2025`: 2025 date range.
- `bookings_2026`: 2026 date range.
- `bookings_other`: default partition.

The primary key is `(booking_id, booked_at)` because PostgreSQL requires a partitioned unique or primary-key constraint to include the partition key.

The June 2026 query uses a half-open date range:

- `booked_at >= 2026-06-01`
- `booked_at < 2026-07-01`

The execution plan accesses only `bookings_2026`, demonstrating partition pruning. During this review, I reran the read-only EXPLAIN on the available `mmt_large` database: it used a parallel sequential scan of that partition only and returned in 188.766 ms (11,406 shared buffer hits). This is one observed run, not a three-run benchmark; it should not be compared directly with the query workload averages.

### Partition storage

| Partition relation | Size |
|---|---:|
| bookings_2025 | 238 MB |
| bookings_2026 | 118 MB |
| bookings_other | 216 kB |
| bookings_2025_pkey | 58 MB |
| bookings_2026_pkey | 29 MB |
| bookings_other_pkey | 56 kB |

The partitioned parent has no direct storage of its own. The data and indexes reside in the child relations; the measured child total was approximately 356 MB.

### Production migration considerations

This is an isolated demonstration, not a production migration.

The original bookings table has a global unique constraint on `booking_ref`. That constraint is intentionally omitted from the partitioned demonstration because a partitioned unique constraint must include the partition key.

Child-table foreign keys must also be redesigned to include `booked_at`, or a separate global booking-reference registry must be introduced.

A production migration would therefore require coordinated changes to constraints, foreign keys, application queries, and migration procedures.

## 8. Scalability recommendations

### Indexing
- Continue using selective B-tree indexes for equality, range and join predicates.
- Use partial indexes where a query consistently filters on a specific status.
- Evaluate composite indexes against the complete predicate and ordering of expensive queries.
- Avoid creating indexes without checking write overhead and query plans.

### Partitioning
- Consider range partitioning bookings by booking date when historical data and date-scoped queries continue to grow.
- Establish retention and archival policies for older partitions.
- Monitor partition pruning using `EXPLAIN (ANALYZE, BUFFERS)`.

### Read replicas
- For a production deployment with read-heavy traffic, consider asynchronous read replicas for reporting and analytical workloads.
- Keep transactionally sensitive reads on the primary when replica lag could cause stale results.

### Caching
- Cache frequently requested, relatively stable data such as airport, airline and hotel reference information.
- Use suitable expiration and invalidation policies for dynamic availability and pricing information.
- Avoid treating cached availability as authoritative during booking confirmation.

### Sharding
- Consider sharding only when a single PostgreSQL instance becomes insufficient for storage or throughput.
- A customer-based shard key may distribute customer-centric workloads, but cross-shard joins, booking references and transactions add complexity.
- Evaluate partitioning, query optimization and read replicas before introducing sharding.

### Maintenance and monitoring
- Run `ANALYZE` after large data loads and significant data changes.
- Monitor table and index growth, sequential scans, buffer reads and query latency.
- Review expensive queries using execution plans.
- Establish regular vacuuming, backup and recovery procedures.

## 9. Conclusion

The large-data experiment loaded 10,439,710 rows into a separate PostgreSQL database and benchmarked all 30 optimized read and write queries three times each. Five customer-facing averages exceed the 5 ms target; the other 25 queries meet their group targets. The large database contains 851 MB of base tables and 762 MB of indexes in schema `mmt`; total database size is 1,979 MB. Seed database storage was unavailable for measurement.

Performance varied significantly across the workload: R06, R10, R11 and R23 remained below 1 ms on average, while R16 exceeded 1 second.

The partitioning demonstration showed that a date-filtered June 2026 query accessed only the 2026 partition. The experiment also exposed important production design considerations around global uniqueness and foreign keys.

The raw execution plans and benchmark summary are retained under `benchmarks/results/large/` to support verification and future optimization.
