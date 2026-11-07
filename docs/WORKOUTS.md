# Workouts and stored exercise videos

## Implemented experience

Customers with an active membership can open a weekly schedule, move between weeks, inspect exercise instructions/sets/repetitions/load/rest in seconds, request a stored demonstration, and record progress. Logging supports completed exercise checkmarks, optional actual sets/repetitions/weight/difficulty/notes, session feedback, completed/skipped/in-progress status, and saved history.

Workout history remains readable after membership expiry; the current history view lists the most recent 50 saved sessions. Detailed paid schedules and video access require an active entitlement. All three plan tiers inherit those entitlements. The Today habits remain the earlier in-memory preview until milestone 5.

## Data and write rules

The schema separates exercises, versioned plans, scheduled sessions, prescribed items with immutable exercise snapshots, and customer-owned progress. Publishing a new version archives the old plan, preserving its logs. Archived plans cannot receive new edits. A trusted publication service validates structural limits and exercise review status; customer HTTP requests cannot publish a routine.

Progress writes require the current revision and a UUID save reference. Exact retries return the original result; changed reuse and stale-device edits return 409. A completed session requires all planned exercises to be marked complete. Future sessions cannot be logged early. Calendar dates currently use Asia/Kolkata for server logging eligibility; customer-specific calendar/timezone settings remain a later extension. Exercise-specific medical suitability and AI personalization are not implemented by these structural checks.

## Private demonstration playback

`GET /api/v1/me/exercises/:id/video` checks membership and content visibility, then returns a five-minute signed playback path. MP4/WebM files live outside the publicly served web build. The stream checks the signature, expiry, current membership, review status and real filesystem location. Range/suffix/HEAD support permits seeking; invalid ranges return 416. Path traversal and symlinks outside the media root are rejected.

Flutter uses the official `video_player` plugin with play/pause, seeking, loading/error/retry states, and proper disposal when leaving the screen. It does not autoplay. Missing files display an explicit message. The playback link is a short-lived bearer link; protect it like other access URLs. Playback links also stop working after a development API restart unless a stable signing key is configured; Retry requests a new one.

## Bring in client content

No client-approved exercise videos have been supplied. No AI video generator or AI workout orchestration is connected. Development sample routines are clearly labelled and excluded from production. Do not treat them as personalized coaching or approved launch content.

An owner/operator can import an exercise JSON with `id`, `name`, `muscleGroup`, `equipment` (array of strings), and `instructions` (array of strings):

```sh
npm run catalogue:import --workspace @jbfitness/api -- --file /path/exercise.json
```

This creates/updates a draft, preserving any stored media. After client/trainer review, repeat with `--approved` to explicitly attest review. Updating a definition without that flag returns it to draft. Catalogue authoring/review UI and audit administration are later dashboard work.

Attach the corresponding reviewed local video:

```sh
npm run media:attach --workspace @jbfitness/api -- --exercise exercise-id --file /path/demonstration.mp4
```

The attachment command accepts MP4/WebM with matching file headers, up to 250 MB. It copies the file under a generated private key; it preserves the original file and the exercise's review status. It does not transcode or certify the instructions/video. Previous private copies remain for operator-managed retention rather than being deleted automatically. Check the client media's actual device/browser codec compatibility before launch.

Configuration: optional `EXERCISE_MEDIA_ROOT` (default `apps/api/private-media`); production requires `MEDIA_SIGNING_KEY` with at least 32 private random characters. Configure HTTPS and persistent private media storage/backup before deployment. iOS/Android playback and signing still need native device verification.

## Local schedule preview

For a registered test customer with an unpaid development membership:

```sh
ENABLE_DEV_WORKOUTS=true npm run dev:workouts --workspace @jbfitness/api -- --email customer@example.test
```

Optional `--week YYYY-MM-DD` sets the starting date. This creates a clearly labelled development sample routine and unreviewed sample catalogue entries with no demonstration files. It does not generate a personalized plan. Production refuses this fixture. Real trainer/AI publication handlers and personalization arrive in their respective milestones.

## API

- `GET /me/workouts?from=YYYY-MM-DD`: seven-day window from the current plan.
- `GET /me/workouts/:id`: prescription and saved progress.
- `PUT /me/workouts/:id/progress`: revision-aware owner-only save.
- `GET /me/workouts/history`: owned historical logs without a paid-content gate.
- `GET /me/exercises`: visible catalogue for eligible members.
- `GET /me/exercises/:id/video`: authorized playback link, or explicit missing-video state.
- `GET/HEAD /media/exercises/:id?...`: signed, membership-checked private stream.

All paths use the `/api/v1` prefix. Except the signed stream itself, these endpoints require an authenticated customer session. Sign-out/account changes clear open workout routes so another signed-in identity cannot inherit a previous customer's detail screen.

## Verification

Database tests check ownership, plan validation/versioning, complete-item enforcement, request retries, concurrent revisions, future/archived saves, history persistence, expired-member restrictions, private file boundaries, streaming ranges and signed-link tampering. A generated two-second technical clip labelled PLAYBACK TEST verifies transport/decoding without masquerading as an exercise demonstration.

`node --env-file=apps/api/.env scripts/browser-account-smoke.mjs --workout` additionally tests the running Flutter player controls, completion/history and account navigation in the dedicated QA browser. It creates a unique temporary customer/exercise/clip and removes only its own fixtures afterwards. The backend workout integration suite also uses `ffmpeg` for that technical clip. Flutter tests exercise the missing-video state without native-player mocks.
