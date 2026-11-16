# Problem Understanding

MakeMyTrip needs a reliable database for flight and hotel bookings. The problems below show which users need information quickly and which teams need reports.

| Problem | Business need | Main stakeholder | Type |
|---|---|---|---|
| P1 | Search flights, compare fares by date, and see current seat availability. | Travellers | Customer-facing / real-time |
| P2 | Find hotels by amenities and check room availability for a date range. | Travellers, hotel partners | Customer-facing / real-time |
| P3 | Open My Trips, find a booking by reference, and sign in. | Travellers, customer support | Customer-facing / real-time |
| P4 | Prepare passenger manifests, low-load reports, and cancellation-rate reports. | Airline partners, revenue management | Reporting / analytics |
| P5 | Process pending payments, confirmations, and cancellations reliably under load. | Travellers, payments team | Customer-facing / real-time |
| P6 | Find coupons that have not been used. | Marketing team | Reporting / analytics |
| P7 | Report room-nights by city and update room details at check-in. | Hotel partners, front desk | Mixed: reporting / analytics and real-time operations |
| P8 | Review revenue, booking lead time, repeat customers, last-minute bookings, routes, and concessions. | Finance, loyalty, revenue management | Reporting / analytics |

## Assumptions

- The provided CSV files are the source of truth for the database design.
- A booking is for either a flight or a hotel, according to its booking type.
- Searches, checkout, payment updates, and check-in need timely results and correct current data.
- Reports must be accurate; no extra business rules will be assumed unless supported by the project files or data.