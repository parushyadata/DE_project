\set ON_ERROR_STOP on

SET search_path TO mmt, public;

\copy mmt.airports FROM 'large_data/airports.csv' WITH (FORMAT csv, HEADER true)
\copy mmt.airlines FROM 'large_data/airlines.csv' WITH (FORMAT csv, HEADER true)
\copy mmt.hotels FROM 'large_data/hotels.csv' WITH (FORMAT csv, HEADER true)
\copy mmt.customers FROM 'large_data/customers.csv' WITH (FORMAT csv, HEADER true)
\copy mmt.coupons FROM 'large_data/coupons.csv' WITH (FORMAT csv, HEADER true)

\copy mmt.room_types FROM 'large_data/room_types.csv' WITH (FORMAT csv, HEADER true)
\copy mmt.flights FROM 'large_data/flights.csv' WITH (FORMAT csv, HEADER true)

\copy mmt.bookings FROM 'large_data/bookings.csv' WITH (FORMAT csv, HEADER true)
\copy mmt.flight_bookings FROM 'large_data/flight_bookings.csv' WITH (FORMAT csv, HEADER true)
\copy mmt.passengers FROM 'large_data/passengers.csv' WITH (FORMAT csv, HEADER true)
\copy mmt.hotel_bookings FROM 'large_data/hotel_bookings.csv' WITH (FORMAT csv, HEADER true)
\copy mmt.hotel_reviews FROM 'large_data/hotel_reviews.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;

SELECT 'airports' AS table_name, count(*) AS row_count FROM mmt.airports
UNION ALL SELECT 'airlines', count(*) FROM mmt.airlines
UNION ALL SELECT 'flights', count(*) FROM mmt.flights
UNION ALL SELECT 'hotels', count(*) FROM mmt.hotels
UNION ALL SELECT 'room_types', count(*) FROM mmt.room_types
UNION ALL SELECT 'customers', count(*) FROM mmt.customers
UNION ALL SELECT 'coupons', count(*) FROM mmt.coupons
UNION ALL SELECT 'bookings', count(*) FROM mmt.bookings
UNION ALL SELECT 'flight_bookings', count(*) FROM mmt.flight_bookings
UNION ALL SELECT 'passengers', count(*) FROM mmt.passengers
UNION ALL SELECT 'hotel_bookings', count(*) FROM mmt.hotel_bookings
UNION ALL SELECT 'hotel_reviews', count(*) FROM mmt.hotel_reviews
ORDER BY table_name;