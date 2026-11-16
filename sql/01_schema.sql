CREATE SCHEMA IF NOT EXISTS mmt;
SET search_path TO mmt, public;

CREATE TABLE airports (
    iata_code    CHAR(3) PRIMARY KEY
                 CHECK (iata_code ~ '^[A-Z]{3}$'),
    airport_name TEXT NOT NULL,
    city_name    TEXT NOT NULL,
    country_code CHAR(2) NOT NULL
                 CHECK (country_code ~ '^[A-Z]{2}$')
);

CREATE TABLE airlines (
    airline_code VARCHAR(2) PRIMARY KEY
                 CHECK (airline_code ~ '^[A-Z0-9]{2}$'),
    airline_name TEXT NOT NULL
);

CREATE TABLE hotels (
    hotel_id       BIGINT PRIMARY KEY,
    hotel_name     TEXT NOT NULL,
    city_name      TEXT NOT NULL,
    star_rating    SMALLINT NOT NULL
                   CHECK (star_rating BETWEEN 1 AND 5),
    user_rating    NUMERIC(2,1)
                   CHECK (user_rating BETWEEN 1 AND 5),
    amenities      JSONB NOT NULL
                   CHECK (jsonb_typeof(amenities) = 'object'),
    check_in_time  TIME NOT NULL,
    check_out_time TIME NOT NULL
);

CREATE TABLE room_types (
    room_type_id    BIGINT PRIMARY KEY,
    hotel_id        BIGINT NOT NULL REFERENCES hotels(hotel_id),
    room_name       TEXT NOT NULL,
    max_guests      SMALLINT NOT NULL CHECK (max_guests > 0),
    price_per_night NUMERIC(12,2) NOT NULL CHECK (price_per_night > 0),
    total_rooms     INTEGER NOT NULL CHECK (total_rooms > 0),
    UNIQUE (hotel_id, room_type_id)
);

CREATE TABLE customers (
    customer_id BIGINT PRIMARY KEY,
    full_name   TEXT NOT NULL,
    email       TEXT NOT NULL UNIQUE,
    phone       TEXT NOT NULL,
    loyalty_tier TEXT NOT NULL
                CHECK (loyalty_tier IN ('BLUE', 'SILVER', 'GOLD', 'PLATINUM')),
    created_at  TIMESTAMPTZ NOT NULL
);

CREATE TABLE coupons (
    coupon_code   TEXT PRIMARY KEY,
    applies_to    TEXT NOT NULL
                  CHECK (applies_to IN ('ALL', 'FLIGHT', 'HOTEL')),
    discount_pct  NUMERIC(5,2) NOT NULL
                  CHECK (discount_pct > 0 AND discount_pct <= 100),
    max_discount  NUMERIC(12,2) NOT NULL CHECK (max_discount >= 0),
    valid_from    DATE NOT NULL,
    valid_to      DATE NOT NULL,
    CHECK (valid_to >= valid_from)
);

CREATE TABLE flights (
    flight_id    BIGINT PRIMARY KEY,
    airline_code VARCHAR(2) NOT NULL REFERENCES airlines(airline_code),
    flight_no    TEXT NOT NULL,
    origin       CHAR(3) NOT NULL REFERENCES airports(iata_code),
    destination  CHAR(3) NOT NULL REFERENCES airports(iata_code),
    departure_at TIMESTAMPTZ NOT NULL,
    arrival_at   TIMESTAMPTZ NOT NULL,
    aircraft     TEXT NOT NULL,
    total_seats  INTEGER NOT NULL CHECK (total_seats > 0),
    base_fare    NUMERIC(12,2) NOT NULL CHECK (base_fare >= 0),
    status       TEXT NOT NULL
                 CHECK (status IN ('SCHEDULED', 'DELAYED', 'DEPARTED', 'LANDED', 'CANCELLED')),
    CHECK (origin <> destination),
    CHECK (arrival_at > departure_at)
);

CREATE TABLE bookings (
    booking_id    BIGINT PRIMARY KEY,
    booking_ref   TEXT NOT NULL UNIQUE,
    customer_id   BIGINT NOT NULL REFERENCES customers(customer_id),
    booking_type  TEXT NOT NULL
                  CHECK (booking_type IN ('FLIGHT', 'HOTEL')),
    booked_at     TIMESTAMPTZ NOT NULL,
    total_amount  NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    coupon_code   TEXT REFERENCES coupons(coupon_code),
    discount      NUMERIC(12,2) NOT NULL DEFAULT 0
                  CHECK (discount >= 0 AND discount <= total_amount),
    payment_method TEXT NOT NULL
                   CHECK (payment_method IN ('CARD', 'EMI', 'NETBANKING', 'UPI', 'WALLET')),
    status        TEXT NOT NULL
                  CHECK (status IN ('PENDING_PAYMENT', 'CONFIRMED', 'COMPLETED', 'CANCELLED')),
    cancelled_at  TIMESTAMPTZ,
    refund_amount NUMERIC(12,2),
    CHECK (coupon_code IS NOT NULL OR discount = 0),
    CHECK (refund_amount IS NULL OR
           (refund_amount >= 0 AND refund_amount <= total_amount)),
    CHECK (
        (status = 'CANCELLED' AND cancelled_at IS NOT NULL AND refund_amount IS NOT NULL)
        OR
        (status <> 'CANCELLED' AND cancelled_at IS NULL AND refund_amount IS NULL)
    )
);

CREATE TABLE flight_bookings (
    booking_id BIGINT PRIMARY KEY REFERENCES bookings(booking_id),
    flight_id  BIGINT NOT NULL REFERENCES flights(flight_id),
    cabin      TEXT NOT NULL
               CHECK (cabin IN ('ECONOMY', 'PREMIUM', 'BUSINESS')),
    passengers INTEGER NOT NULL CHECK (passengers > 0),
    fare_paid  NUMERIC(12,2) NOT NULL CHECK (fare_paid >= 0)
);

CREATE TABLE passengers (
    booking_id BIGINT NOT NULL REFERENCES flight_bookings(booking_id),
    seq_no     SMALLINT NOT NULL CHECK (seq_no > 0),
    full_name  TEXT NOT NULL,
    age        SMALLINT NOT NULL CHECK (age BETWEEN 0 AND 120),
    gender     CHAR(1) NOT NULL CHECK (gender IN ('F', 'M', 'X')),
    seat_no    TEXT,
    PRIMARY KEY (booking_id, seq_no)
);

CREATE TABLE hotel_bookings (
    booking_id  BIGINT PRIMARY KEY REFERENCES bookings(booking_id),
    hotel_id    BIGINT NOT NULL,
    room_type_id BIGINT NOT NULL,
    check_in    DATE NOT NULL,
    check_out   DATE NOT NULL,
    rooms       INTEGER NOT NULL CHECK (rooms > 0),
    guests      INTEGER NOT NULL CHECK (guests > 0),
    room_number TEXT,
    UNIQUE (booking_id, hotel_id),
    FOREIGN KEY (hotel_id, room_type_id)
        REFERENCES room_types(hotel_id, room_type_id),
    CHECK (check_out > check_in)
);

CREATE TABLE hotel_reviews (
    review_id   BIGINT PRIMARY KEY,
    booking_id  BIGINT NOT NULL,
    hotel_id    BIGINT NOT NULL,
    rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title       TEXT NOT NULL,
    review_text TEXT,
    created_at  TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (booking_id, hotel_id)
        REFERENCES hotel_bookings(booking_id, hotel_id)
);