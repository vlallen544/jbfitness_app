# Connected Android demo — 0.3.0+8

This build connects the real Flutter account flow to `https://jbfitness-app.onrender.com/api/v1`. It replaces the previous offline sample-account shortcut for client login testing.

[Download the connected demo ZIP](https://github.com/vlallen544/jbfitness_app/releases/download/v0.3.0-demo.1/JB_Fitness_Connected_Demo.zip), extract it, then install `JB_Fitness_Connected_Demo.apk`. A [direct APK](https://github.com/vlallen544/jbfitness_app/releases/download/v0.3.0-demo.1/JB_Fitness_Connected_Demo.apk) and checksums are attached to the [release](https://github.com/vlallen544/jbfitness_app/releases/tag/v0.3.0-demo.1).

The selected Stitch design now covers the entire mobile interface: entry/profile setup, feature animations, main tabs, tracking, AI screens, meal review, sessions and shared controls. See [the screen mapping and captures](STITCH_IMPLEMENTATION.md). Logos and final imagery are pending client assets.

Android Firebase messaging and optional crash reporting are connected at the client SDK level. Use the bell or Profile → Notifications & reminders to opt in and access debug test tools. Automated alerts/reminder scheduling and backend sending remain pending. The iOS Firebase file has a mismatched bundle ID and remains unused; see [Firebase setup](FIREBASE_SETUP.md).

## What to show

1. Explore the four animated feature pages. Use Next, Back or swipe; nothing advances automatically.
2. Tap Continue to login, or skip/log in from any page.
3. Register a dedicated customer account with test details, or sign in as an existing customer. Staff use the web dashboard instead.
4. Complete the profile, reopen the app and verify that saved account/profile data returns.
5. The admin can inspect the registered customer in the hosted dashboard.

This update uses a new tour-completion preference so the redesigned introduction appears once after updating, including for returning users. The saved account session is retained; finishing the tour opens the authenticated account when it is still valid. The tour preference is remembered separately from the account session. Replay it from **Explore app features** on the login page. Returning users with a valid saved session open their account directly. The animated examples do not make real AI requests or create food logs, workouts or memberships.

Registration is free and does not activate a paid membership. Restricted features still need an active membership and appropriate content. Payment checkout, live AI and video providers are unconfigured; store fulfilment and automated notification delivery remain pending. The next demo milestone is safe hosted membership activation and supplied content so test customers can use the member features.

Render Free may need time to wake. The hosted API health endpoint was checked during packaging. If the first request times out, wait and retry. Keep the Supabase project active before presenting.

## Connection timeouts — 0.1.4

Login, registration and saved-session verification use a bounded 75-second wait. Other ordinary JSON requests keep their existing 15-second limit. The login screen shows connection status while submitting. Requests are sent once; credentials and registration are not automatically replayed. Session-check failure preserves the local token for Retry connection, and a late response cannot restore a timed-out session by itself. A registration timeout advises trying sign-in with the same email first, because a slow server may already have created the account.

During investigation the public health endpoint returned HTTP 200 in about 0.55 seconds. A healthy check from the development machine does not establish that a particular phone can reach the service. For the older APK, opening `https://jbfitness-app.onrender.com/api/v1/health` on the same phone and waiting for `status: ok` can wake the service before retrying login. If that page also fails, check the phone's internet connection, network/VPN restrictions and Render service status.

Render documents that free web services sleep after 15 idle minutes and take about a minute to resume: [official free-service limits](https://render.com/docs/free). Cold start is a plausible cause of the reported timeout, not a confirmed diagnosis of the phone network.

## Rebuild

```bash
bash scripts/build-connected-demo.sh --no-pub
```

The script builds `lib/main.dart` with the hosted HTTPS `API_BASE_URL`, verifies its APK signature and exports APK/ZIP, package metadata, install instructions and SHA-256 checksums to ignored `artifacts/connected-demo/`. The APK inside the ZIP is checked against the original checksum. `JB_API_URL` can select another HTTPS API ending in `/api/v1`; never put a credential in that URL.

Package: `com.jbfitness.jbfitness`, version `0.3.0`, version code `8`, same development signing key as previous preview builds. It can update the previous Android preview. This is a development-signed testing build, not a store release. Android installation/runtime behavior still needs a physical-device check. iOS needs macOS/Xcode and separate signing.

Current checks: all 84 Flutter tests pass and analysis is clean, including simulated 45-second authentication responses, bounded session timeouts, token preservation and single-submit registration recovery.

Verification also covers non-auto-advancing navigation, skip, swipes, back, the real login handoff, persistence and replay; enlarged-text and reduced-motion layouts; existing mobile account and feature tests; Flutter analysis; native packaging/signature and ZIP embedded-file checks. The dashboard/backend source was not changed for this mobile design update.
