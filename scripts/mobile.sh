#!/usr/bin/env bash
set -euo pipefail
JB_PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
JB_FLUTTER_BIN="${JB_FLUTTER_BIN:-/home/allen/.local/share/jbfitness-tools/flutter/bin/flutter}"
if [[ ! -x "$JB_FLUTTER_BIN" ]]; then
  printf '%s\n' 'Flutter was not found. Set JB_FLUTTER_BIN to your Flutter executable.' >&2
  exit 1
fi
cd "$JB_PROJECT_DIR/apps/mobile"
export CHROME_EXECUTABLE="${CHROME_EXECUTABLE:-/usr/bin/chromium}"
if [[ -x /home/allen/.local/share/jbfitness-tools/jdk21/bin/java ]]; then
  export JAVA_HOME=/home/allen/.local/share/jbfitness-tools/jdk21
fi
if [[ -d /home/allen/.local/share/jbfitness-tools/android-sdk/cmdline-tools/latest ]]; then
  export ANDROID_HOME=/home/allen/.local/share/jbfitness-tools/android-sdk
fi
exec "$JB_FLUTTER_BIN" "$@"
