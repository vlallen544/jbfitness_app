# JB Fitness

Mobile customer app for iOS and Android, with a separate trainer/admin dashboard and API.

Free hosted demo: [dashboard](https://jbfitness-app-1.onrender.com), [API health](https://jbfitness-app.onrender.com/api/v1/health), [setup guide](docs/FREE_DEMO_DEPLOYMENT.md) and [Render Blueprint](render.yaml). The API/dashboard use Render Free and the database uses Supabase Free. The published APK below remains the offline sample preview. Live AI, private object storage and other providers need separate integration.

## Current milestone

New: [redesigned staff workspace](docs/previews/staff-trainer-inbox.png) and [animated mobile intro](docs/previews/fitness-intro.gif). The intro can be skipped and respects reduced-motion settings. Read the [feature and verification notes](docs/WORKSPACE_AND_INTRO.md).

[Download the smaller preview ZIP (78 MiB)](https://github.com/vlallen544/jbfitness_app/releases/download/v0.1.2-preview.1/JB_Fitness_Client_Preview.zip) · [Direct APK](https://github.com/vlallen544/jbfitness_app/releases/download/v0.1.2-preview.1/JB_Fitness_Client_Preview.apk) · [Release and installation files](https://github.com/vlallen544/jbfitness_app/releases/tag/v0.1.2-preview.1)

Extract the ZIP, then open `JB_Fitness_Client_Preview.apk` on an Android phone. The ZIP contains the same signature-verified APK with a smaller download size.

The Android client-preview APK is built and signature/checksum verified. This offline demo opens a sample customer account and labels sample data on every screen; it needs no API server or real credentials. Generate the local `artifacts/client-preview/` handover folder with `bash scripts/build-client-preview.sh`; it contains the APK, installation instructions, package details and SHA-256 checksums. Generated APKs and handover files are excluded from Git. Physical-phone testing remains pending. See [client preview instructions](docs/CLIENT_PREVIEW.md) and [phone screenshot](docs/previews/red-theme-today.png).

Working email/password accounts, fitness-profile onboarding/editing, secure sessions and PostgreSQL persistence are now joined by membership tracking: current/next periods, expiry, history, inherited entitlements and session balances. Customer records are isolated; assigned trainers need customer sharing consent. Today now uses saved customer habits, with monthly targets, weekly/monthly grids and retained history. Checkout, real payment verification, live AI, video calls, store fulfilment, email verification and password recovery are not connected. Use test details in this local development environment.

See [BUILD_PLAN.md](BUILD_PLAN.md) for the ordered delivery milestones and [PRD.md](PRD.md) for requirements.

Milestone 4 adds weekly workout schedules, exercise prescriptions/instructions, completion/feedback, saved history, versioned routines and private demonstration playback. Use the new Workouts tab or Today → Open workouts. Real client demonstration assets and AI-generated personalized routines are still pending; local sample routines are labelled development content. See [docs/WORKOUTS.md](docs/WORKOUTS.md) for imports, fixtures and endpoints.

The mobile app uses a red, white-background and black theme throughout: red actions/selections, black headlines and summary cards, neutral borders and a matching Android JB icon. Version 0.1.1 includes this palette in the connected app and offline preview. Read the [design direction](docs/DESIGN_DIRECTION.md). Phone previews from the actual offline app: [Today](docs/previews/red-theme-today.png), [workouts](docs/previews/red-theme-workouts.png), [plans](docs/previews/red-theme-plans.png), [profile](docs/previews/red-theme-profile.png), [habits](docs/previews/red-theme-habits.png), [nutrition](docs/previews/red-theme-nutrition.png) and [progress](docs/previews/red-theme-progress.png). Records are labelled samples; older screenshot groups document earlier design passes.

The workout detail pass adds session progress, numbered exercise cards, clearer instruction/video states, phone-friendly actual-performance fields and a saved-completion confirmation. Existing API behavior and archived/future-session restrictions are preserved. Real demonstration content and native device playback verification remain pending.

Workout preview screenshots: [session details](docs/previews/redesign-workout-details.png), [missing demonstration](docs/previews/redesign-exercise-video.png), [saved completion](docs/previews/redesign-workout-completed.png). Browser visual checks use sample responses; 19 Flutter checks and static analysis pass, and the web build succeeds.

Membership and profile refinement adds separate active/queued membership summaries, a session-balance bar, clearer monthly plan cards and grouped profile sections with independent consent controls. See [membership](docs/previews/redesign-membership.png), [plan comparison](docs/previews/redesign-plan-comparison.png), [profile](docs/previews/redesign-profile.png) and [consent controls](docs/previews/redesign-profile-consent.png). Current verification: 21 passing Flutter checks, clean analysis, successful web build, and browser sample-response checks through a profile save. Native device checks, real checkout and upcoming AI services remain pending.

## Structure

Food diary: **Today → Open food diary → Log a food**. Use a saved food, enter label values per 100 g, or search USDA when the backend key is configured. Save decimal gram quantities under breakfast/lunch/dinner/snacks, edit/remove entries, and set dated reference targets. Missing optional nutrients remain unknown. See [docs/NUTRITION.md](docs/NUTRITION.md). Live USDA search/detail mapping was separately checked with the public demo key; no client key was provisioned.

**Estimate from photo or text** adds approximate meal recognition: upload/capture a dish or describe it, review assumptions and editable portions/nutrients, then explicitly save to the diary. Saved entries and daily totals retain AI estimate labels. The server adapter is built but disabled until `ENABLE_MEAL_AI`, `OPENAI_API_KEY` and a compatible `MEAL_AI_MODEL` are configured. No live AI accuracy evaluation has been performed. See [docs/MEAL_ESTIMATES.md](docs/MEAL_ESTIMATES.md) for configuration, privacy, usage limits and verification.

Body progress: **Today → View body progress**. Save dated weight/measurements, view trends, select two dates to compare and add private front/side/back photos. Every photo read requires the owner's session; photos are not sent to AI. History and deletion remain available after expiry. See [docs/BODY_PROGRESS.md](docs/BODY_PROGRESS.md) for storage, limits and native verification still pending.

AI workout planning: **Workouts → Plan with AI**. A durable job reviews the saved routine, drafts from approved matching exercises, runs application checks and an AI judgment, and allows one revision before publication or a persistent review-needed result. The mobile app polls status and opens the published training dates. Live use needs explicit server flags/models, client exercise content and a quality pilot. No real provider calls were made during implementation. See [docs/AI_PLANNING.md](docs/AI_PLANNING.md).

AI coaching: **Today → Open AI coach**. Ask workout/nutrition questions, request a seven-day summary and review saved conversations. Backend-calculated tracking facts stay separate from AI commentary; unknown days and AI food estimates remain labelled. Replies are advisory and cannot mutate plans or targets. Coaching is disabled until its separate server flag/model is configured. See [docs/COACHING.md](docs/COACHING.md) for context limits, retries, quotas, clearing and pending trainer integration.

Staff operations: open the dashboard at `http://localhost:3000` with a provisioned trainer/admin account. Admins assign customers; trainers review shared AI escalations, save customer-visible feedback and explicitly publish a reviewed workout. Profile sharing and coaching-review sharing are separate opt-ins. Customers read notes under **Today → Trainer feedback**. Progress photos remain private. See [docs/STAFF_OPERATIONS.md](docs/STAFF_OPERATIONS.md) for setup, access rules and isolated dashboard tests. The public catalogue moved to `/plans`.

The staff dashboard now uses a redesigned red/white/black coaching workspace: dark navigation rail, illustrated overview, four record-based metrics, customer cards and a review-workload panel. The mobile app adds a skippable animated fitness intro. See [workspace and intro notes](docs/WORKSPACE_AND_INTRO.md). Staff previews: [sign-in](docs/previews/staff-login.png), [assignments](docs/previews/staff-assignments.png), [trainer inbox](docs/previews/staff-trainer-inbox.png), [workout review](docs/previews/staff-workout-review.png), [phone layout](docs/previews/staff-mobile-inbox.png). The browser walkthrough uses actual local services with isolated technical fixtures, verifies feedback delivery and a single trainer-plan publication, then removes its temporary database schema.

Coaching previews: [recorded week](docs/previews/coaching-recorded-week.png), [chat](docs/previews/coaching-chat.png), [summary](docs/previews/coaching-summary.png). Browser QA uses fixture responses and verifies explicit requests, accessible reply text, saved summary facts and confirmed clearing without deleting tracking records.

Planning previews: [introduction](docs/previews/ai-planning-intro.png), [review](docs/previews/ai-planning-review.png), [published result](docs/previews/ai-planning-published.png), [workout version](docs/previews/ai-planning-workouts.png). Browser QA verifies a single submission, polled status and published navigation using fixture responses.

Progress previews: [chart](docs/previews/progress-chart.png), [measurements](docs/previews/progress-measurements.png), [private photo](docs/previews/progress-private-photo.png). Browser QA uses fixture values and solid-color technical images to verify edits, actual file selection, explicit uploading and authenticated photo display.

Nutrition previews: [daily summary](docs/previews/nutrition-daily-summary.png), [food picker](docs/previews/nutrition-food-picker.png), [gram portion](docs/previews/nutrition-portion.png), [meal log](docs/previews/nutrition-meals.png). A browser check with sample responses verifies navigation, choosing a food, entering 150 g, submitting a saved meal and the resulting 600 kcal total. Database-backed tests separately verify real calculations and persistence.

Meal estimate previews: [input](docs/previews/meal-estimate-input.png), [editable review](docs/previews/meal-estimate-review.png), [saved diary](docs/previews/meal-estimate-diary.png). Browser QA selects an actual generated technical image and uses fixture responses; it verifies explicit saving and a portion edit from 395 to 460 kcal, not recognition accuracy.

Session reservations add **Today → Live coaching sessions** and a staff **Session calendar** at `/sessions`. The software handles trainer availability, held/used/available credits, booking confirmation, saved cancellation rules, staff withdrawal and audited manual attendance. Actual client rules and the video service are unconfigured, so new customer bookings remain disabled. See [docs/SESSIONS.md](docs/SESSIONS.md) and the [owner rules](docs/previews/sessions-owner-rules.png), [trainer calendar](docs/previews/sessions-trainer-calendar.png) and [phone layout](docs/previews/sessions-mobile-calendar.png) previews. Browser walkthrough rules are temporary technical fixtures.

Current verification: 111 API integration checks, 9 dashboard boundary/provisioning checks and 66 Flutter tests pass, with clean Flutter analysis and successful API, admin-dashboard, Flutter web and offline Android debug APK builds. APK signature and checksum checks pass. Physical-device testing, iOS builds and live AI evaluation remain pending.

Saved habits: **Today → Add habit / View tracking**. An active membership enables writes; expired members can read their own history. New accounts start with an empty checklist. See [docs/HABITS.md](docs/HABITS.md) for date, target, archival and concurrency rules. Verification: 38 database integration checks and 24 Flutter tests pass; Flutter analysis and API compilation are clean.

Habit previews: [monthly summary](docs/previews/habits-monthly-summary.png), [monthly grid](docs/previews/habits-monthly-grid.png), [weekly grid](docs/previews/habits-weekly-grid.png). Browser fixtures are sample responses; database tests separately verify real persistence and access control.

```
apps/mobile/   Flutter iOS/Android app (web target for development previews)
apps/api/      NestJS backend, port 3001
apps/admin/    Next.js operations dashboard, port 3000
infra/         Isolated PostgreSQL Compose service, port 55432
```

## Start API and dashboard

From the project root, install dependencies and initialize the local database:

```sh
npm ci
npm run setup:db
npm run db:up
npm run db:migrate
```

The setup command generates private credentials without printing them, and preserves existing configuration. Docker may need appropriate access on this machine. Database records live in the `jbfitness_database` volume; stopping the container preserves them. Then use separate terminals:

```sh
npm run dev:api
npm run dev:admin
```

Dashboard: http://localhost:3000

After building the Flutter web preview, run `npm run dev:mobile` and open http://localhost:8080. Keep the API running for membership data. The server binds only to the local machine and serves only the generated Flutter build directory.

Endpoints:

- `GET http://127.0.0.1:3001/api/v1/health`
- `GET http://127.0.0.1:3001/api/v1/plans`
- `POST /api/v1/auth/register` — email, password (12–128 characters), displayName; creates a customer only.
- `POST /api/v1/auth/login` — email/password; returns a session and saved profile.
- `GET /api/v1/auth/me` — restore the signed-in user and profile.
- `POST /api/v1/auth/logout` — revoke the current session.
- `GET /api/v1/me/profile` and `PUT /api/v1/me/profile` — customer-owned profile.
- `GET /api/v1/coach/customers/:id/profile` — assigned trainer only, with customer sharing consent.
- `GET /api/v1/me/membership` — customer-owned dates, status, history, effective entitlements, and completed-session balance.
- `GET/POST /api/v1/me/habits` — customer-owned monthly history / create a habit.
- `PUT /api/v1/me/habits/:id/days/:date` — save a daily checkmark.
- `PUT /api/v1/me/habits/:id/archive` — retain history and stop tracking a habit.
- `GET /api/v1/me/nutrition?date=YYYY-MM-DD` — private diary, nutrient totals and dated targets.
- `GET/POST /api/v1/me/nutrition/foods` — find saved foods / save label values.
- `POST /api/v1/me/nutrition/foods/usda/:fdcId` — import a provider food when configured.
- `POST /api/v1/me/nutrition/entries` and `PUT /api/v1/me/nutrition/entries/:id` — log/edit/remove a portion.
- `PUT /api/v1/me/nutrition/targets` — save reference targets from today.
- `GET /api/v1/me/meal-estimates/status` — configuration, entitlement and remaining attempts.
- `POST /api/v1/me/meal-estimates` — photo/text analysis draft, without creating diary entries.
- `POST /api/v1/me/meal-estimates/:id/save` — explicitly save reviewed estimated foods.
- `GET/POST /api/v1/me/progress` — history / create dated measurements.
- `PUT /api/v1/me/progress/:id` and `PUT /api/v1/me/progress/:id/delete` — versioned edit / delete a record with its photos.
- `POST /api/v1/me/progress/:id/photos` — explicitly upload a private progress photo.
- `GET/DELETE /api/v1/me/progress/photos/:id` — owner-authenticated photo bytes / deletion.
- `GET /api/v1/me/ai-planning/status` — readiness, quota and latest planning result.
- `POST /api/v1/me/ai-planning` — enqueue/replay a request reference; the server supplies context and content.
- `GET /api/v1/me/ai-planning/:id` — owner-only job status and published plan reference.
- `GET /api/v1/me/coaching` and `GET /api/v1/me/coaching/:id` — private paginated conversation / turn status.
- `GET /api/v1/me/coaching/facts` — application-calculated last-seven-days facts.
- `POST /api/v1/me/coaching` — explicit chat or summary request with duplicate protection.
- `DELETE /api/v1/me/coaching` — clear private coaching text/snapshots and retain retry tombstones.

Protected API endpoints require `Authorization: Bearer <session token>`. Passwords are never returned, and the database stores hashes of session tokens. Sessions currently expire after seven days. The dashboard keeps its token in a server-set HttpOnly cookie and forwards only allowlisted operations. Admins manage assignments; trainer review access requires the current assignment and separate customer consent.

Environment templates are in each JavaScript app's `.env.example`. The API requires `DATABASE_URL`; `npm run setup:db` supplies it in an ignored `apps/api/.env`. API files load from `apps/api` through the workspace scripts. Admin `API_URL` is server-side. No paid services, AI keys, or SMS provider are needed for this milestone.

The API binds loopback by default. For physical-device testing, set API `HOST=0.0.0.0` only on a trusted development network and use the machine's LAN IP. This development configuration is not a public production deployment.

## Flutter development

The local SDK setup uses `/home/allen/.local/share/jbfitness-tools/flutter/bin/flutter`. Substitute your Flutter executable on another machine.

Verified tooling: Flutter 3.47.9 / Dart 3.13.7, project-local Java 21, Android platform/build-tools 36 and NDK 28.2.13676358. The user accepted the SDK licence and the Android toolchain passes Flutter Doctor. The offline debug APK builds for arm64-v8a, armeabi-v7a and x86_64, with verified APK v2 signing and a JB launcher icon. iOS remains unbuilt pending macOS/Xcode access. The temporary application identifier is `com.jbfitness.jbfitness`; confirm client ownership before store registration.

After agreeing to [Google's SDK terms](https://developer.android.com/studio#terms-and-conditions), `bash scripts/setup-android.sh --accept-sdk-license` downloads the pinned/checksummed command-line tools and installs the platform/build tools/NDK required by this Flutter version. Without that flag it prints the review instructions and exits. `scripts/mobile.sh` discovers the project-local JDK/SDK without changing global Java or shell configuration.

From the repository root, `bash scripts/mobile.sh <flutter arguments>` uses that SDK and runs inside the mobile project. Override `JB_FLUTTER_BIN` if Flutter is installed elsewhere.

From `apps/mobile`:

```sh
flutter pub get
flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:3001/api/v1
```

For a web preview, include `http://localhost:8080` (or the exact served origin) in API `CORS_ORIGINS`. Android emulator API URL: `http://10.0.2.2:3001/api/v1`. A physical phone needs the development machine's reachable LAN IP. Use `--dart-define=API_BASE_URL=...` with `flutter run`. This is a public backend URL, not a secret.

Android and iOS targets share the same Dart source. The debug client-preview APK is available; a production Android release still needs release signing, connected-service configuration and physical-device verification. iOS build/testing requires macOS/Xcode and appropriate signing access. Development cleartext networking, where configured, must remain debug-only; production integrations will use HTTPS.

## Checks

```sh
npm test
npm run test:integration
npm run build
cd apps/mobile
flutter analyze
flutter test
flutter build web
```

Foundation verification completed: API compilation and plan-contract test, live HTTP health/catalogue checks, dashboard production build and rendered prices, mobile-preview CORS, Flutter analysis, checklist/navigation interaction test, and Flutter web release build. Dashboard and phone-sized screenshots are in `docs/previews/`.

Account verification: 8 PostgreSQL-backed integration checks cover credential hashing, strict input, consent, ownership isolation, trainer permissions, restart persistence, expired/revoked sessions, and throttling. Six Flutter tests cover session errors, logout, onboarding, editing and navigation. Real-browser checks also exercise the actual secure-storage plugin across login, reload, profile display and logout. Browser QA creates and deletes only its own uniquely identified test account.

To repeat browser QA, start a separate headless Chromium with remote debugging on port 9234, run the API and mobile preview, then execute `node --env-file=apps/api/.env scripts/browser-account-smoke.mjs`. The browser test takes screenshots in `docs/previews/` and does not print credentials or tokens.

Native Android/iOS builds and device secure-storage behavior are unverified. iOS Keychain entitlements are configured for a future signed build. Before public launch, connect email verification/recovery, complete privacy/deletion controls and production deployment settings, and move rate limiting to infrastructure suitable for multiple server instances.

Membership verification adds database tests for idempotent/concurrent development receipts, renewals, expiry, inherited benefits, session limits, ownership and production exclusion. There are now 20 backend integration checks, 2 catalogue/calendar-month unit checks, and 11 Flutter tests. Checkout remains disabled; no fixture is represented as an actual payment.

See [docs/BILLING.md](docs/BILLING.md) for the opt-in test-grant command and pending provider setup. `node --env-file=apps/api/.env scripts/browser-account-smoke.mjs --membership` additionally exercises a temporary unpaid Premium fixture and captures the live membership screen; it requires the same isolated QA browser/API/preview setup as the account check.

## Membership contract

Amounts are integer paise: 300000 / 1000000 / 2000000, each for one month. Total live video allowances are 0 / 10 / 25; Premium Plus does not receive 35 sessions. Higher tiers inherit lower-tier features. Audio calls are deferred. Exact expiry/renewal and coaching scheduling policies remain open.

The workout milestone brings verification to 32 PostgreSQL-backed integration checks, 4 unit checks, and 17 Flutter tests. The optional `--workout` browser QA adds actual protected technical-video playback, saved completion/history and route privacy checks. The resolved dependency lock targets Dart 3.13 / Flutter 3.47 or newer; this workstation uses Flutter 3.47.9.

Development fixtures provisionally use a clamped calendar month and manual renewal. Early renewal of the same plan starts after the existing period without resetting its session balance. Test grants require `ENABLE_DEV_MEMBERSHIPS=true` on the local CLI, collect no money, and cannot grant paid access when `NODE_ENV=production`. They do not provide a real payment verification integration.
