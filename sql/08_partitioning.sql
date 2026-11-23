\set ON_ERROR_STOP on

-- Isolated Phase 5 demonstration. This does not change mmt.bookings or the
-- database used for the large-data query benchmarks. It copies only the columns
-- needed to demonstrate time-range partition pruning and uses extra disk space.
-- Run after sql/01_schema.sql and sql/03_load_large_data.sql.

CREATE SCHEMA IF NOT EXISTS mmt_partition_demo;
DROP TABLE IF EXISTS mmt_partition_demo.bookings;

-- PostgreSQL requires every UNIQUE/PRIMARY KEY constraint on a partitioned
-- table to include its partition key. Therefore this demo uses the composite
-- key (booking_id, booked_at), rather than the source table's booking_id key.
-- The source schema's global UNIQUE(booking_ref) is intentionally omitted.
-- A production migration must also update foreign keys from child tables to
-- include booked_at (or use a separate global booking-reference registry).
CREATE TABLE mmt_partition_demo.bookings (
    booking_id   BIGINT NOT NULL,
    booking_ref  TEXT NOT NULL,
    customer_id  BIGINT NOT NULL,
    booking_type TEXT NOT NULL,
    booked_at    TIMESTAMPTZ NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    status       TEXT NOT NULL,
    PRIMARY KEY (booking_id, booked_at)
) PARTITION BY RANGE (booked_at);

CREATE TABLE mmt_partition_demo.bookings_2025
    PARTITION OF mmt_partition_demo.bookings
    FOR VALUES FROM (TIMESTAMPTZ '2025-01-01 00:00:00+00')
             TO (TIMESTAMPTZ '2026-01-01 00:00:00+00');

CREATE TABLE mmt_partition_demo.bookings_2026
    PARTITION OF mmt_partition_demo.bookings
    FOR VALUES FROM (TIMESTAMPTZ '2026-01-01 00:00:00+00')
             TO (TIMESTAMPTZ '2027-01-01 00:00:00+00');

CREATE TABLE mmt_partition_demo.bookings_other
    PARTITION OF mmt_partition_demo.bookings DEFAULT;

INSERT INTO mmt_partition_demo.bookings
    (booking_id, booking_ref, customer_id, booking_type, booked_at, total_amount, status)
SELECT booking_id, booking_ref, customer_id, booking_type, booked_at, total_amount, status
FROM mmt.bookings;

ANALYZE mmt_partition_demo.bookings;

-- The plan should touch only bookings_2026 for this half-open date range.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM mmt_partition_demo.bookings
WHERE booked_at >= TIMESTAMPTZ '2026-06-01 00:00:00+00'
  AND booked_at <  TIMESTAMPTZ '2026-07-01 00:00:00+00';

-- Storage for the isolated copy, after loading:
SELECT pg_size_pretty(pg_total_relation_size('mmt_partition_demo.bookings'))
       AS partitioned_demo_total_size;
