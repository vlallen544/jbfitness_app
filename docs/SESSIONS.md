# Coaching availability and session reservations

The reservation software is implemented for the Flutter iOS/Android app and staff web dashboard. A video service is **not connected**. New customer bookings remain disabled. No proposed call duration or cancellation rule has been accepted on the client’s behalf.

## Customer workflow

Open **Today → Live coaching sessions** to see available, reserved and used session credits, published times from assigned trainers, and the latest 50 saved appointments. All displayed times use Asia/Kolkata (IST). Normal includes zero live sessions, Premium includes 10 and Premium Plus includes 25 per membership period; higher plans do not add the lower plan’s allowance again.

When booking is enabled, a member reviews the trainer, date, duration and cancellation/no-show terms before confirming. A booking holds one credit. For example, a Premium member with no previous usage sees **9 available, 1 reserved, 0 used** after one reservation. Two customers competing for the same time cannot both reserve it. A customer also cannot hold overlapping appointments with different trainers.

The complete appointment must fit inside the current active membership. A scheduled renewal does not permit bookings against its future allowance. Membership expiry retains the customer’s appointment history.

Each booking saves its own policy snapshot. Later owner changes affect new bookings only. For example, if a booking’s saved rules charge one credit for a late cancellation, changing the current rules does not silently rewrite that booking’s terms. The confirmation shows the saved rules, and the success message reports whether the server actually used or released the held credit. “Charge” here means session-credit consumption, never a new monetary payment.

## Staff workflow

Sign in at the operations dashboard and open **Session calendar** (`/sessions`). The owner must explicitly confirm duration, minimum booking notice, booking horizon, free cancellation notice, late-cancellation usage and no-show usage. The form starts empty. Confirming rules alone cannot activate booking.

Trainers publish their own appointment times on five-minute boundaries. Duration comes from the confirmed policy. Overlapping trainer availability is rejected; adjacent appointments are permitted. The calendar shows at most 200 slots from the past 30 days through the next 60 days. Customers see at most 100 eligible available times.

Trainers manage their own slots; admins can manage the calendar. Withdrawing booked availability requires explicit acknowledgement of the customer cancellation and releases the hold without a penalty. After the scheduled end, the assigned trainer or admin can record completion or no-show with an attendance note. Completion consumes one held credit. No-show consumes or releases it according to the saved policy. Attendance records include the acting staff account and timestamp; no automatic no-show detector or provider webhook is implemented.

Calendar access reveals booking identity, times, status and attendance notes. It does not grant access to private progress photos or override the separate fitness/coaching sharing controls. Appointment notes should describe attendance rather than health details.

## Persistence and concurrency

- `011_sessions.sql`: nullable policy, revisioned slots/bookings, saved booking terms, attendance audit fields, deduplicated operations and session-ledger reasons.
- `012_session_environments.sql`: development/production availability separation. Production excludes development memberships, booking history, slots and cached reservation responses.
- Trainer advisory locks serialize calendar changes. Customer and membership row locks serialize competing holds, cancellations and deductions. A partial unique index prevents two active reservations for one slot.
- Every mutation uses a UUID request reference and payload hash. Identical retries return the saved result; conflicting reuse is rejected. Mobile and dashboard retain uncertain requests for retry.
- Usage is append-only in `membership_session_ledger`; each consumed booking has a unique ledger entry. Available allowance is `total − used − reserved`, bounded at zero. The older trusted completion helper also respects existing holds.
- Removed trainer assignments prevent joining; customer cancellation releases the hold without penalty when the trainer is no longer assigned. Staff may withdraw the affected appointment. Reassignment does not transfer existing appointments automatically.

## API and activation boundary

Customer routes require a customer session:

| Method | Route | Purpose |
|---|---|---|
| GET | `/me/sessions` | Rules, balance, eligible availability and owned history |
| POST | `/me/sessions` | Reserve using observed slot/policy revisions |
| POST | `/me/sessions/:id/cancel` | Cancel using observed booking revision |
| POST | `/me/sessions/:id/join` | Participant/time/membership checks; returns unavailable without provider |

Staff routes require a trainer/admin session:

| Method | Route | Purpose |
|---|---|---|
| GET | `/staff/sessions` | Own trainer calendar or owner calendar |
| POST | `/staff/sessions/policy` | Admin-only explicit policy confirmation |
| POST | `/staff/sessions/slots` | Trainer-only own availability |
| POST | `/staff/sessions/slots/:id/withdraw` | Withdraw with revision and explicit cancellation acknowledgement |
| POST | `/staff/sessions/bookings/:id/outcome` | Record attendance after scheduled end |
| POST | `/staff/sessions/bookings/:id/join` | Trainer-participant check; provider still unavailable |

The existing `/api/operations` dashboard boundary forwards a fixed set of calendar actions using the staff HttpOnly cookie, exact mutation Origin, role revalidation and bounded JSON bodies. No access token is returned to browser JavaScript.

Customer booking requires all three: confirmed owner rules, `ENABLE_SESSION_BOOKING=true`, and a configured `SessionVideoProvider` adapter. The current adapter always reports unconfigured and returns HTTP 503 for video joining. An environment flag alone cannot fabricate a working call. There is no live call SDK, camera/microphone UI, room creation, joining screen or provider billing integration yet. Joining checks are participant-only, matching-active-membership-only and limited to 15 minutes before start through scheduled end.

## Verification and remaining work

The isolated session integration suite tests policy confirmation/revisions, provider/flag gates, trainer overlap, competition, duplicate retries, ownership, period bounds, all 10/25 reservations, saved cancellation/no-show rules, staff withdrawal, attendance, legacy-credit protection and production exclusion. Video readiness is stubbed only in this test schema; no provider is contacted.

Flutter tests cover IST date rollover, disabled/Normal states, explicit booking confirmation, uncertain retries with the same reference, saved cancellation terms, actual server credit results and a 320 px layout at 1.6× text size. `scripts/browser-sessions-preview.ts` checks actual local owner confirmation, trainer availability, IST conversion and withdrawal using temporary database fixtures. It removes its schema and shuts down owned API/dashboard servers.

Before activation: confirm the actual client rules; choose and integrate the video service; implement provider rooms/tokens and call UI, trusted attendance reconciliation, reminders/notifications and physical Android/iOS permission/network tests. Review refunds, carry-forward, cancellations after start, trainer reassignment and outage handling alongside the outstanding billing decisions. Owner-confirmed technical policy values in QA are never production settings.
