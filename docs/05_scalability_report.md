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
| Partitioned bookings demo, tables and indexes | Approximately 443 MB |

The partitioned parent relation reports zero direct storage because rows are stored in its child partitions. The partition tables and their indexes were measured separately.

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

## 5. Baseline comparison

The available baseline measurements cover R01–R10. The following comparison uses the recorded averages in `benchmarks/results/baseline_part/summary.csv`.

| Query | Baseline (ms) | Large data (ms) | Large / baseline |
|---|---:|---:|---:|
| R01 | 8.588 | 5.475 | 0.64x |
| R02 | 0.853 | 1.037 | 1.22x |
| R03 | 0.268 | 5.154 | 19.23x |
| R04 | 2.360 | 17.790 | 7.54x |
| R05 | 6.194 | 46.139 | 7.45x |
| R06 | 0.037 | 0.129 | 3.49x |
| R07 | 2.080 | 6.355 | 3.06x |
| R08 | 6.937 | 18.535 | 2.67x |
| R09 | 16.017 | 56.738 | 3.54x |
| R10 | 0.676 | 0.081 | 0.12x |

These ratios are indicative comparisons between the recorded baseline and large-data runs. The baseline represents the smaller benchmark dataset. They should not be interpreted as controlled scaling experiments in which only row count changed.

R03, R04 and R05 show substantial increases. R01 and R10 are faster in the large-data run, illustrating that execution time is also affected by query plans, index availability, cache state and data distribution.

## 6. Slow-query investigation

### R04: Room availability

- Average execution time: 17.790 ms.
- Observed plan includes sequential scans on `hotel_bookings` and `room_types`, followed by an index lookup on `bookings`.
- The large hotel-booking relation increases the amount of data that may need to be examined.
- Further investigation should examine selectivity of the hotel and date predicates and whether a composite index matches the complete filter.

### R05: Customer confirmed trips

- Average execution time: 46.139 ms.
- Observed plan includes a sequential scan on `bookings`, followed by index lookups on flight and hotel booking relations.
- The bookings table contains approximately 2.9 million rows.
- Further optimization should evaluate a composite or partial index matching the customer and booking-status predicates, after examining the full query and plan.

### R07: Flight passenger manifest

- Average execution time: 6.355 ms.
- The plan uses an index-only scan on `flight_bookings` and index lookups on `bookings` and `passengers`.
- The minimum was 0.918 ms and maximum was 17.225 ms.
- The variation suggests sensitivity to cache state and physical reads. Buffer statistics in the raw plans should be used when investigating this further.

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

The execution plan accesses only `bookings_2026`, demonstrating partition pruning. The observed execution time was 28.286 ms.

### Partition storage

| Partition relation | Size |
|---|---:|
| bookings_2025 | 238 MB |
| bookings_2026 | 118 MB |
| bookings_other | 216 kB |
| bookings_2025_pkey | 58 MB |
| bookings_2026_pkey | 29 MB |
| bookings_other_pkey | 56 kB |

The partitioned parent has no direct storage of its own. The data and indexes reside in the child relations.

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

The large-data experiment loaded 10,439,710 rows into a separate PostgreSQL database and benchmarked all 30 optimized read and write queries three times each.

The database occupied approximately 1,979 MB. Performance varied significantly across the workload: R06, R10, R11 and R23 remained below 1 ms on average, while R16 exceeded 1 second.

The partitioning demonstration showed that a date-filtered June 2026 query accessed only the 2026 partition. The experiment also exposed important production design considerations around global uniqueness and foreign keys.

The raw execution plans and benchmark summary are retained under `benchmarks/results/large/` to support verification and future optimization.
