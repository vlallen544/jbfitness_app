# Architecture — foundation decisions

## Components

Flutter serves customer mobile flows; Next.js serves trainer/admin workflows; NestJS owns the API. PostgreSQL persists accounts, memberships, trainer assignments, reviewed exercise definitions, versioned workout plans, prescriptions and progress through migrations. The membership catalogue remains read-only code configuration until real purchase integration.

The plan catalogue remains public at the API and dashboard `/plans`. Registration creates customer roles only. Passwords use salted scrypt; random opaque session tokens are stored as SHA-256 hashes server-side with seven-day development expiry. Logout deletes the server session. The mobile client stores only the token through flutter_secure_storage and fetches profile data from the API on restoration.

Customer endpoints derive identity from the validated session, never a submitted user ID. Trainer profile reads require a trainer role, an existing assignment, and customer-enabled profile sharing. Coaching review additionally requires a new separate opt-in. The dashboard now has private staff operations behind a same-origin server route and HttpOnly cookie; admins manage assignments/queue metadata, while trainers access consent-controlled details. Public registration cannot provision staff roles.

PostgreSQL runs in project-scoped Docker Compose on loopback port 55432 with a named volume. Local credentials are randomly generated into ignored, owner-readable environment files. Parameterized queries separate values from SQL; profile input uses a strict schema. Development throttling is in process; email verification, recovery, production deployment configuration, and distributed abuse controls remain launch work.

## AI workflow (milestone 6)

Customer context → routine reviewer → workout planner → deterministic checks + LLM review → bounded revision → publication or trainer escalation. Approved exercise identifiers connect plans to stored demonstrations. Keep plan versions, actual logged activity, and cost/latency traces. The app must clearly identify AI responses.

Provider credentials stay on the server. Nutrition totals, payments, permissions, inventory, habit counts, and session allowances remain governed by application code. Meal estimation, workout planning and contextual coaching/summary adapters are implemented behind disabled configuration flags. No live provider credentials or real payment integration have been provisioned; fixture tests are distinct from live model evaluation.

Migration `008_ai_planning.sql` adds durable jobs, one pending request per customer, request deduplication, private context/output snapshots and bounded provider-call traces. Workers claim queued jobs with `SKIP LOCKED`, stop after at most one draft revision/five calls, and route interrupted leases to review without replaying paid stages. Atomic publication shares a transaction with `WorkoutService`, locks/rechecks profile/catalogue/current-plan state and records the new plan reference with the job outcome. The mobile app polls status; it cannot supply a plan or approve catalogue content. See [docs/AI_PLANNING.md](docs/AI_PLANNING.md).

## Contextual coaching

Migration `009_coaching.sql` adds owner-scoped chat/summary turns. Context reads use a repeatable-read snapshot to calculate seven-day workout, nutrition, habit and weight facts; AI commentary is stored separately from these statistics. A customer lock, unique pending index and request references bound calls and deduplicate retries. Clearing removes text/facts and preserves retry tombstones; late replies cannot restore cleared data. The provider has no mutation tools. Review flags are visible through the local operator queue, with trainer messaging/notifications still pending. See [docs/COACHING.md](docs/COACHING.md).

## Membership and billing foundation

Membership receipts/events are separate from period records and an append-only session-usage ledger. Per-customer transaction locks deduplicate receipts, serialize renewals and retain historical plan snapshots. Per-membership locks serialize session holds and deductions. The customer API is read-only for membership status; no client-declared payment or grant endpoint exists.

The local CLI/test fixture is explicitly unpaid, opt-in and development-only. Production reads/entitlements exclude development receipts. There is no real payment-provider adapter, webhook handler or checkout yet. Calendar-month/manual/no-rollover rules are provisional development behavior, pending client confirmation. The actual billing boundary must accept only independently verified provider events before production activation is implemented.

`requireEntitlement` now gates workout prescriptions and demonstration access; future AI features will use the same boundary. Profile/workout history remains readable after expiry. Membership validity is checked from server time.

## Workout and media boundary

Trusted publication checks exercise IDs, review status and prescription bounds, then atomically supersedes the previous plan while retaining historical logs. Workouts preserve exercise-definition snapshots. Owner-only progress uses row locks, revisions and idempotency references; an archived or future workout cannot receive a new log. The AI planner/judge adapter now shares this publication transaction after bounded checks; live configuration and trainer authoring UI remain pending.

Demonstrations are private local MP4/WebM assets, accessed through short-lived HMAC playback paths after membership checks. Every stream rechecks entitlement and confines real filesystem paths to the media root. Byte ranges/HEAD support seeking; files and signing keys are never served by the preview's public build server. Production needs a stable private signing key, persistent storage and HTTPS. Content import defaults to draft; explicit operator approval is distinct from technical test fixtures.

Flutter adds a Workouts tab, details/progress/history routes and a video player. Changing signed-in identity removes open private routes. Technical playback tests use generated clips and unique fixtures that are removed afterwards. Real exercise videos and Native Android/iOS playback remain unverified pending client assets/device setup.

## Habit tracking

Migration `004_habits.sql` adds customer-owned habits and unique habit/date entries. Membership entitlement gates writes; historical reads remain available after expiry. Owner checks and habit-row locks serialize checkmarks and archival. Unique customer creation references deduplicate retries, and a customer-row lock enforces the active limit. Read-only repeatable-read snapshots keep grids and computed totals consistent. Calendar boundaries use Asia/Kolkata; goal progress is calculated deterministically per eligible habit/month. Flutter reloads saved server state after mutations and does not simulate success offline. See [docs/HABITS.md](docs/HABITS.md).

## Nutrition tracking

Migration `005_nutrition.sql` stores private label/provider foods, immutable food snapshots in meal entries, revisioned changes/removal tombstones and dated targets. Calculations are deterministic per-100-g scaling; optional unknown nutrients remain null with completeness counts. Owner checks, membership writes, idempotency references, row locks and snapshot reads follow existing service boundaries. Target changes apply from today without rewriting prior days.

USDA requests run server-side with an optional `USDA_API_KEY`; missing configuration leaves label entry/saved foods usable. Import validates dataset type, nutrient IDs and units, preserving provenance and rejecting incomplete core nutrients. API keys are not returned or saved in provenance. Daily targets remain user-entered. See [docs/NUTRITION.md](docs/NUTRITION.md).

Migration `006_meal_estimates.sql` adds owner-scoped AI drafts and idempotent batch saves. Photo decoding, orientation correction, metadata removal and size limits precede the server-only Responses API call. Structured outputs are validated before an editable draft reaches Flutter. Saving requires explicit review, active membership and a transaction; immutable snapshots retain AI provenance. User locks enforce one pending attempt and a provisional daily budget. The service is disabled without an explicit flag, key and model. No live provider or accuracy evaluation has been performed. See [docs/MEAL_ESTIMATES.md](docs/MEAL_ESTIMATES.md).

## Body progress

Body progress migration `007_body_progress.sql` stores dated optional measurements, revisioned edit references and private normalized JPEG bytes. Customer locks and partial unique indexes enforce one active record per date and one photo per angle. List reads use a consistent database snapshot; image endpoints require the owner session on every request and disable caching. Historical reads and deletion remain available after membership expiry. Measurement and photo deletion clear active data while retaining limited retry tombstones. Flutter charts and comparisons use recorded values without AI analysis or inferred body metrics. See [docs/BODY_PROGRESS.md](docs/BODY_PROGRESS.md). Production storage/backup retention and trainer consent-controlled review remain follow-up work.

## Staff operations

Staff migration `010_staff_operations.sql` adds review state, customer-visible feedback events and assignment/provisioning audits. Review writes serialize on the customer, recheck live consent/assignment and use revisions/request references. Trainer publication shares the workout transaction and verifies the previously observed current-plan ID, preventing stale schedule replacement. Mobile feedback reads stay owner-scoped after expiry; clearing coaching also clears related feedback text. The Next.js route enforces a fixed upstream/action allowlist, a bounded JSON body and exact mutation Origin, with Secure cookies in production. See [docs/STAFF_OPERATIONS.md](docs/STAFF_OPERATIONS.md).

## Session reservations

Migrations `011_sessions.sql` and `012_session_environments.sql` add nullable owner-confirmed rules, trainer availability, customer bookings with policy snapshots, attendance audit fields and operation deduplication. Trainer advisory locks plus customer/membership row locks prevent overlap and overspending; a unique slot index and booking-ledger reference enforce single reservation/consumption. Available credits subtract both consumed ledger entries and held bookings. Staff withdrawal releases a hold without penalty; attendance outcomes and late cancellations follow the saved terms. Production excludes development slots and receipts. Flutter exposes Today → Live coaching sessions; the staff dashboard exposes `/sessions` through its existing cookie boundary.

Booking requires confirmed rules, an explicit server activation flag and a configured video adapter. The current adapter reports unconfigured and always refuses video joining; rooms, provider tokens and native call UI are pending. No proposed cancellation terms are saved to the real development policy. Tests confirm technical rules only in temporary database schemas. See [docs/SESSIONS.md](docs/SESSIONS.md).

## Platform strategy

Android and iOS use one Dart application, plus their generated native projects and platform-specific permissions. A web target allows review on this Linux workstation. The Android SDK is installed; macOS/iOS build access is still pending. The web target is a development preview of the mobile code, not an additional committed customer web product.

## Configuration

API: `DATABASE_URL`, `PORT`, `HOST`, `CORS_ORIGINS`. Dashboard: server-side `API_URL`. Mobile: compile-time public `API_BASE_URL`. Commit templates only, never credentials. iOS Keychain entitlements are configured but unverified until a macOS build. Android SDK licences were accepted by the user and the toolchain installed; scripts use project-local SDK/JDK paths without changing the system's Java installation. Gradle uses a 2 GiB heap and two workers to fit the development machine.
