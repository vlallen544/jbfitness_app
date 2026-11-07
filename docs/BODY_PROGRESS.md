# Body progress

Open **Today → View body progress**. Add one dated record with optional weight (kg), waist, chest, arm and thigh measurements (cm). Save it, then open the record from history to add optional front, side and back photos. No sample measurements are seeded into customer accounts.

For example, a customer records 80.5 kg on November 1 and 79 kg on November 7. The chart plots those dated values; the comparison shows **−1.5 kg**. If waist was not recorded on both dates, it says so rather than displaying zero. Customers select the dates and photo angle to compare. An increase or decrease is not labelled good or bad.

## Behavior

- One active record per customer/date, from 2020 through the server's current Asia/Kolkata date. Dates are fixed after creation; delete and recreate to correct a date.
- All measurements are optional, supporting photo-only records. Blank values stay unknown. Positive values accept up to two decimals. Software bounds: weight 500 kg, waist/chest 400 cm, arm 200 cm, thigh 250 cm; these are input limits, not recommendations.
- Charts use actual dates and recorded values only; they do not fill missing dates or measurements with zero. A single point shows the value without implying a trend. Comparisons calculate second date minus first date.
- Chart selection covers each available measurement. Numeric history and date comparisons accompany the chart for accessibility.
- Editing a dated weight does not change onboarding/profile weight or generate AI recommendations. No body-fat calculation, image analysis, appearance score or automatic trainer sharing is implemented.
- Active membership is required to add/edit measurements or upload photos. Expired members retain history, photo reads and deletion controls.

## Private photos

Photos are optional, with one front, side and back photo per record. The user selects a photo and then explicitly taps **Save private photo**. A thumbnail can be enlarged and zoomed. Delete a photo before replacing its angle. Android lost-picker recovery is available when returning to an existing record; recovered content is never automatically uploaded. Physical-device behavior remains unverified.

The server accepts JPEG, PNG and WebP up to 4 MB and 16 million decoded pixels, rejects animations and unsupported bytes, corrects orientation, removes original metadata and resizes within 1,600 pixels. Processed JPEGs must fit within 1 MB. The current storage allowance is 300 photos and 3,660 active dated records per customer; confirm operational limits before launch.

Migration `007_body_progress.sql` stores normalized JPEG bytes privately in PostgreSQL, separate from measurement list responses. Photos have no public or signed download URLs. Every image read authenticates the session and checks customer ownership. Responses use `Cache-Control: private, no-store` and JPEG content type. The Flutter client fetches bytes with its authorization header and keeps display bytes in widget memory; browser screenshots, device screenshots, temporary picker files and operating-system caches are outside this server control.

Progress photos are not sent to AI. This version exposes customer-only endpoints; trainer/admin review requires a separate assigned-trainer and consent-controlled implementation. Database access and backups must be restricted in deployment. PostgreSQL byte storage is a development-stage choice; evaluate private object storage and encrypted backups before scaling.

## Edits, retries and deletion

Customer-row locks serialize creates/uploads/deletes. One-date and one-angle uniqueness are enforced in the database. Creation references and normalized payload hashes deduplicate retries and reject changed input. Measurement edits also require a revision and retain retry references, preventing concurrent overwrites. On an uncertain mobile save, fields stay locked and retry sends the same payload/reference; closing and refreshing reloads server state.

Photo upload retries reuse the same image/angle/reference. A deleted reference cannot resurrect media. Deleting a photo clears its stored bytes and preserves a small retry tombstone. Deleting a whole record clears measurements and deletes attached photo rows; a record tombstone with identifiers/date and hashed creation reference remains for retry protection. Repeated owner deletion succeeds. These operations remove active app data; backup retention and full account erasure remain separate launch policies.

## API

All routes below follow `/api/v1/me/progress` and require a customer session.

| Method | Route | Behavior |
|---|---|---|
| GET | `/` | Date-sorted measurement records and photo identifiers, calendar and write permission |
| POST | `/` | `{date, measurements, requestId}`; create or replay |
| PUT | `/:id` | `{measurements, revision, requestId}`; update or replay |
| PUT | `/:id/delete` | `{revision}`; clear record and delete attached photos |
| POST | `/:id/photos` | Multipart `photo`, `angle`, `requestId`; explicit upload |
| GET | `/photos/:photoId` | Authenticated owner-only JPEG bytes |
| DELETE | `/photos/:photoId` | Clear a photo's bytes; duplicate-safe deletion |

## Verification

Database integration checks exercise actual HTTP uploads, concurrent creation/edit retries, date and measurement validation, customer isolation, metadata removal/orientation, invalid/oversized uploads, private image headers, deletion, restart persistence and expiry behavior. Flutter checks cover numeric comparisons, missing values, optional-field validation, explicit save/upload, retry payloads, narrow/enlarged-text layout and expired-member photo deletion.

Verified project totals: 64 backend integration checks and 37 Flutter tests pass. Flutter analysis is clean; API compilation and the Flutter web build succeed. The iOS permission plist includes both progress and meal photos and parses successfully; that does not establish native permission behavior.

`scripts/browser-progress-preview.mjs` exercises the phone-sized UI using fixture API records and generated solid-color technical images, including actual file selection and authenticated image display. It does not depict a real transformation or establish native camera behavior. Android/iOS builds and physical-device camera/gallery tests remain pending platform setup.
