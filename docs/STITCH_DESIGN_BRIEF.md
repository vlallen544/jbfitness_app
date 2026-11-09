# JB Fitness — Stitch design brief

The client subsequently selected the [linked Stitch preview](https://stitch.withgoogle.com/preview/12045522015379722897?node-id=bb9575ca6f0e407e86acd45455737dfa). Its native Flutter implementation, final tokens and screenshots are documented in [STITCH_IMPLEMENTATION.md](STITCH_IMPLEMENTATION.md). The prompts below record the original design exploration brief.

Use Stitch to explore and select the visual design. Implement the selected screens as native Flutter widgets for Android/iOS; implement the staff dashboard in the existing Next.js app. Existing authentication, APIs, data permissions and business behavior remain the integration foundation.

## First prompt: establish the mobile visual direction

Paste this into a new mobile project in Stitch:

```text
Design JB Fitness, a personalized fitness coaching mobile app for Android and iOS.

Create three cohesive screens first:
1. Login / create account.
2. Today / home.
3. Workout session details.

Explore three visual directions using the same content: athletic editorial, minimal premium coaching, and approachable daily fitness. Show each direction as a consistent set so I can compare them.

Brand: white page backgrounds, black typography and red primary actions. Primary red #D71920; black #111111; white #FFFFFF. Neutral gray supporting text and borders. Use lighter red #FF6268 for readable accents on black panels. Give white backgrounds most of the screen area.

Create a distinctive, polished mobile product with strong typography, deliberate spacing, useful information hierarchy, restrained illustration and consistent icons. Make primary actions easy to reach with one hand. Keep body text readable and controls comfortably tappable. Account for safe areas, the keyboard, long content and enlarged text.

Login: email, password, show/hide password, Sign in, Create account, and an Explore app features link. Include connecting and incorrect-credentials states. Authentication currently uses app email/password. Google sign-in and password reset are not connected.

Today: customer greeting, today's workout, Open workouts, a compact habit checklist, meal-log entry point and progress shortcut. Bottom navigation: Today, Workouts, Plans, Profile. Show a believable empty/new-member state as well as an active member example. Label example content.

Workout details: session title, date, duration, exercise list, sets/reps/rest, available demonstration-video action, actual-performance logging and session completion. Include unavailable-video and saved-completion states.

Use real product actions and clear copy. Example records should be labelled. Include a reusable design system for typography, spacing, colors, buttons, cards, form controls, icons, navigation and status states. Provide screens and exportable design rules, including DESIGN.md where available.
```

## Follow-up prompt: extend the selected direction

```text
Use the selected JB Fitness design system for these screens:

1. Four-page feature onboarding: workouts, meal estimates, habits/progress and coaching. Design animated app-preview storyboards. Next, Back, swipe and Skip are user controlled. Last action: Continue to login. The tour has no automatic page advance or dismissal.
2. Fitness profile onboarding: goals, experience, measurements, training days, equipment and separate sharing choices.
3. Weekly workout schedule and exercise details.
4. Food diary and photo/text meal-estimate review: estimated calories/macros, editable portions and explicit save.
5. Habits: quick Today checklist plus weekly and monthly grids, completion targets and progress summaries.
6. Body progress: measurements, private progress photos, history and date comparisons.
7. Coaching: fitness questions, labelled assistant messages and trainer feedback.
8. Membership comparison: monthly Normal ₹3,000 with stored demonstrations and no live video sessions; Premium ₹10,000 with 10 sessions; Premium Plus ₹20,000 with 25 total sessions. Higher plans inherit lower-plan benefits. Audio support is deferred.
9. Session booking/history with availability, confirmation, cancellation terms and remaining allowance.
10. Profile/settings, sharing controls and sign out.

Include loading, empty, validation, disabled/unavailable, error/retry and success states. Provide motion notes for feature demonstrations and page transitions, with reduced-motion alternatives. Keep the white/red/black identity consistent.

The current demo has real email/password accounts and saved profiles. AI providers, live payments, video calls, notifications and supplement fulfilment are not activated. Communicate unavailable features truthfully. Supplements are a later feature and can be designed separately as planned screens.
```

## Separate web dashboard project

```text
Design the JB Fitness owner/trainer web dashboard using the selected mobile brand system: white workspace, black typography and red actions. Provide desktop and narrow layouts.

Screens: staff login, owner overview, customer directory and trainer assignment, assigned-trainer review inbox, workout review/publication, session calendar and membership catalogue.

Owners manage assignments. Trainers review customer information only when assigned and authorized by the customer's sharing choices. Show empty states, real record counts, search, filters, pending saves, errors and successful actions. Base review workload on loaded open/resolved records. Keep administrative tasks easy to scan and complete. Financial analytics and store operations are later work.

Export the shared design system and screen designs so the existing Next.js implementation can follow them.
```

## Handoff

Share the selected screens/export, design-rule file and any motion notes. Screenshots can establish the visual direction; exported assets and design rules make spacing, typography and reusable components easier to reproduce. A project link is useful when accessible. An automatic production Flutter conversion is not assumed.

References: [Google's Stitch introduction](https://developers.googleblog.com/en/stitch-a-new-way-to-design-uis/) and [Stitch design-rule import/export](https://blog.google/innovation-and-ai/models-and-research/google-labs/stitch-design-md/).
