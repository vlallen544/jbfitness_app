# AI routine review and workout planning

Open **Workouts → Plan with AI**. The customer reads what will be used and requests a plan. The app submits a request reference; the server loads the customer's profile and approved exercise content. A durable database job continues while the customer leaves the screen. Status refreshes never generate another plan.

For example, a beginner records walking as their current routine, chooses three training days, lists their equipment and saves 30-minute availability. The workflow reviews that context, drafts sessions on their chosen days, checks exercise IDs and availability, and obtains a separate AI judgment. A correctable issue gets one revision. A passing plan appears in Workouts with an AI label; existing workout logs stay in history.

## Bounded workflow

1. **Admission:** require a customer session, active membership, completed profile, configured service and at least one approved exercise matching equipment. Freeze the profile, catalogue, next training dates, recent workout summaries and model names in a private job snapshot.
2. **Routine review:** use the configured review model to return `proceed` or `needs_review`, a summary and practical notes.
3. **Draft:** use the planner model to create exactly one session on each selected weekday within the next seven days, starting tomorrow. Weekday numbers follow the profile convention: Monday 0 through Sunday 6. Calendar boundaries use Asia/Kolkata.
4. **Application checks:** validate structure, exact dates, approved IDs, equipment, unique exercises, dosage bounds and an estimated time budget.
5. **AI judgment:** separately review suitability against the supplied profile, routine, available equipment, exercise instructions and recovery. A review decision needing human judgment stops publication.
6. **One revision:** supply concrete code/reviewer issues to the planner, then run application checks and AI judgment again. At most two drafts and five provider calls occur in a run.
7. **Atomic publication:** lock the customer, job, profile and exercise definitions; recheck the current plan and input fingerprint, dates and membership. Publish the new workout version and job result in the same transaction. A stale profile, changed plan or revoked/edited definition prevents publication.

The planner and reviewer are separate calls and can use different configured models. They are not independent human reviewers. Strict JSON controls structure, not fitness correctness: real quality, suitability and cost evaluation remain necessary before activation. The provider uses the [official OpenAI structured-output format](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses), with server-side schema validation as well.

## Provisional automatic-planning boundaries

- Only operator-approved catalogue exercises are used; development samples and draft content are excluded. Equipment names match after trimming/case/whitespace normalization; `bodyweight` requires no equipment. Unknown equipment aliases are not guessed.
- The eligible catalogue is capped at the first 60 approved matching definitions ordered by ID. Oversized context is rejected rather than silently sending an unbounded prompt.
- Profiles under 18, sessions below 15 minutes, or limitations beyond a small explicit set of empty/none responses are routed to review before any model calls. The routine reviewer may identify other reasons for human review. These are conservative product boundaries, not clinical validation or medical clearance.
- Maximum eight unique exercises per session, one to five sets, one to 30 repetitions, and 30–180 seconds of rest. Starting load is always unset (`targetWeightKg:null`) because a verified load baseline is unavailable.
- Time is an operational estimate: five minutes of warm-up allowance, one minute transition per exercise, and `sets × (repetitions × 4 seconds + rest seconds)`. It does not measure actual workout duration, prescribe a specific warm-up routine or guarantee suitability. Timed exercise prescriptions remain a later schema extension.
- An AI approval with outstanding issues cannot publish. A failed second draft/review leaves the existing plan intact.

## Queue, budgets and recovery

Migration `008_ai_planning.sql` adds customer-owned jobs. One queued/running request per customer is enforced by a partial unique index. Identical request references replay the stored result; a new reference requests new work. The provisional allowance is two admitted runs per customer per Asia/Kolkata day, including failed and review-needed runs. Confirm allowance and model budgets before launch.

Workers claim queued rows with `FOR UPDATE SKIP LOCKED` and a six-minute lease. Each API instance with the worker enabled handles one job at a time. A call has a 45-second timeout and a 5,000-output-token cap, with no provider tools or automatic transport retries. A trace is persisted before each call and records available token counts, timing, model and review output after completion. Failed calls may have unknown token usage; use provider billing records for spend reconciliation.

Queued jobs survive API restart. A running job whose lease expires becomes `review_needed` instead of replaying an uncertain paid stage. Lost claims cannot publish or overwrite a later result. The worker waits for its active job during graceful shutdown; abrupt termination relies on lease recovery. Disabling provider configuration pauses queue processing. Hosts must restart after changing configuration.

`review_needed` jobs form a persistent review queue. A trusted operator can inspect unresolved identifiers and reasons with `npm run ai:reviews --workspace @jbfitness/api`. The staff dashboard now provides assignments, consent-controlled review, customer-visible feedback and explicit trainer-plan publication; see [STAFF_OPERATIONS.md](STAFF_OPERATIONS.md). Notifications and live trainer messaging remain pending. Provider failures show a failed result; a customer may explicitly request a new run within their allowance.

## Configuration and data

In the ignored API environment configuration, set `ENABLE_WORKOUT_AI=true`, `OPENAI_API_KEY`, `WORKOUT_AI_PLANNER_MODEL` and `WORKOUT_AI_REVIEW_MODEL`. Both model names are explicit; there is no silent model selection. Models must support strict structured outputs. `WORKOUT_AI_WORKER_ENABLED=false` disables the local worker so another configured API instance can process the shared queue. The default is enabled when the provider is configured. Live keys and flags were not provisioned as part of this implementation.

Requests send age, height/weight, goal, experience, equipment, training days, session length, current routine, limitations and up to 14 recent workout date/status/note summaries. They do not send names, email, diet notes, progress photos, or the photo gallery. The screen explains this processing before submission. Context snapshots, drafts and assessments contain personal fitness information and require restricted database/backup access and an agreed retention policy.

Credentials remain server-only. Provider calls use `store:false`; this does not guarantee zero provider retention. Review the provider account's data controls and customer privacy disclosures before activation. The customer status endpoint exposes job status, summary and published-plan reference, not raw prompts, private catalogue snapshots, credentials or unfinished drafts. Status/history reads remain available after membership expiry; new generation/publication requires active entitlement.

## API

| Method | Route after `/api/v1/me/ai-planning` | Purpose |
|---|---|---|
| GET | `/status` | Configuration, entitlement, profile readiness, matching exercise count, quota and latest run |
| POST | `/` | `{requestId}`; enqueue or replay the customer's request |
| GET | `/:id` | Owner-only status and published-plan reference |

## Verification and remaining work

Integration checks use real HTTP/PostgreSQL and fixture model responses to verify duplicate admission, concurrent worker claims, publication, one-revision bounds, exact dates/equipment/time/load rules, ownership, human-review boundaries, unresolved reviewer issues, stale inputs, restart, interrupted leases, provider errors and expiry. A stubbed transport checks the real provider request format without contacting OpenAI. Flutter checks cover unavailable configuration, submission, published navigation, polling without resubmission, uncertain-submit references and narrow/enlarged-text review states.

Verified project totals: 76 backend integration checks, 3 unit-test files and 42 Flutter tests pass. Flutter analysis is clean; API compilation and the Flutter web build succeed. The operator review-queue command was also exercised successfully.

`scripts/browser-ai-planning-preview.mjs` passed the phone-sized browser walkthrough: one submission, polled review, routine summary and navigation to the published AI-labelled workout version. Previews are saved in `docs/previews/ai-planning-*.png`. Responses and workouts in these images are fixtures, not live model output.

Live provider quality, cost/latency, client exercise content, trainer policy review and physical iOS/Android behavior remain unverified. Existing AI meal estimation and this planner use separate flags/model settings. Contextual coaching chat, automatic activity-driven replanning, nutrition suggestions, weekly summaries and trainer notifications are subsequent work.
