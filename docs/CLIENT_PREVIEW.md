# Earlier offline client preview

The current connected build is documented in [CONNECTED_DEMO.md](CONNECTED_DEMO.md). The 0.1.2 download below is retained as an earlier offline demo with the superseded timed splash. Rebuilding the offline entry point from current source uses the new four-page feature walkthrough.

[Download the smaller ZIP (about 78 MiB)](https://github.com/vlallen544/jbfitness_app/releases/download/v0.1.2-preview.1/JB_Fitness_Client_Preview.zip), extract it and open **JB_Fitness_Client_Preview.apk** on an Android phone. The ZIP contains the unchanged signature-verified APK, instructions and its checksum. The installed app size is unchanged. A separate ZIP checksum is published with the release.

The [direct APK](https://github.com/vlallen544/jbfitness_app/releases/download/v0.1.2-preview.1/JB_Fitness_Client_Preview.apk) remains available under Assets on the [GitHub preview release](https://github.com/vlallen544/jbfitness_app/releases/tag/v0.1.2-preview.1). The release includes APK and ZIP SHA-256 checksums. Open **JB Fitness** after installation; no login is needed.

The separate `lib/main_preview.dart` entry point shows the skippable fitness intro, then opens a sample customer account. The normal `lib/main.dart` app remains connected to the real API. A persistent banner identifies the offline demo on every route. Its HTTP adapter has no network delegate, backend URL, real account credentials or AI key.

The client can watch the animated athlete intro and review Today, habit checkmarks/monthly grids, workout schedules and details, exercise logging, membership comparison, profile fields, sample nutrition, progress charts, trainer feedback and session history. Habit checks, workout logging and profile edits are simulated in memory and reset when the process restarts. Nutrition/measurements are sample read-only records. Unsupported mutations return an explicit unavailable message. Video playback has no supplied client media. Payments, live AI, calls and uploads are not simulated as functioning services. Example historical session terms are illustrative, not confirmed client policy.

Verified: all 66 Flutter tests pass, analysis is clean, and the separate web preview builds with bundled renderer resources. A browser check opens directly into the sample account without API interception or a backend. The Android APK at local path `artifacts/client-preview/JB_Fitness_Client_Preview.apk` now builds, passes APK v2 signature verification and matches its SHA-256 checksum. Generated handover files are excluded from Git; use the build script below to recreate them. Package metadata confirms version 0.1.2 (code 3), minimum API 24, target API 36, the JB launcher icon and arm64-v8a/armeabi-v7a/x86_64 libraries. See the [phone preview](previews/red-theme-today.png). Physical-device installation and behavior remain unverified.

## Build the Android APK

The user accepted the Android SDK licence and the required tools are installed on this workstation; build again with `bash scripts/build-client-preview.sh`. On a new machine, `scripts/setup-android.sh` requires explicit licence acceptance. Review [Google’s SDK terms](https://developer.android.com/studio#terms-and-conditions), then, after accepting them:

```sh
bash scripts/setup-android.sh --accept-sdk-license
bash scripts/build-client-preview.sh
```

The build script verifies the APK signature before creating `artifacts/client-preview/JB_Fitness_Client_Preview.apk`, `SHA256SUMS.txt`, `APK_DETAILS.txt` and `INSTALL.txt`. With Python 3 it also creates `JB_Fitness_Client_Preview.zip` and its `.zip.sha256` checksum. ZIP packaging checks that the embedded APK matches its original checksum. It can be rerun without compiling the APK using `python3 scripts/package-client-preview.py artifacts/client-preview`.

The universal APK is approximately 157 MiB; its compressed ZIP download is approximately 78 MiB. It is a debug-signed review build, not a store release. The APK uses the current development package ID and can replace a previously installed debug build with the same ID/signing key. No Play Store upload is required for this review. Gradle uses a 2 GiB heap and two workers for this development machine.

Send the APK through your chosen file-sharing channel after building it. On the Android phone, open the APK and allow installation from that source if prompted. Open **JB Fitness**. No registration, API server or network connection is needed for the offline sample flows. This APK cannot install on an iPhone; iOS installation still needs macOS/Xcode and an appropriate Apple testing/signing workflow.

## Local visual review without Android tooling

```sh
bash scripts/mobile.sh build web --target lib/main_preview.dart --output build/client-preview-web --no-web-resources-cdn
node scripts/serve-mobile.mjs --client-preview
```

Open `http://localhost:8080` on the development computer. This verifies shared Flutter UI only; it does not establish Android APK correctness or physical-device behavior.

## Connected review later

A connected build needs a client-accessible test API over HTTPS, dedicated test accounts and test membership/content fixtures. `localhost` in an Android APK refers to the phone itself, so the current default development URL cannot provide a remote client demo. Do not include backend credentials or provider keys in an APK. The offline build avoids exposing the workstation or deploying a backend merely to show the design.
