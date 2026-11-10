# Firebase notifications and crash reporting

Firebase project: `jb-fitness-a2dc4`. Existing account authentication, NestJS API on Render and PostgreSQL on Supabase remain in use. Firebase is used only for device messaging and optional crash reports; no Firestore, Firebase Auth, Analytics or Firebase Storage integration is introduced.

## Current implementation

- Registered Android application: `com.jbfitness.jbfitness`.
- Android client configuration validated and added, alongside matching Dart Firebase options.
- Firebase Core, Messaging and Crashlytics Flutter SDKs installed. Android Google Services and Crashlytics Gradle plugins configured.
- An Android notification channel, white status-bar icon and red accent match the app design.
- Open the bell icon or **Profile → Notifications & reminders** for the Stitch-style settings screen.
- Push registration and crash reporting are separate, explicit choices. Neither is automatically enabled by app startup.
- Firebase initializes without blocking account startup. Unsupported platforms and offline previews do not start the native SDK through the app's device-services controller.
- Device registration is tied to the current in-memory signed-in session. Logout clears the token from the UI immediately and attempts native token revocation. Late callbacks from a previous binding cannot restore that displayed token.
- Foreground messages display a generic in-app update banner. Background notification payloads are displayed by Android. Taps use only allowlisted destination names and open records through the current account's normal API permissions.
- Crash reports are opt-in. Custom Flutter error reports contain a generic error type and stack, without attaching profile data, food logs, photos, chat contents or tokens.
- Debug-only controls reveal/copy the device token and record an opt-in non-fatal diagnostic test. No intentional crash is required for the first check.

This is the client transport milestone. Automated trainer, booking, renewal and order notifications are **not connected**. There is no backend device-token registry or event sender yet. Scheduled workout/food/habit reminders remain pending.

## Test Android notifications

1. Install the Firebase-enabled connected Android APK. Existing APKs before 0.3.0 do not contain this integration.
2. Sign in as a customer and complete the fitness profile.
3. Open the bell or **Profile → Notifications & reminders**.
4. Turn on **Push notifications** and accept Android's permission prompt. If blocked, adjust the phone's app notification settings and refresh device status.
5. In **Demo test tools**, choose **Show device token → Copy device token**. Keep the token private to your testing workflow; it is not a login credential.
6. In Firebase Console, open **Messaging** (use the console product search if its menu location differs), create/select a notification campaign and choose **Send test message**.
7. Paste the registration token. Use a generic title/body, such as `JB Fitness test` / `Your device is connected`.
8. Put the app in the background using Home, then send. Confirm the OS notification appears. A force-stopped app is not the same as a backgrounded app.
9. Tap the notification and confirm the app opens. Test again while the app is foregrounded; it displays the generic update banner rather than duplicating an OS alert.

Optional custom data: set `screen` to `workouts`, `nutrition`, `progress`, `coaching`, `feedback`, `sessions`, `plans`, `habits` or `notifications`. Unknown destinations fall back to notification settings. URLs and record IDs are not navigation instructions.

The current Flutter Messaging SDK also exposes a newer installation-ID registration API. The console-testing bridge deliberately uses its still-supported registration-token compatibility methods; an installation ID is not substituted into the token field. Review this interface when adding the server sender.

## Test Crashlytics

1. Open **Notifications & diagnostics** and enable **Share crash reports**.
2. In the debug test tools, choose **Record diagnostic test**.
3. Open Firebase Console → Crashlytics for the registered Android app. Complete the console's Get started flow if shown.
4. Allow the device to sync; inspect the non-fatal `JB Fitness diagnostic test` report. This button records locally and does not claim that the server has received it immediately.
5. Turn sharing off to disable SDK collection and request deletion of unsent reports.

The user confirmed receipt of a Firebase Console notification on their Android phone on 9 November 2026. Notification-tap routing and a real Crashlytics report still need separate device verification. The user deferred the Crashlytics check while app feature work takes priority.

## iOS registration correction

The downloaded `GoogleService-Info.plist` is registered to **`com.jbfitness.jbfitnes`**, missing its final `s`. It is intentionally not copied into the project or used by the runtime. The app's bundle ID is **`com.jbfitness.jbfitness`**.

Register a new iOS application under the same Firebase project with the exact correct bundle ID, and download its new plist. Keep the existing Android registration. Do not fix this by editing the old plist's string or changing the application's bundle ID.

After the matching file is supplied, add matching iOS Dart options and project resource membership, configure APNs authentication in Firebase, enable the Xcode Push Notifications capability and verify signing/background delivery on macOS and a physical iPhone. Configure Crashlytics dSYM upload for the project's Swift Package Manager setup before claiming useful iOS crash reports. The current iOS device gateway remains unavailable until that setup is complete; login and other app features still run independently.

## Backend delivery — deferred integration milestone

Use an authenticated, owner-scoped device registry, token rotation/logout unlinking and a retry-safe event outbox. Configure a server-side Firebase service identity privately on Render, then connect trainer feedback, bookings and membership events. Keep push text generic and fetch protected details only after the user opens the app. Sending credentials never belong in the APK or public repository.

Firebase app config files contain client identifiers; they are not Firebase Admin service-account credentials. `.gitignore` excludes common Admin SDK/service-account JSON names and Apple `.p8` keys.

## Design review

[Notification settings](previews/firebase-notification-settings.png) and [debug test tools](previews/firebase-test-tools.png) are native Flutter captures using synthetic device state. They do not show a real Firebase delivery or crash report.

## Verification and references

The mobile suite covers denied permission, registration failure, logout races, cold-start routing, unsupported destinations, independent diagnostics consent, failure isolation and enlarged text. Native Android build/signature/package checks and manual device checks have separate status.

- [Firebase Flutter setup](https://firebase.google.com/docs/flutter/setup)
- [Flutter messaging setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
- [Receiving Flutter messages](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)
- [Flutter Crashlytics setup](https://firebase.google.com/docs/crashlytics/flutter/get-started)
- [Opt-in crash reporting](https://firebase.google.com/docs/crashlytics/flutter/customize-crash-reports)
