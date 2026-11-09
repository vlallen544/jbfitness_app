# Stitch design implemented in Flutter

Reference supplied by the client on 9 November 2026: [JB Fitness Stitch preview](https://stitch.withgoogle.com/preview/12045522015379722897?node-id=bb9575ca6f0e407e86acd45455737dfa).

The linked Today, workout, nutrition and profile designs are implemented as native Flutter widgets for the existing Android/iOS application. No embedded website or new authentication system is required. The existing web staff dashboard is a separate interface.

## Screens and behavior

| Screen | Implemented design and working connections |
| --- | --- |
| Today | Compact brand header, real membership/session summary, selectable weekly date strip, workout card, Log Meal/Snap Food/Bodyweight/Chat Coach shortcuts, food summary, habits and trainer feedback. Workout details, diary, estimates, progress and coaching open the existing screens. Pull to refresh reloads the daily overview and habits. |
| Workouts | Training block, schedule/history/AI shortcuts, weekly routine cards, white session header and exercise protocol cards. Existing demonstration playback, actual-performance inputs, revision checks and save/complete behavior remain in use. |
| Nutrition | White calorie summary, red progress accents, macro cards, meal estimation actions and the existing dated meal diary. Food logging, photo/text estimation, portion review and explicit save retain the existing entitlement and provider checks. |
| Profile | Account identity, membership expiry and remaining sessions, plan comparison, coaching links, fitness-profile editing, privacy switches, progress-photo link, walkthrough replay and sign-out. |
| Plans | Matching compact header, white membership summary, session balance and confirmed monthly plan comparison: Normal ₹3,000; Premium ₹10,000 with 10 video sessions; Premium Plus ₹20,000 with 25 total. Checkout remains disabled until configured. |
| Login and profile setup | Shared temporary identity, white feature/profile cards, pale-blue feature chips, Space Grotesk headings and rounded white inputs. Real authentication, validation and profile persistence retain their existing behavior. |
| Introduction | Four rebuilt native Flutter scenes: a weekly workout strip and assembling exercise cards; a food scan, calorie ring and macro bars; habit checks and a drawn weight trend; a coaching conversation and support card. Each animation settles on its page. Next/Back/swipe/Skip remain user-controlled, with reduced-motion support. |
| Supporting screens | Habits and monthly grid, body charts/comparison/photo editors, photo/text meal review, food catalogue and nutrient dialogs, AI planner/replies/summaries, trainer feedback, session bookings and video loading/error states all use the shared light surfaces, typography and red/pale-blue accents. |
| Shared controls | Rounded white forms, outlined actions, dialogs, bottom sheets, date pickers, menus, floating alerts and branded startup/reconnection cards. Android day/night startup and iOS launch background match the app canvas. |

## Visual system

Background `#F8F9FF`; white cards; dark ink `#0B1C30`; red `#D71920`; supporting pale blue `#E5EEFF`; subtle borders and shadows; rounded cards and pill buttons. Space Grotesk is used for headings and metrics; Inter for body text and controls. Fonts are bundled locally with their SIL Open Font License texts and registered in Flutter's license registry.

`lib/stitch_ui.dart` owns the reusable header, cards, pills, shortcuts and daily nutrition summary; `lib/app_theme.dart` owns the shared tokens and theme.

The JB mark, initial avatar and exercise icon are temporary. No third-party trainer photo, client logo, product imagery or exercise thumbnail is represented as final supplied content. Replace these when the client provides assets.

## Data and privacy

Prototype names, calories, targets, ratings, coach identity, call recordings and AI confidence are not shipped as live facts. Connected builds use the authenticated API; missing values stay unknown. Sample-account screenshots below come from the separately labelled offline preview.

Profile sharing must be enabled before coaching review sharing can be selected. Coaching sharing requires its own explicit action. Revoking profile sharing also revokes coaching review sharing. A failed save leaves the existing consent unchanged. Progress photos remain private under the existing access controls.

Store, automated notifications/reminder schedules, data export/deletion, real payment checkout and unconfigured AI/video services are shown honestly as unavailable or pending. This design update does not activate those providers.

## Complete mobile pass — 0.2.1+7

The remaining legacy dark promotional panels were replaced across mobile screens. The four walkthrough scenes use the actual visual vocabulary of the Stitch interface. There is no new animation service or runtime dependency. Illustration motion uses Flutter animation controllers, staged opacity/translation/scale, ring/bar progress and custom chart painting. The walkthrough preference is versioned independently of authentication so updated clients see the new introduction once without losing their saved login.

The player can still letterbox supplied video content in black; its loading, unavailable, error, retry and transport controls use the new app design. Final logo and imagery are still pending client assets. The subsequent Android Firebase milestone activates device-notification preferences and opt-in diagnostic controls; see [Firebase setup](FIREBASE_SETUP.md).

## Review captures

Native Flutter captures at a 390 × 844 logical phone viewport using the bundled fonts. Offline/test fixtures are used solely for design review; displayed values are illustrative rather than live customer data:

- [Today](previews/stitch-today.png)
- [Workouts](previews/stitch-workouts.png)
- [Workout detail](previews/stitch-workout-details.png)
- [Nutrition](previews/stitch-nutrition.png)
- [Plans](previews/stitch-plans.png)
- [Profile](previews/stitch-profile.png)

- [Introduction: workouts](previews/stitch-intro-workouts.png), [nutrition](previews/stitch-intro-nutrition.png), [progress](previews/stitch-intro-progress.png), [coaching](previews/stitch-intro-coaching.png)
- [Sign in](previews/stitch-sign-in.png), [create account](previews/stitch-register.png), [profile setup](previews/stitch-profile-setup.png)
- [Habits](previews/stitch-habit-tracker.png), [body progress](previews/stitch-body-progress.png), [progress editor](previews/stitch-progress-editor.png)
- [AI planning](previews/stitch-workout-planner.png), [AI coaching reply](previews/stitch-coach-reply.png), [trainer feedback](previews/stitch-trainer-feedback.png)
- [Food library](previews/stitch-food-library.png), [food label dialog](previews/stitch-food-label-dialog.png), [connection status](previews/stitch-connection-status.png)
- [Meal input](previews/stitch-meal-input.png), [estimate review](previews/stitch-meal-review.png), [session management](previews/stitch-coaching-sessions.png), [video status](previews/stitch-video-status.png)

## Validation

Flutter analysis and the complete mobile test suite cover the existing account, login-timeout, onboarding, workouts, nutrition, meal estimates, progress, coaching, membership, sessions and walkthrough flows, plus new sharing-consent success/failure checks. Small-phone/enlarged-text and reduced-motion walkthrough checks verify that the new scenes preserve navigation and fit constrained layouts. Native review also checks supporting screens at 320 px with 1.6× text. Existing tests verify account/session, entitlement, consent and explicit-save boundaries.

The connected Android package uses the hosted HTTPS backend, verifies APK signing and checks the APK embedded in the ZIP against its original SHA-256. iOS source uses the same Flutter widgets; an iOS build still requires macOS/Xcode and signing. Physical-device installation, fonts and runtime need client-device confirmation.
