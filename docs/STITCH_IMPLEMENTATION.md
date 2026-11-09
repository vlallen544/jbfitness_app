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
| Login, walkthrough and supporting screens | Shared font, colors, form controls and button styling carry through the existing real-login flow and user-controlled feature walkthrough. The supplied preview did not specify replacement login/walkthrough layouts. |

## Visual system

Background `#F8F9FF`; white cards; dark ink `#0B1C30`; red `#D71920`; supporting pale blue `#E5EEFF`; subtle borders and shadows; rounded cards and pill buttons. Space Grotesk is used for headings and metrics; Inter for body text and controls. Fonts are bundled locally with their SIL Open Font License texts and registered in Flutter's license registry.

`lib/stitch_ui.dart` owns the reusable header, cards, pills, shortcuts and daily nutrition summary; `lib/app_theme.dart` owns the shared tokens and theme.

The JB mark, initial avatar and exercise icon are temporary. No third-party trainer photo, client logo, product imagery or exercise thumbnail is represented as final supplied content. Replace these when the client provides assets.

## Data and privacy

Prototype names, calories, targets, ratings, coach identity, call recordings and AI confidence are not shipped as live facts. Connected builds use the authenticated API; missing values stay unknown. Sample-account screenshots below come from the separately labelled offline preview.

Profile sharing must be enabled before coaching review sharing can be selected. Coaching sharing requires its own explicit action. Revoking profile sharing also revokes coaching review sharing. A failed save leaves the existing consent unchanged. Progress photos remain private under the existing access controls.

Store, notifications, data export/deletion, real payment checkout and unconfigured AI/video services are shown honestly as unavailable or pending. This design update does not activate those providers.

## Review captures

Native Flutter captures at a 390 × 844 logical phone viewport, using the bundled fonts and explicitly labelled offline sample account:

- [Today](previews/stitch-today.png)
- [Workouts](previews/stitch-workouts.png)
- [Workout detail](previews/stitch-workout-details.png)
- [Nutrition](previews/stitch-nutrition.png)
- [Plans](previews/stitch-plans.png)
- [Profile](previews/stitch-profile.png)

## Validation

Flutter analysis and the complete mobile test suite cover the existing account, login-timeout, onboarding, workouts, nutrition, meal estimates, progress, coaching, membership, sessions and walkthrough flows, plus new sharing-consent success/failure checks. The small-phone/enlarged-text Today check verifies the revised layout.

The connected Android package uses the hosted HTTPS backend, verifies APK signing and checks the APK embedded in the ZIP against its original SHA-256. iOS source uses the same Flutter widgets; an iOS build still requires macOS/Xcode and signing. Physical-device installation, fonts and runtime need client-device confirmation.
