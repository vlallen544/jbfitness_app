# JB Fitness — Build Execution Plan

Complete and demonstrate one milestone at a time. Dates remain uncommitted until budget and integration decisions are resolved.

## Confirmed rules

- iOS/Android Flutter app; trainer/admin web dashboard.
- One-month plans: Normal ₹3,000, Premium ₹10,000 with 10 total live video sessions, Premium Plus ₹20,000 with 25 total sessions.
- Higher plans inherit lower-tier features. Stored demonstration videos are included from Normal upward.
- Routine chat/workout coaching uses AI orchestration with selective trainer escalation. Audio calls are deferred.

## 1. Foundation — complete for shared-code preview

- [x] Install Flutter and validate available build targets (Android SDK is now installed; iOS needs macOS).
- [x] Initialize Git, configuration templates, and repository structure.
- [x] Build customer app shell: Today, membership, and profile entry points.
- [x] Build NestJS API: health and read-only plan catalogue.
- [x] Build Next.js dashboard connected to the plan catalogue.
- [x] Validate dashboard production build, API HTTP contract, mobile analysis, navigation/checklist test, and Flutter web build. Inspect dashboard and phone-sized preview screenshots.

Deliverable: runnable development foundation with clearly marked preview states. No customer accounts, purchases, or live AI yet.

Verified: Flutter 3.47.9 / Dart 3.13.7; API build/test and HTTP checks pass; Next.js production build passes; Flutter analysis/test/web build pass. The offline Android debug APK now builds and passes signature/checksum checks. Physical Android testing and iOS builds remain pending. See README for run commands.

## 2. Onboarding and persistence — account flow implemented; native setup pending

- [x] Use email/password for local development; normalize emails, hash passwords, validate input, and limit login attempts.
- [x] Run isolated PostgreSQL with a persistent volume and versioned account/profile/session migrations.
- [x] Implement registration, login, session restoration, logout/revocation, and customer-owned profile read/update.
- [x] Build onboarding/editing for goals, current routine, equipment, availability, diet/allergy notes, and limitations.
- [x] Store session tokens through the secure-storage plugin; do not persist passwords or health profiles on the device.
- [x] Implement customer/trainer/admin role storage; trainer reads require an assignment and customer sharing consent. Trainer assignment UI remains in milestone 7.
- [x] Verify 8 backend integration checks, 6 Flutter tests, clean analysis, a web build, and real-browser login/reload/profile/logout.
- [x] Install the project-local Android SDK/platform/build-tools/NDK after the user's SDK-licence acceptance; validate the Android toolchain with Java 21.
- [x] Build the offline client-preview APK, verify APK v2 signing, package metadata, all three ABIs and SHA-256 checksum; include client installation instructions.
- [ ] Check APK installation and the sample flows on a physical Android phone.
- [ ] Verify iOS builds and Keychain integration on macOS/Xcode.
- [x] Prepare and build a separate offline client-preview entry point with a persistent sample-data banner, no network transport, sample screens and temporary habit/workout/profile edits.
- [x] Apply the requested red/white-background/black mobile theme, replace hard-coded green tints, update the Android JB icon and build version 0.1.1/code 2 with verified APK/ZIP packaging. Validate all 63 Flutter tests, clean analysis and phone screenshots.

Launch follow-up: email verification, password recovery, production authentication/rate-limit hardening, and account data-deletion flow. These are not implemented or presented as ready.

Android tools are installed after licence acceptance. The verified client APK is in `artifacts/client-preview/`; physical Android installation remains unverified. Arrange iOS build access early for native checks; store signing remains a release task.

Deliverable: customer signs up, saves a profile, signs back in, and accesses only their own records.

## 3. Membership and payments — membership foundation implemented; provider integration pending

- [x] Persist membership periods, historical plan snapshots, receipt/event deduplication, and the completed-video-session ledger.
- [x] Expose customer-owned membership status, current/next dates, history, inherited benefits, and 0/10/25 total session balances.
- [x] Add mobile active/expired/empty/error states, disabled checkout, refresh and app-resume refresh.
- [x] Refine active/queued membership summaries and plan comparison; verify enlarged-text layout, zero-session allowances and inherited 0/10/25 totals.
- [x] Add opt-in local development fixtures, clearly marked unpaid and excluded from production access. These are not a payment-provider sandbox.
- [x] Verify concurrent duplicate grants/completions, early renewals, expiry, restart persistence, ownership and production exclusion in database tests.
- [ ] Confirm calendar-month versus 30-day expiry and manual versus automatic renewal. Calendar-month/manual behavior is provisional for development fixtures only.
- [ ] Confirm refund, cancellation, session carry-forward and upgrade/downgrade rules, and digital/coaching purchase packaging.
- [ ] Configure a real billing provider/store products and implement server-side verification, receipt/webhook adapters and provider sandbox tests.

See docs/BILLING.md for the development model and open integration work. Session booking/reservation rules and trusted call-completion handlers remain in milestone 7.

Target completion: provider-verified sandbox purchases activate the correct benefits, and duplicate deliveries cannot duplicate entitlements. The membership engine is ready for this adapter; actual checkout and charging remain disabled.

## 4. Workouts and video library — software implemented; client content pending

- [x] Add versioned plans, weekly schedules, prescribed exercise snapshots and customer-owned progress/history.
- [x] Build workout list/detail screens, instructions, sets/repetitions/load/rest, actual-performance feedback, completion/skipping and history.
- [x] Apply the shared mobile design to workout details, instruction/video states and completion confirmation; verify exercise logging at 320 px with enlarged text.
- [x] Protect progress with owner checks, revisions, idempotent save references and archived/future-session rules.
- [x] Add private MP4/WebM storage attachment, short-lived signed playback, seeking/ranges, membership checks and missing-media states.
- [x] Add draft/approved catalogue import and explicitly unpaid/unreviewed local schedule fixtures.
- [ ] Supply and review the client's real exercise definitions and demonstration videos.
- [x] Connect the bounded AI planning/review adapter to versioned workout publication, behind explicit provider configuration. Development sample schedules remain labelled fixtures.
- [ ] Add trainer authoring and review resolution in the trainer milestone.
- [ ] Verify Android/iOS builds and playback on real devices when native tooling is available.

See docs/WORKOUTS.md for endpoints, content import and technical-playback QA. Calendar eligibility currently uses Asia/Kolkata; individual timezone configuration remains a later extension.

Software deliverable: a member follows, records and reviews an assigned workout, with private playback of supplied media. Launch content remains pending client assets and review.

## 5. Daily tracking

- [x] Persist customer-owned habits, date check-ins, monthly targets and archival history.
- [x] Replace the sample Today checklist; add weekly/monthly grids and daily progress bars.
- [x] Enforce membership writes with historical reads after expiry, date bounds, ownership and retry-safe saves.
- [x] Build gram-based meal logging, source-labelled foods, daily nutrients, dated user targets and private saved history.
- [x] Implement USDA search/detail normalization and verify it with the public demo API; provide food-label entry without a provider key.
- [ ] Configure the client's server-side USDA key and assess food coverage for the client, including Indian dishes.
- [x] Build AI meal estimates from an uploaded photo, typed dish description, or both: show assumptions, allow corrections, and save only after review. Provider transport is tested with fixtures; live activation remains pending.
- [x] Label estimated food entries and daily totals so AI estimates remain distinguishable from food-label/database values.
- [ ] Configure the client's server-side AI key and compatible vision/structured-output model; evaluate real dishes, cost and latency before enabling members. Confirm the provisional 10-attempt daily limit.
- [ ] Verify camera/gallery uploads on physical Android and iOS devices.
- [x] Build customer-owned dated measurements, private front/side/back photos, charts and two-date comparisons, with explicit uploads and deletion controls.
- [ ] Verify progress photo camera/gallery access on Android/iOS devices; review production storage, backups and retention before launch.
- [ ] Add configurable schedules, streaks and individual customer timezones if required by the next tracking scope.

See [docs/HABITS.md](docs/HABITS.md), [docs/NUTRITION.md](docs/NUTRITION.md) and [docs/BODY_PROGRESS.md](docs/BODY_PROGRESS.md) for calendar, target, persistence, food-source, private-photo and concurrency rules.

Frontend refinement is complete for Today, sign-in, workout details, membership comparison and profile sections. Flutter remains the customer framework. See [design direction and reference notes](docs/DESIGN_DIRECTION.md). The Today checklist now uses persistent habits.

The session availability, reservation, cancellation and manual attendance foundation is implemented in milestone 7. Actual client booking rules and the video provider remain unconfigured, so customer booking is disabled. The AI features still need live configuration and quality evaluation. Native verification, meal accuracy evaluation and client content remain pending. USDA search needs the client's backend key. Streaks and configurable habit schedules remain follow-up work.

Deliverable: daily records survive restart and agree with charts/totals.

## 6. AI coaching orchestration

- [x] Build durable customer-owned planning jobs, quota checks, duplicate-safe admission and status recovery.
- [x] Implement routine review → workout draft → application checks + AI judgment → one revision → atomic publication or persistent review-needed result.
- [x] Connect a mobile planning/status screen and navigate to the published training dates; retain existing workout logs.
- [x] Add a local operator review-queue command. Trainer inbox/resolution remains in milestone 7.
- [ ] Configure the client-owned AI key/models, approved content and usage budgets; pilot representative profiles with the trainer before live activation.
- [x] Add private contextual coaching chat, general meal ideas and user-requested seven-day progress summaries, with bounded context, application-calculated facts, quotas, retry protection and clearing.
- [ ] Evaluate live coaching/planning output quality and safety with representative client cases; automatic summaries/notifications and activity-driven replanning remain later extensions.
- [ ] Verify physical iOS/Android behavior and complete production privacy/retention controls.

See [docs/AI_PLANNING.md](docs/AI_PLANNING.md) for the workflow, provider configuration, product limits, queue recovery and remaining work.

See [docs/COACHING.md](docs/COACHING.md) for private chat, summary snapshots, context boundaries, quotas and deletion.

Deliverable: representative profiles yield valid versioned plans; repeated failures escalate rather than loop indefinitely.

## 7. Trainer and live video

- [x] Add staff sign-in with server-side cookie sessions and role/Origin checks.
- [x] Add admin customer/trainer directory, assignment/removal and audit events.
- [x] Add an assigned-trainer review inbox for flagged AI requests, with separate customer consent for coaching review.
- [x] Add revisioned, duplicate-safe customer-visible feedback and explicit reviewed-plan publication.
- [x] Add mobile trainer-feedback history, reviewed-week navigation and coaching-sharing controls.
- [x] Add explicitly confirmed owner policy forms and trainer availability calendars, without pre-accepting client rules.
- [x] Add membership-bound reservations, held/used/available balances, saved cancellation terms and duplicate-safe cancellation.
- [x] Add staff withdrawal and audited manual attendance outcomes, with 0/10/25 allowance enforcement and development/production separation.
- [x] Add mobile session history/confirmation and verify concurrency, retries, access boundaries and narrow layouts.
- [ ] Confirm call duration, booking lead time, cancellation/no-show and carry-forward rules.
- [ ] Choose/configure the video provider; implement real rooms/tokens, mobile call UI and trusted completion reconciliation. Booking remains disabled until provider and actual rules are configured.
- [ ] Add live trainer messaging and notifications; verify on physical devices and complete production staff/security setup.

See [docs/STAFF_OPERATIONS.md](docs/STAFF_OPERATIONS.md) for access rules, local provisioning and verification.

See [docs/SESSIONS.md](docs/SESSIONS.md) for reservations, policy snapshots, credit accounting and the disconnected video boundary.

Deliverable: eligible members complete calls against the correct monthly allowance.

## 8. Store and business operations

Confirm delivery areas, shipping fees, stock responsibility and return policies. Build products/cart/checkout/orders/inventory, reminders, admin reports and operational controls.

Deliverable: owner fulfils paid test orders and manages memberships/coaching from the dashboard.

## 9. Device pilot and release

Arrange macOS/Xcode access and physical iPhone tests; validate Android tools/devices. Configure client-owned store/production accounts, test billing/access/offline/uploads, run pilot and prepare submissions.

Deliverable: approved iOS/Android releases and monitoring/support ownership.

## Remaining decisions

Login method, exact month-expiry/renewal rules, session duration/cancellation, AI usage limits, trainer handoff policy, food/provider licensing, delivery/refunds, budget and launch date. These do not block the foundation milestone.
