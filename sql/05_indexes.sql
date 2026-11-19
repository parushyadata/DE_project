-- CP3: Query optimization indexes

-- Required extension for trigram text search.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- R19: Accelerate passenger counts grouped by flight.
CREATE INDEX IF NOT EXISTS idx_flight_bookings_flight_booking
ON mmt.flight_bookings (flight_id, booking_id);

-- R17: Accelerate completed-booking aggregation by date and customer.
CREATE INDEX IF NOT EXISTS idx_bookings_completed_date_customer
ON mmt.bookings (booked_at, customer_id)
INCLUDE (total_amount)
WHERE status = 'COMPLETED';

-- R18: Accelerate substring searches in hotel reviews.
CREATE INDEX IF NOT EXISTS idx_hotel_reviews_text_trgm
ON mmt.hotel_reviews USING gin (review_text gin_trgm_ops);

-- R21: Accelerate senior-passenger filtering and booking joins.
CREATE INDEX IF NOT EXISTS idx_passengers_senior_booking
ON mmt.passengers (booking_id)
WHERE age >= 60;

-- R20 and R22: Accelerate date-range filtering and newest-first booking pagination.
CREATE INDEX IF NOT EXISTS idx_bookings_booked_at_desc
ON mmt.bookings (booked_at DESC);

-- R23: Accelerate case-insensitive customer email lookups.
CREATE INDEX IF NOT EXISTS idx_customers_lower_email
ON mmt.customers (lower(email));

-- W02: Accelerate finding the oldest pending booking.
CREATE INDEX IF NOT EXISTS idx_bookings_pending_booking_id
ON mmt.bookings (booking_id)
WHERE status = 'PENDING_PAYMENT';

-- W05: Accelerate room assignment for unassigned hotel bookings.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_unassigned_checkin
ON mmt.hotel_bookings (check_in, booking_id)
WHERE room_number IS NULL;
