# 03 · Baseline Timings

Baseline execution times for all 30 queries in `queries/workload_30.sql`, measured **before any optimization** (schema from `sql/01_schema.sql`: only the indexes PostgreSQL creates for PRIMARY KEY and UNIQUE constraints).

## Method

- Each query run with `EXPLAIN (ANALYZE, BUFFERS)`; the `Execution Time` line is recorded.
- Each query run **3 times**; the reported value is the **average** of the three runs.
- Write queries (W01–W05) run inside `BEGIN; … ROLLBACK;`, so the data is unchanged.
- Timings collected with `benchmarks/run_benchmark.sh` against the seed data (`seed_data.zip`, 144,792 bookings), loaded with `sql/02_load_data.sql` and `ANALYZE`d.
- PostgreSQL 18.6 (the version declared in `team.json`), default server settings (no tuning).
- The work was split three ways; each member's raw results are in `benchmarks/results/baseline/part-*.csv`, combined into `benchmarks/results/baseline/summary.csv`.

| Queries | Measured by |
|---|---|
| R01–R10 | Aranav Chhabra |
| R11–R20 | Parushya Data |
| R21–R25, W01–W05 | Sriharsha Mallavarapu (Apple M4, 16 GB) |

## Results

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|-------|------|--------------|-----------:|-----------:|-----------:|-------------:|
| R01 | READ | Flight search: Delhi → Mumbai on 5 July 2026 with seats left | 9.241 | 8.556 | 7.967 | 8.588 |
| R02 | READ | Fare calendar: cheapest Bengaluru → Delhi fare for each day of July 2026 | 0.822 | 0.851 | 0.887 | 0.853 |
| R03 | READ | Hotel search: 4★+ hotels in Goa with a swimming pool, best rated first | 0.307 | 0.251 | 0.246 | 0.268 |
| R04 | READ | Room availability: rooms left per room type of hotel 208 for 10–12 July 2026 | 2.635 | 2.323 | 2.122 | 2.360 |
| R05 | READ | "My Trips": customer 1021's upcoming confirmed trips | 7.050 | 5.898 | 5.635 | 6.194 |
| R06 | READ | Support: open a booking by its reference | 0.047 | 0.035 | 0.029 | 0.037 |
| R07 | READ | Airline manifest: passengers on flight 13047 ordered by seat | 2.088 | 2.089 | 2.062 | 2.080 |
| R08 | READ | Revenue management: July 2026 flights with fewer than 5 passengers booked | 6.210 | 9.008 | 5.592 | 6.937 |
| R09 | READ | Trends: 10 most-booked routes in June 2026 | 12.243 | 21.428 | 14.381 | 16.017 |
| R10 | READ | Flight status board: delayed flights | 0.697 | 0.675 | 0.656 | 0.676 |
| R11 | READ | Payments: bookings waiting for payment for more than 30 minutes (checked at 23:59 on 30 Jun 2026) | 16.649 | 15.682 | 13.122 | 15.151 |
| R12 | READ | Finance: revenue per booking type per month in 2026 (excluding cancellations) | 36.458 | 29.179 | 30.402 | 32.013 |
| R13 | READ | Marketing: coupons that have never been used | 157.149 | 154.126 | 154.405 | 155.227 |
| R14 | READ | Airline partnerships: cancellation rate of flight bookings per airline | 70.946 | 71.253 | 69.937 | 70.712 |
| R15 | READ | Hotel partnerships: room-nights sold per city for stays in June 2026 | 33.833 | 33.785 | 34.368 | 33.995 |
| R16 | READ | Insights: average days between booking and travel, per booking type and loyalty tier | 136.409 | 129.410 | 136.362 | 134.060 |
| R17 | READ | Loyalty: customers with 3 or more completed trips that started in 2026 | 41.608 | 41.363 | 41.921 | 41.631 |
| R18 | READ | Hotel page: Goa reviews that mention breakfast | 6.281 | 6.291 | 6.296 | 6.289 |
| R19 | READ | Operations: passengers booked on every flight departing in June 2026 | 2842.521 | 2849.013 | 2911.558 | 2867.697 |
| R20 | READ | Finance: bookings per day and running total for June 2026 | 12.943 | 13.304 | 13.056 | 13.101 |
| R21 | READ | Concessions: senior-citizen passengers (60+) per route in 2026 | 19.323 | 19.615 | 20.896 | 19.945 |
| R22 | READ | Support console: all bookings, newest first, page 4,001 (25 per page) | 32.531 | 32.618 | 36.568 | 33.906 |
| R23 | READ | Sign-in: find the customer by email, ignoring case | 3.677 | 3.663 | 3.685 | 3.675 |
| R24 | READ | Hotel ranking: Goa hotels with at least 5 reviews, by average review rating | 1.786 | 1.516 | 1.518 | 1.607 |
| R25 | READ | Insights: last-minute flight bookings (made less than 24 hours before departure) in 2026 | 20.353 | 20.287 | 19.852 | 20.164 |
| W01 | WRITE | Checkout: create a pending flight booking for customer 1021 | 0.372 | 0.362 | 0.359 | 0.364 |
| W02 | WRITE | Payment gateway callback: confirm the oldest booking that is waiting for payment | 9.581 | 9.646 | 9.996 | 9.741 |
| W03 | WRITE | Customer cancels booking MMA7772F with a 70% refund | 0.158 | 0.179 | 0.162 | 0.166 |
| W04 | WRITE | Flight ops: every flight that was scheduled to depart before 1 July 2026 has now departed | 1.022 | 0.916 | 0.922 | 0.953 |
| W05 | WRITE | Front desk: assign room numbers to every guest checking in on 1 July 2026 | 2.349 | 2.634 | 2.627 | 2.537 |

Sum of averages across the workload: **3,506.944 ms**.

## Observations

Slowest queries (average), the main targets for CP3:

1. **R19** — 2,867.697 ms (81.8% of total): Operations: passengers booked on every flight departing in June 2026
1. **R13** — 155.227 ms (4.4% of total): Marketing: coupons that have never been used
1. **R16** — 134.060 ms (3.8% of total): Insights: average days between booking and travel, per booking type and loyalty tier
1. **R14** — 70.712 ms (2.0% of total): Airline partnerships: cancellation rate of flight bookings per airline
1. **R17** — 41.631 ms (1.2% of total): Loyalty: customers with 3 or more completed trips that started in 2026

R19 alone accounts for 82% of the total baseline time.

## Caveats

- The three parts were measured by different members, possibly on different laptops. All used the same schema, seed data and script, and `team.json` declares PostgreSQL 18.6; R21–R25 and W01–W05 were confirmed on 18.6 with default settings. Absolute times are not strictly comparable across parts; compare each query against its own optimized timing in CP3 on the same machine.
- Three runs per query is a small sample; some sub-20 ms queries vary by more than 30% between runs (e.g. R08, R09).
