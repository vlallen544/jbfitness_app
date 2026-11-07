# Contextual AI coaching and weekly summaries

Open **Today → Open AI coach**. Ask a general workout question, request a practical food idea, or tap **Summarize my last 7 days**. Replies are labelled AI-generated, saved to a private conversation, and use the customer's recorded context. No trainer message is sent by this feature.

For example, a customer asks “How can I make my routine more consistent?” The coach can use their saved training days and recent records to suggest a manageable next step. A summary might show two completed workouts and food logged on one day. That does not mean the customer ate on only one day: the app keeps unlogged intake unknown.

## Recorded facts and AI commentary

The backend calculates a seven-day window ending today in Asia/Kolkata. **Your recorded week** remains available without an AI key and after membership expiry. Facts include:

- Completed and explicitly skipped workout sessions, plus a separately labelled count of sessions in the current plan during the period. Completions can include prior plan versions; these counts are not used as an adherence fraction.
- Food-entry count, days with food logs and per-day nutrient totals from immutable food snapshots and gram quantities. Unlogged days have null totals. Missing optional nutrients remain incomplete; AI-estimated food entries stay flagged.
- Completed habit check-ins across the habits that actually have completed entries. This is not a streak or a habit-adherence percentage.
- The latest two recorded weights within the period and their signed difference. A missing or single weight cannot produce a change value. Deleted records are excluded.

AI commentary appears separately from these application-calculated figures. A saved summary preserves its facts snapshot even when the user later edits the underlying diary. A new summary uses fresh records. Current implementation is user-requested, not scheduled or automatically notified.

## Conversation and provider behavior

Migration `009_coaching.sql` adds private coaching turns and summary snapshots. Customers see chronological messages, a **Load earlier messages** control, pending/failed states, AI replies, suggestions and any **Trainer review needed** reason. The model receives at most six completed chat exchanges; it does not receive the entire stored history or previous summary text.

Server context includes age, goal, experience, equipment, training days, session length, current routine, limitations, dietary preferences, food notes and deterministic recent facts. Names, email, passwords, uploaded photos and the photo gallery are excluded. User-supplied chat text may itself contain identifying information; it is transmitted as entered. The screen discloses use of saved context before submission.

The provider makes one bounded [OpenAI structured-output](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses) call with no action tools. Schema validation bounds reply length and suggestions and requires a reason for trainer-review flags. Nutrition suggestions are general meal ideas; chat cannot alter a workout plan, nutrition target, food log, membership or order. Medical/injury questions requiring judgment are directed to review in the prompt; this is not a guarantee that the model will detect every risk. Safety, prompt-injection, nutrition and representative profile evaluation remain necessary before live activation.

Review flags are stored on the turn and appear in the trusted operator command `npm run ai:reviews --workspace @jbfitness/api`. The staff dashboard now supports assigned-trainer review, resolution and saved customer-visible feedback under a separate coaching-sharing opt-in; see [STAFF_OPERATIONS.md](STAFF_OPERATIONS.md). The operator queue excludes resolved/cleared items. Live trainer chat and notifications remain pending. A flag alone does not mean a trainer has read it or that emergency support is available.

## Activation and usage limits

In the API's ignored environment configuration, set `ENABLE_COACHING_AI=true`, `OPENAI_API_KEY` and `COACHING_AI_MODEL`, then restart. The model must support strict structured outputs; none is silently selected. Chat and summaries use a separate flag/model from meal estimation and workout planning. No live key or model was configured for this milestone, and verification uses fixture responses.

Provisional limits are 20 chat attempts and two summary attempts per customer per Asia/Kolkata day, including failed and deleted attempts. Only one request may be pending per customer. The service requires an active AI-coaching entitlement and completed profile for new work. History, facts and clearing remain available after expiry. At most 1,000 visible turns may be stored before clearing history is required. Confirm quotas and costs before launch.

Calls have a 45-second timeout and a 2,000-output-token cap, with no automatic paid retries. The app uses a 65-second request timeout. A repeated reference replays its saved pending/completed/failed state without contacting AI again; changed input with the same reference conflicts. Pending turns older than two minutes become failed on the customer's next history/status request. They are not replayed after a crash.

The client retains uncertain request payloads and polls history; polling never submits new work. A user can explicitly retry the same reference to discover its stored result. A failed stored turn requires an explicit new request to try again, within the allowance. Conversation pagination uses owner-scoped cursors and database timestamp precision.

## Privacy and deletion

The API requires the owner session for every conversation read/write. There are no public chat URLs or customer-ID parameters. Keys stay server-side. Provider requests use `store:false`, which does not guarantee zero provider retention; review the provider account's data controls and privacy disclosures before activation.

**Clear coaching history** requires confirmation and clears stored input, replies, facts, usage and model data for that customer's turns, plus related coaching feedback text from trainers. It preserves small request-reference/hash/status tombstones and review metadata to prevent late retries from resurrecting cleared content; admission quotas still count those attempts. A response returning after clearing cannot restore text or snapshots. An in-flight paid request may still finish at the provider; clearing does not cancel that transmission. Backup retention and complete account erasure remain separate launch policies. Tracking records and planning feedback are unaffected by clearing chat.

## API

All routes follow `/api/v1/me/coaching` and require a customer session.

| Method | Route | Purpose |
|---|---|---|
| GET | `/` | Latest 30 chronological turns, cursor, configuration and remaining allowances |
| GET | `/?before=:turnId` | Earlier owner-scoped turns |
| GET | `/facts` | Current deterministic seven-day facts |
| GET | `/:id` | Owner-only saved turn/pending state |
| POST | `/` | `{requestId,kind:'chat',message}` or `{requestId,kind:'summary',message:''}` |
| DELETE | `/` | Clear the owner's coaching text and snapshots |

## Verification and remaining work

Database-backed HTTP checks cover authentication/roles, membership, strict input, context isolation, nutrient calculations and unknown values, workout counts, habit check-ins, weight differences, duplicate/in-flight requests, saved summary snapshots, clearing during a provider call, review flags, invalid output, quotas, pagination, restart and expiry. Transport checks stub the fixed provider endpoint; no paid AI calls occur.

Flutter checks cover unavailable service, explicit text submission, AI/review labels, summaries and missing food days, retained retry references, polling without resubmission, expired-member clearing and a 320-pixel screen at enlarged text size. The browser walkthrough uses fixture responses. Live model quality, actual trainer handoff and physical iOS/Android behavior remain unverified.

Project verification: 86 database-backed integration checks and 50 Flutter tests pass. Flutter analysis is clean; API, admin-dashboard and Flutter web builds succeed. The local operator command successfully reads both review queues. Widget checks include readable semantics for selectable AI replies and retaining editable drafts after rejected requests.

`scripts/browser-coaching-preview.mjs` passed the phone-sized walkthrough with fixture responses: explicit chat, accessible AI reply, seven-day summary snapshot and confirmed deletion preserving tracking records. Previews are in `docs/previews/coaching-*.png`; no AI provider was called.
