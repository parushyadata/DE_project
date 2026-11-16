# Schema Design

## Purpose

This PostgreSQL database stores MakeMyTrip flight and hotel data. The schema follows the column names in the 12 supplied CSV files so the fixed benchmark queries can run without being edited.

## Tables and relationships

| Table | Primary key | Purpose and main links |
|---|---|---|
| `airports` | `iata_code` | Airport name, city, and country. Referenced by flights. |
| `airlines` | `airline_code` | Airline names. Referenced by flights. |
| `flights` | `flight_id` | A dated flight, with its airline, origin, and destination. |
| `hotels` | `hotel_id` | Hotel details, ratings, times, and amenity data. |
| `room_types` | `room_type_id` | Room categories and capacity for a hotel. |
| `customers` | `customer_id` | Customer contact and loyalty information. |
| `coupons` | `coupon_code` | Coupon rules and validity dates. |
| `bookings` | `booking_id` | Shared booking details for flight and hotel bookings. |
| `flight_bookings` | `booking_id` | Flight-specific details for a booking. |
| `passengers` | (`booking_id`, `seq_no`) | One row per passenger on a flight booking. |
| `hotel_bookings` | `booking_id` | Hotel, room type, and stay details for a booking. |
| `hotel_reviews` | `review_id` | Reviews linked to a hotel booking. |

A customer can have many bookings. A booking has flight-specific or hotel-specific details. A flight booking can have multiple passenger rows. A hotel has room types and can receive hotel bookings. Flights refer to airports and airlines.

## Data types and constraints

- IDs use `BIGINT` to hold the supplied numeric identifiers and benchmark write IDs.
- Money uses `NUMERIC(..., 2)` to preserve cents. Dates and times use `DATE`, `TIME`, or `TIMESTAMPTZ` to match the CSV data.
- Phone numbers and seat numbers use text because they are identifiers, not values for arithmetic.
- Hotel amenities use `JSONB` because the supplied data is JSON and query R03 reads the `pool` property.
- Primary keys identify rows. Foreign keys connect related rows. Unique constraints protect airport and airline codes, customer emails, booking references, and other keys.
- Check constraints restrict values such as booking types, cabin classes, statuses, ratings, positive room counts, and valid date ranges.
- No tuning indexes are added in this phase. PostgreSQL creates indexes for primary-key and unique constraints automatically.

## Functional dependencies

The key of each table determines the other attributes in that row. Examples:

- `iata_code → airport_name, city_name, country_code`
- `airline_code → airline_name`
- `flight_id → airline_code, flight_no, origin, destination, departure_at, arrival_at, aircraft, total_seats, base_fare, status`
- `hotel_id → hotel_name, city_name, star_rating, user_rating, amenities, check_in_time, check_out_time`
- `room_type_id → hotel_id, room_name, max_guests, price_per_night, total_rooms`
- `customer_id → full_name, email, phone, loyalty_tier, created_at`
- `coupon_code → applies_to, discount_pct, max_discount, valid_from, valid_to`
- `booking_id → booking_ref, customer_id, booking_type, booked_at, total_amount, coupon_code, discount, payment_method, status, cancelled_at, refund_amount`
- `booking_id → flight_id, cabin, passengers, fare_paid` in `flight_bookings`
- `(booking_id, seq_no) → full_name, age, gender, seat_no`
- `booking_id → hotel_id, room_type_id, check_in, check_out, rooms, guests, room_number` in `hotel_bookings`
- `review_id → booking_id, hotel_id, rating, title, review_text, created_at`

## Normalization and deliberate repeated data

The tables separate customers, bookings, flights, hotels, and other entities so their details are not copied into every booking row. Passengers are stored as separate rows rather than as a list in a flight booking. This avoids repeating passenger columns and supports the benchmark queries.

Some supplied fields are repeated or derived, and are kept because the fixed workload uses them:

- `flight_bookings.passengers` stores a passenger count that can also be counted from `passengers`.
- `hotel_bookings.hotel_id` can be determined from its `room_type_id`.
- `hotel_reviews.hotel_id` can be determined from its hotel booking.
- `hotels.amenities` stores multiple flags in one JSON document.

The composite foreign keys in the schema keep the repeated hotel IDs consistent with their room type or booking. The repeated fields are documented so they can be considered during later optimization.

## Data validation after loading

After loading the CSV files, check that the row counts match the supplied data. Also check that:

1. Each booking has exactly one matching flight or hotel detail row, according to `booking_type`.
2. The number in `flight_bookings.passengers` matches the number of passenger rows for that booking.
3. Each hotel review refers to the same hotel as its hotel booking.

These checks must be run against PostgreSQL before recording that the load succeeded.