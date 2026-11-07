# Saved habits

Customers can create daily habits with a name and monthly target, check/uncheck dates, view progress and archive habits while retaining history. Today uses persisted records; it no longer contains a sample checklist.

## Calendar and targets

- Calendar dates and eligibility use `Asia/Kolkata`, supplied by the server. Individual customer timezones are a later extension.
- Habits begin on their creation date. Past dates on/after that date can be corrected; future dates cannot be logged.
- Monthly goals are the smaller of the requested target (1–31) and the days that the habit exists during that month. February, leap years and partial months are handled explicitly.
- Each row shows actual completed days and its effective target. The monthly completion summary counts all true check-ins. Overall target progress sums `min(completed, goal)` per habit and divides by summed goals, so over-completing one habit cannot make up for another missed target.
- The daily chart shows completed habits relative to eligible habits on each date. Future days show no completion.
- Weekly mode groups a month into days 1–7, 8–14, 15–21, 22–28, and remaining days. The displayed date range makes this explicit; these are not ISO calendar weeks.
- Names and targets are fixed when a habit is created in this milestone. Archive and create a new habit to change them without rewriting historical targets.
- Archiving is effective through today, preserves existing checkmarks, removes the habit from the active Today checklist, and makes its history read-only. No restore/delete action is exposed yet.
- Up to 20 active habits per customer. No default habits are silently created; add your own through the app.
- Adding a habit from an older month returns the view to the current server month, where the new habit begins.

Habit checkmarks do not mark workout sessions complete or create meal records. They record the customer's own daily check-in.

## API

All endpoints require a customer session. Active membership with `habitTracking` is required for writes. Read access remains available after expiry, with `canEdit: false`.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/api/v1/me/habits?month=YYYY-MM` | Habits, entries, effective goals, daily chart counts, totals, server calendar and edit permission. Omit month for the current server month. |
| POST | `/api/v1/me/habits` | Create with `{name,targetDays,requestId}`. |
| PUT | `/api/v1/me/habits/:id/days/YYYY-MM-DD` | Save `{completed:true}` or `{completed:false}`. |
| PUT | `/api/v1/me/habits/:id/archive` | Archive with an empty JSON object. |

Months are restricted to 2020–2100; dates must be real calendar dates. Request bodies reject unknown fields. Customers cannot override ownership. Trainer/admin accounts do not gain habit access through these customer routes.

## Persistence and concurrency

Migration `004_habits.sql` stores habits and one entry per habit/date. Foreign keys cascade on account deletion. Creation references are unique per customer; retries return the same habit, while reusing a reference with different input conflicts. Customer-row locking enforces the active-habit limit during concurrent creation.

Day updates and archiving lock the owned habit row. Repeated same-value saves are idempotent; conflicting updates to the same day use last-processed-write semantics. This does not provide revision conflicts across devices. Month grids/totals are read in one repeatable-read snapshot.

Flutter waits for the server and reloads the month after saving. Failed writes do not show fake completion. Refresh and app resume retrieve saved state. A failed creation can be retried with its original request ID while the widget remains open. Offline queuing and a persistent cross-device update feed are not implemented.

## Verification

Database integration checks cover authentication/roles, entitlement gates, strict inputs, concurrent creation retries, cross-customer isolation, valid/invalid dates, idempotent check/uncheck, restart persistence, archival history, membership expiry, leap months and aggregate goal calculations. Mobile checks cover persistence after widget recreation, failed saves, creation retry references, validation and narrow weekly/monthly views with enlarged text.

Run `npm run db:migrate`, `npm run test:integration`, and `bash scripts/mobile.sh test --no-pub`. The browser design helper uses sample responses and does not replace database integration or native-device testing.
