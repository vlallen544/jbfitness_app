# Staff dashboard and review inbox

The existing Next.js dashboard at `http://localhost:3000` now opens staff sign-in. The public read-only membership catalogue remains at `/plans`. Run `npm run dev:api` and `npm run dev:admin` after database migration. This milestone is local development work; no website was deployed.

For example, the owner assigns Alex to Sam. Alex enables profile sharing and separately opts into coaching-review sharing in the mobile app. Sam sees Alex's flagged AI coaching question, saves feedback, or edits a planning draft and explicitly publishes the reviewed workout. Alex opens **Today → Trainer feedback** to read the note and open the reviewed training week.

## Accounts and permissions

Public registration still creates customer accounts only. For local staff setup, create a dedicated account through the existing registration flow, then run:

```sh
npm run staff:role --workspace @jbfitness/api -- --email coach@example.com --role trainer
```

Use `--role admin` for a dedicated owner account. The trusted local command rejects accounts with customer memberships, records the role change and revokes existing sessions. Sign in again afterward. No real account was promoted automatically during implementation. Production provisioning, recovery and stronger staff authentication remain launch work.

| Role | Available operations |
|---|---|
| Customer | Own sharing choices and trainer-feedback history in the mobile app |
| Admin | Customer/trainer directory, assignment/removal, review queue metadata and status |
| Trainer | Assigned-customer directory; shared profile, flagged coaching/planning details, feedback and reviewed-plan publication where consent permits |

Admins do not automatically receive private fitness profiles, chat content or progress photos. A trainer must have a current assignment and customer profile sharing. Opening/resolving a coaching or planning review additionally requires `shareCoachingWithTrainer=true`. The role is revalidated through the API; client-side role displays do not grant access.

The mobile profile has a separate unchecked-by-default choice: **Also allow my assigned trainer to review AI coaching requests and recent tracking summaries.** Existing profile-sharing consent does not enable this new access. Progress photos remain customer-only. Revocation/removal blocks subsequent private reads and review writes; already-delivered information cannot be recalled from a browser. Refresh or a denied request clears the open dashboard detail.

## Dashboard workflow

- Owner: open **Customers**, assign a provisioned trainer, or remove an existing assignment. Repeating the same assignment does not duplicate its audit entry. Assignment does not change customer consent.
- Trainer: review assigned customers, open a shared profile and the recorded-week figures when coaching sharing permits, or use **Review inbox** for flagged requests.
- Reviews show the original reason, current shared profile, applicable AI question/reply or routine draft, and prior trainer feedback. A trainer can save a follow-up note while leaving the review open or resolve it with customer-visible feedback.
- A planning review also has a normal workout editor: plan/session titles, dates, approved exercise selection, sets, repetitions, optional loads and rest seconds. Publishing is a separate explicit action. Resolving with feedback alone does not publish a plan.
- The customer sees saved notes under **Today → Trainer feedback**, with trainer name, date and outcome. Published-plan feedback opens its actual training week. AI planning status distinguishes trainer publication/completed review from an unresolved AI escalation.

The current directory and queue return up to 200 rows, with truncation notices; search filters the current view. The trainer selector shows up to 200 trainers. Larger deployments need server-side search/pagination. Customer feedback shows the latest 50 notes; full records remain stored. Review detail includes up to 30 prior feedback events. These are initial software limits, not business totals.

## Review publication and concurrency

Migration `010_staff_operations.sql` adds revisioned review state, feedback events and assignment/provisioning audit events. Review sources remain in their existing AI planning/coaching tables.

Review writes lock the customer and recheck assignment, profile/coaching consent and source availability. Revision checks prevent simultaneous reviewers overwriting an outcome. A request reference deduplicates an uncertain retry and rejects different feedback under the same reference. The dashboard freezes uncertain saves and offers retry/reload controls.

Publication requires an explicitly supplied reviewed plan, active customer workout entitlement, approved exercises matching current equipment, unique session dates from today through the next 27 days, and the ordinary workout schema bounds. The dashboard editor supports up to seven sessions with eight exercises each. Its load field is a trainer-entered value, distinct from the AI planner's unset starting loads. The trainer remains responsible for reviewing exercise suitability and dosage.

The current-plan identifier captured when opening the review must still match at publication. A changed schedule requires reloading instead of silently replacing a newer plan. Plan/version creation, planning outcome, review resolution and customer feedback commit together. An idempotent retry returns the stored result without publishing another version. Existing workout logs remain in history.

## Session and privacy boundaries

The browser calls a fixed same-origin `/api/operations` route. Next.js stores the opaque API session token in an HttpOnly, SameSite=Strict cookie, with Secure enabled in production. Tokens are not returned in login JSON or stored in browser local storage. Every private request checks the staff session. Server requests use a fixed configured `API_URL`; query input cannot choose an upstream host.

Mutations require the dashboard's exact Origin and JSON input. The route reads at most 16,000 bytes and uses a route/action allowlist. Set `DASHBOARD_ORIGIN` to the canonical HTTPS origin behind a reverse proxy. Private responses use `Cache-Control: private, no-store`; logout clears the cookie and attempts backend revocation. If revocation cannot be confirmed, the UI says so rather than claiming it succeeded. Use HTTPS for production.

Feedback is customer-visible, not an internal-only note. Customers retain their own feedback after membership expiry or sharing withdrawal. Clearing AI coaching history also clears related coaching feedback text and hides those review sources; planning feedback remains. Minimal action/reference metadata remains for audit and duplicate protection. Full account erasure and backup retention remain separate launch policies.

This document covers the review inbox and saved-feedback workflow. The subsequent [session reservation foundation](SESSIONS.md) adds owner policy controls, trainer availability, held credits and manual attendance. Actual video calls/customer booking activation, live trainer chat, push/email notifications and billing integration remain pending. No external person was messaged during verification.

## API

All routes follow `/api/v1` and use existing opaque bearer sessions.

| Method | Route | Access |
|---|---|---|
| GET | `/staff/overview` | Staff role; trainer results scoped to assignments/consent |
| PUT | `/staff/customers/:id/assignment` | Admin; `{trainerId,assigned}` |
| GET | `/staff/customers/:id` | Assigned trainer with profile sharing |
| GET | `/staff/reviews/:kind/:id` | Assigned trainer with profile and coaching sharing |
| POST | `/staff/reviews/:kind/:id` | Same access; revision, request reference, decision and customer-visible feedback |
| GET | `/me/trainer-feedback` | Customer's own feedback, including after expiry |

Kinds are `planning` and `coaching`; decisions are `follow_up`, `resolved` and `publish_plan`. Publication also supplies `plan` and `currentPlanId` (nullable when no plan exists). Session/role provisioning remains a trusted local command, not a customer API.

## Reproducing verification

Run the API integration suite after migrations, then build the dashboard and run:

```sh
npm run build --workspace @jbfitness/admin
npm run test:dashboard --workspace @jbfitness/api
```

The dashboard test starts actual Next/Nest servers and an isolated temporary PostgreSQL schema, applies migrations, uses dedicated fixture accounts and removes the schema on completion. It verifies origin rejection, customer-login denial, HttpOnly/Secure cookies, owner assignment, trainer review, feedback delivery and logout revocation. No live AI service is involved.

Verified project totals: 94 API integration checks, 8 dashboard boundary/provisioning checks and 54 Flutter tests pass. Flutter analysis is clean; API, dashboard and Flutter web builds succeed. The trusted role command was exercised only on dedicated fixture accounts, including rejection of an account with customer memberships.

With a dedicated local Chromium debugging session on port 9234, run `TSX_TSCONFIG_PATH=apps/api/tsconfig.json node --env-file=apps/api/.env --import tsx scripts/browser-staff-preview.ts` from the project root. The explicit TypeScript configuration enables the API's Nest decorators. The walkthrough exercises real local requests in a separate temporary schema and captures `docs/previews/staff-*.png`. Its accounts, reviews and exercise definition are technical fixtures, not client data. Physical mobile testing and production staff/security review remain pending.

The browser walkthrough passed actual owner assignment, trainer review, customer feedback delivery, one reviewed-plan publication, a 390-pixel dashboard layout and a delayed-refresh/sign-out regression. Screenshots include login, assignments, trainer inbox and the workout editor. Its local API/dashboard servers and temporary schema are removed on completion.
