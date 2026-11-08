# JB Fitness mobile design direction

Flutter remains the customer app framework for iOS and Android. This is an original interface built around JB Fitness's existing account, workout and membership flows.

## Current mobile palette — version 0.1.1

The user requested red, white backgrounds and black. White (`#FFFFFF`) is the app canvas and form/card surface. Black (`#111111`) anchors headlines and summary panels. Red (`#D71920`) is used for primary actions, selection and active controls; a lighter red (`#FF6268`) keeps small labels and chart lines readable on black. Supporting borders and text use neutral grays. The app stays light when the phone uses dark mode, and the Android launcher uses the matching red/black JB mark.

The shared palette covers Today, sign-in/profile, workouts/video controls, membership, habit grids, nutrition, meal estimates, progress charts, coaching, planning, trainer feedback and session history. Hard-coded green tints were replaced alongside the shared theme. White-on-red button contrast is 5.19:1; red labels on black are 6.47:1.

All 63 Flutter tests pass, analysis is clean, and web plus Android debug preview builds pass. APK signature, package version 0.1.1/code 2, all three ABIs and ZIP checksums are verified. Physical Android and iOS checks remain pending.

The actual offline preview was inspected at phone size: [Today](previews/red-theme-today.png), [workouts](previews/red-theme-workouts.png), [plans](previews/red-theme-plans.png), [profile](previews/red-theme-profile.png), [habits](previews/red-theme-habits.png), [nutrition](previews/red-theme-nutrition.png), [progress](previews/red-theme-progress.png). Earlier screenshot sets below retain the previous design for reference.

## Dashboard palette — 8 November 2026

The admin/trainer dashboard now shares the mobile red, white-background and black palette. Its global stylesheet defines the same red (`#D71920`), bright red on black (`#FF6268`), black (`#111111`), white and neutral gray roles. This covers staff sign-in, navigation, summary cards, customer assignments, review/publication controls, session calendar and membership catalogue. Focus indicators and form controls use red; badge states retain text labels. No account, permission or API behavior changed.

## Reference review — 6 November 2026

| Public project | Material reviewed | Useful idea for JB Fitness |
| --- | --- | --- |
| [wger Flutter](https://github.com/wger-project/flutter) | README and actual dashboard screenshot in its Fastlane metadata | Group workout access and progress into clear sections; keep workout actions easy to reach. |
| [Fitness Buddy](https://github.com/vaibhavhariramani/fitness_buddy) | README and `docs/screenshots/dashboard.png` | Compact greeting, restrained card borders, clear empty states and labelled bottom navigation. |
| [Feeel](https://github.com/EnjoyingFOSS/feeel) | Repository overview and README; no screenshots inspected | Keep exercise execution focused and easy to follow. This is a product-flow reference, not a visual reference. |
| [PulseFit](https://github.com/TheodorAbel/PulseFit-Fitness-App) | Repository README; no screenshots inspected | Separate weekly planning, active sessions and workout history. This is a flow reference, not a verified visual reference. |

Reference code, illustrations, photos and branding were not imported. The screenshots were inspected temporarily outside this repository. These are design observations, not claims that every documented feature was independently tested.

## Visual system

- White page backgrounds and surfaces, black ink/summary panels and red accents.
- Large, compact headlines; small section labels; consistent 16–26 px corners.
- One prominent workout action on Today; secondary information follows it.
- Existing Today / Workouts / Plans / Profile navigation remains functional.
- Responsive Today content capped at 640 px; screens scroll for smaller phones and larger text.
- Standard labelled Material controls, readable text, and accessible checkboxes.
- No external font, image or UI-library dependency introduced.

## First implementation

- Shared theme affects cards, buttons, fields, headings and navigation across the app.
- Today adds a greeting from the signed-in account, current-week date strip, a training card using saved profile preferences, and a habit checklist with live completion progress.
- Week strip highlights the current date only. It does not claim workout completion or offer date navigation.
- Training card opens the real workout schedule. Profile preferences are not presented as an assigned workout.
- The initial checklist sample has now been replaced by saved customer habits, monthly targets and tracking grids. Habit checkmarks remain separate from workout and food logs.
- Sign-in gains a branded training panel; validation and authentication remain intact.
- Workout list gains stronger hierarchy, exercise icons and a completed-session indicator based on server state.
- AI meal estimates, workout planning and coaching chat now have real server adapters, with unavailable states while configuration is missing. Sample QA responses remain separate from live provider evaluation. Summary facts come from saved records and remain readable without an AI key.

## Following passes

1. Daily tracking now covers habits, food diary, editable meal estimates and body progress. See [HABITS.md](HABITS.md), [NUTRITION.md](NUTRITION.md), [MEAL_ESTIMATES.md](MEAL_ESTIMATES.md) and [BODY_PROGRESS.md](BODY_PROGRESS.md).
2. AI planning, coaching/summaries, staff reviews and session reservation software are implemented. Continue with actual client policy decisions and video-provider integration; native verification, provider configuration and quality evaluation remain pending.
3. Check camera, keyboard, safe areas, text scaling and video playback on physical Android and iOS devices during the native pilot.

Phone-sized Flutter previews validate the shared UI; they do not replace native device testing.

## Workout detail pass

- Session overview shows the date, last saved status and the number of checked exercises. The progress indicator reflects edits on the current screen; a reminder makes clear that saving is required.
- Numbered exercise cards separate prescriptions, instructions, video access and optional actual-performance logging.
- Sets, repetitions and weight fields stack on narrow phones. The difficulty selector expands within the available width.
- A saved completion confirmation appears only after a successful save or when loading a previously completed session.
- Demonstration loading, missing-content and playback-error states share the new visual system. The player shows elapsed/total time and retains play/pause, seeking and retry.
- Session feedback, completion, partial saving, skipping, revisions and request-id reuse continue through the existing API. Archived and future-session restrictions remain intact.
- No duration estimate is invented from sets/reps, and real exercise videos remain pending client content.

## Membership and profile pass

- Active membership uses a dark summary card with dates and remaining live-session allowance. Scheduled next periods remain separate. A zero-session plan does not render a misleading progress fraction.
- Plan cards preserve API prices, benefits and 0/10/25 total session allowances. The page explicitly distinguishes planned services from features already connected; checkout stays disabled.
- Profile sections group basic measurements, goals, dietary preferences, workout availability and consent. Fields retain their existing validation and save contract.
- Height/weight fields stack at narrow widths, dropdowns use available width, and long equipment helper text wraps.
- Health-data consent and optional trainer sharing remain separate controls. Profile updates do not silently change either flag.
- Account identity is displayed from the signed-in account. No calculated health metrics or invented progress are added.

## Reproduce visual checks

Session reservation milestone: 111 API checks, 9 dashboard checks and 60 Flutter tests pass. `scripts/browser-sessions-preview.ts` verifies actual owner confirmation, trainer availability, IST conversion and withdrawal with temporary database fixtures. See [owner rules](previews/sessions-owner-rules.png), [trainer calendar](previews/sessions-trainer-calendar.png) and [phone layout](previews/sessions-mobile-calendar.png). The Flutter flow shows held/used/available credits, explicit confirmation, saved terms and retryable requests. Customer booking/video remain disabled pending real client rules and a video adapter.

Staff operations milestone: 94 API checks, 8 dashboard checks and 54 Flutter tests pass, with clean analysis and successful API/admin/web builds. At that milestone the dashboard used green/ink/lime; the current red/white/black palette above replaces it. Features include staff sign-in, assignment cards, a focused review inbox, profile context, customer-visible feedback and a normal workout editor. `scripts/browser-staff-preview.ts` tests actual local services in an isolated database schema. See [inbox](previews/staff-trainer-inbox.png), [assignment](previews/staff-assignments.png), [workout editor](previews/staff-workout-review.png) and [phone layout](previews/staff-mobile-inbox.png). Technical fixtures are removed after the walkthrough; native-device checks remain pending.

Coaching milestone: 86 backend integration checks and 50 Flutter tests pass, with clean analysis and successful API/admin/web builds. `scripts/browser-coaching-preview.mjs` verifies explicit chat/summary requests, recorded facts, accessible AI reply text and confirmed history clearing. See [recorded week](previews/coaching-recorded-week.png), [chat](previews/coaching-chat.png) and [summary](previews/coaching-summary.png). These are fixture responses, not evidence of live model quality. Native and provider pilots remain pending.

AI planning milestone: 76 backend integration checks and 42 Flutter tests pass, with clean analysis and successful API/web builds. `scripts/browser-ai-planning-preview.mjs` verifies one request, polled review states, a routine summary, published navigation and an AI-labelled workout version using fixture responses. See [introduction](previews/ai-planning-intro.png), [review](previews/ai-planning-review.png), [published result](previews/ai-planning-published.png) and [workouts](previews/ai-planning-workouts.png). This does not establish live model quality or native device behavior.

Body progress milestone: 64 backend integration checks and 37 Flutter tests pass, with clean analysis and successful API/web builds. `scripts/browser-progress-preview.mjs` verifies phone-sized dated charts, a measurement edit, actual file selection, explicit upload and authenticated image display. See [chart](previews/progress-chart.png), [measurements](previews/progress-measurements.png) and [private photo](previews/progress-private-photo.png). Images are solid-color technical fixtures; native camera/gallery checks remain pending.

Meal estimate milestone: 56 backend integration checks and 32 Flutter tests pass, with clean analysis and successful API/web builds. `scripts/browser-meal-estimate-preview.mjs` exercises actual file selection, combined text/photo input, editable review and explicit diary saving using fixture responses. The review uses the shared ink/green palette and preserves visible estimate labels. See [review preview](previews/meal-estimate-review.png) and [saved diary](previews/meal-estimate-diary.png). This verifies UI behavior, not live AI accuracy or native camera behavior.

Nutrition milestone: 47 backend integration checks and 28 Flutter checks pass. `scripts/browser-nutrition-preview.mjs` uses sample responses to inspect the diary, food picker, portion preview and saved energy totals. The USDA adapter was separately verified against its public demo API; no customer search key was configured.

Saved-habits milestone: 38 database integration checks and 24 Flutter checks pass, with clean analysis and successful API/web compilation. The browser helper also exercises a persisted-checkmark response, monthly/weekly grids and a grid save request using sample responses. [HABITS.md](HABITS.md) describes the implemented behavior and remaining extensions.

Validation for the three frontend passes: clean Flutter analysis and 21 passing Flutter checks, including 320 px wide Today, exercise-logging, membership and profile screens at 1.6× text size; queued memberships and zero-session plans; measurements and trainer-sharing saves; actual sets/reps/decimal weight saving; saved completion confirmation; checklist/navigation; onboarding; and workout flows. Native iOS/Android verification remains pending platform tooling.

Build the regular Flutter web target and start `node scripts/serve-mobile.mjs`. Use a dedicated Chromium profile with remote debugging on port 9234, then run `node scripts/browser-design-preview.mjs` from the project root. The helper intercepts requests to the local API with sample responses; no API server or database is required. It checks sign-in, checklist interaction, workout navigation, details, missing-video feedback, completion-save requests, membership comparison and profile saves preserving consent flags. It captures screenshots in `docs/previews/redesign-*.png`.

This is separate from `scripts/browser-account-smoke.mjs`, which exercises the real local API and database. The visual check does not establish backend correctness or exercise protected video playback.
