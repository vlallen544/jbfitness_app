#!/usr/bin/env bash
set -euo pipefail
JB_PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$JB_PROJECT_DIR"
bash scripts/mobile.sh build apk --debug --target lib/main_preview.dart "$@"
JB_TOOLS_DIR="${JB_TOOLS_DIR:-/home/allen/.local/share/jbfitness-tools}"
JB_ANDROID_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$JB_TOOLS_DIR/android-sdk}}"
if [[ -x "$JB_TOOLS_DIR/jdk21/bin/java" ]]; then
  export JAVA_HOME="$JB_TOOLS_DIR/jdk21"
fi
JB_APK_FILE="apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"
"$JB_ANDROID_DIR/build-tools/36.0.0/apksigner" verify --verbose "$JB_APK_FILE"
mkdir -p artifacts/client-preview
cp "$JB_APK_FILE" artifacts/client-preview/JB_Fitness_Client_Preview.apk
cp docs/CLIENT_PREVIEW_INSTALL.txt artifacts/client-preview/INSTALL.txt
"$JB_ANDROID_DIR/build-tools/36.0.0/aapt" dump badging "$JB_APK_FILE" > artifacts/client-preview/APK_DETAILS.txt
cd artifacts/client-preview
sha256sum JB_Fitness_Client_Preview.apk > SHA256SUMS.txt
python3 "$JB_PROJECT_DIR/scripts/package-client-preview.py" "$JB_PROJECT_DIR/artifacts/client-preview"
printf '%s\n' 'Created artifacts/client-preview/ APK and smaller ZIP (offline sample-data preview).'
