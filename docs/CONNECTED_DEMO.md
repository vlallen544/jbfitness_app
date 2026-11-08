# Connected Android demo — 0.1.3+4

This build connects the real Flutter account flow to `https://jbfitness-app.onrender.com/api/v1`. It replaces the previous offline sample-account shortcut for client login testing.

[Download the connected demo ZIP](https://github.com/vlallen544/jbfitness_app/releases/download/v0.1.3-demo.1/JB_Fitness_Connected_Demo.zip), extract it, then install `JB_Fitness_Connected_Demo.apk`. A [direct APK](https://github.com/vlallen544/jbfitness_app/releases/download/v0.1.3-demo.1/JB_Fitness_Connected_Demo.apk) and checksums are attached to the [release](https://github.com/vlallen544/jbfitness_app/releases/tag/v0.1.3-demo.1).

## What to show

1. Explore the four animated feature pages. Use Next, Back or swipe; nothing advances automatically.
2. Tap Continue to login, or skip/log in from any page.
3. Register a dedicated customer account with test details, or sign in as an existing customer. Staff use the web dashboard instead.
4. Complete the profile, reopen the app and verify that saved account/profile data returns.
5. The admin can inspect the registered customer in the hosted dashboard.

The tour preference is remembered separately from the account session. Replay it from **Explore app features** on the login page. Returning users with a valid saved session open their account directly. The animated examples do not make real AI requests or create food logs, workouts or memberships.

Registration is free and does not activate a paid membership. Restricted features still need an active membership and appropriate content. Payment checkout, live AI and video providers are unconfigured; store fulfilment and notifications remain pending. The next demo milestone is safe hosted membership activation and supplied content so test customers can use the member features.

Render Free may need time to wake. The hosted API health endpoint was checked during packaging. If the first request times out, wait and retry. Keep the Supabase project active before presenting.

## Rebuild

```bash
bash scripts/build-connected-demo.sh --no-pub
```

The script builds `lib/main.dart` with the hosted HTTPS `API_BASE_URL`, verifies its APK signature and exports APK/ZIP, package metadata, install instructions and SHA-256 checksums to ignored `artifacts/connected-demo/`. The APK inside the ZIP is checked against the original checksum. `JB_API_URL` can select another HTTPS API ending in `/api/v1`; never put a credential in that URL.

Package: `com.jbfitness.jbfitness`, version `0.1.3`, version code `4`, same development signing key as previous preview builds. It can update the previous Android preview. This is a development-signed testing build, not a store release. Android installation/runtime behavior still needs a physical-device check. iOS needs macOS/Xcode and separate signing.

Verification covers non-auto-advancing navigation, skip, swipes, back, the real login handoff, persistence and replay; enlarged-text and reduced-motion layouts; existing mobile account and feature tests; Flutter analysis; native packaging/signature and ZIP embedded-file checks. The dashboard/backend source was not changed for this walkthrough.
