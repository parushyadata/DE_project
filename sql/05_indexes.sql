-- CP3: Query optimization indexes
-- Each index includes: which queries it serves, why this index type,
-- and why these columns in this order.

-- Required extension for trigram text search (R18).
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- R19, R07, R08, R14, R16: Composite B-tree on flight_bookings(flight_id, booking_id).
-- flight_id leads because R19's correlated subquery filters WHERE fb.flight_id = f.flight_id
-- (equality lookup). booking_id follows to satisfy the join to passengers/bookings, enabling
-- Index Only Scans so the heap is never visited. This turns R19 from a 2.9 s plan with
-- repeated seq scans of flight_bookings (84,899 rows × 720 loops) into a ~5 ms plan.
CREATE INDEX IF NOT EXISTS idx_flight_bookings_flight_booking
ON mmt.flight_bookings (flight_id, booking_id);

-- R17: Covering partial B-tree on bookings(booked_at, customer_id) INCLUDE (total_amount)
-- WHERE status = 'COMPLETED'.
-- booked_at leads because R17 filters booked_at >= '2026-01-01' (range predicate).
-- customer_id follows for the GROUP BY aggregation. INCLUDE (total_amount) covers the
-- SUM(total_amount) so the query runs as an Index Only Scan without heap fetches.
-- The partial condition restricts to completed bookings (~27% of rows), keeping the
-- index at 5 MB vs the 16 MB table.
CREATE INDEX IF NOT EXISTS idx_bookings_completed_date_customer
ON mmt.bookings (booked_at, customer_id)
INCLUDE (total_amount)
WHERE status = 'COMPLETED';

-- R18: GIN trigram index on hotel_reviews(review_text).
-- A B-tree cannot accelerate a leading-wildcard pattern like ILIKE '%breakfast%'.
-- pg_trgm breaks text into 3-character grams and builds a GIN inverted index.
-- PostgreSQL uses a Bitmap Index Scan on the trigrams to locate matching rows
-- without scanning all 15,913 review texts.
CREATE INDEX IF NOT EXISTS idx_hotel_reviews_text_trgm
ON mmt.hotel_reviews USING gin (review_text gin_trgm_ops);

-- R21: Partial B-tree on passengers(booking_id) WHERE age >= 60.
-- Only senior passengers are indexed (~8% of rows), keeping the index small (776 kB
-- vs 9.7 MB table). booking_id is the join column to flight_bookings.
CREATE INDEX IF NOT EXISTS idx_passengers_senior_booking
ON mmt.passengers (booking_id)
WHERE age >= 60;

-- R20, R22, R09, R25: B-tree on bookings(booked_at DESC).
-- DESC matches R22's ORDER BY booked_at DESC pagination (OFFSET 100000 LIMIT 25).
-- For R20, the sargable half-open TIMESTAMPTZ range filter enables an Index Only Scan
-- reading only 28 pages instead of 2,049. Single-column so PostgreSQL can also scan
-- it forward for ascending date-range queries.
CREATE INDEX IF NOT EXISTS idx_bookings_booked_at_desc
ON mmt.bookings (booked_at DESC);

-- R23: Expression B-tree on customers(lower(email)).
-- R23 filters WHERE lower(email) = '...'. Without this index PostgreSQL must seq-scan
-- all 50,000 customers and evaluate lower() on each row. The expression index
-- pre-computes lower(email), enabling a direct Index Scan (0.026 ms vs 3.675 ms).
CREATE INDEX IF NOT EXISTS idx_customers_lower_email
ON mmt.customers (lower(email));

-- R11, W02: Partial B-tree on bookings(booking_id) WHERE status = 'PENDING_PAYMENT'.
-- Only ~97 of 144,792 rows match this status, so the partial index is tiny (16 kB
-- vs 16 MB table). R11 filters on PENDING_PAYMENT and adds a booked_at range check;
-- W02 finds the MIN(booking_id) among pending rows. Both go from full seq scans
-- (reading all 2,049 heap pages) to an index scan reading only 3 pages.
CREATE INDEX IF NOT EXISTS idx_bookings_pending_booking_id
ON mmt.bookings (booking_id)
WHERE status = 'PENDING_PAYMENT';

-- W05: Partial B-tree on hotel_bookings(check_in, booking_id) WHERE room_number IS NULL.
-- W05 assigns room numbers to guests checking in on a specific date with no room yet.
-- check_in leads (equality filter), booking_id follows for the join to bookings.
-- The partial condition restricts to unassigned rooms, keeping the index small
-- (232 kB vs 4.4 MB table).
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_unassigned_checkin
ON mmt.hotel_bookings (check_in, booking_id)
WHERE room_number IS NULL;
