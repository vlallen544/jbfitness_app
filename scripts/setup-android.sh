#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != '--accept-sdk-license' ]]; then
  printf '%s\n' 'Review https://developer.android.com/studio#terms-and-conditions first.' 'After agreeing, run: bash scripts/setup-android.sh --accept-sdk-license'
  exit 2
fi
JB_TOOLS_DIR="${JB_TOOLS_DIR:-/home/allen/.local/share/jbfitness-tools}"
JB_ANDROID_DIR="$JB_TOOLS_DIR/android-sdk"
JB_JAVA_DIR="$JB_TOOLS_DIR/jdk21"
if [[ ! -x "$JB_JAVA_DIR/bin/java" ]]; then
  printf '%s\n' 'Install the project-local OpenJDK 21 in jbfitness-tools/jdk21 before continuing.' >&2
  exit 1
fi
export JAVA_HOME="$JB_JAVA_DIR"
export ANDROID_HOME="$JB_ANDROID_DIR"
mkdir -p "$JB_TOOLS_DIR/downloads" "$JB_ANDROID_DIR/cmdline-tools"
if [[ ! -x "$JB_ANDROID_DIR/cmdline-tools/latest/bin/sdkmanager" ]]; then
  JB_ARCHIVE="$JB_TOOLS_DIR/downloads/commandlinetools-linux-15859902_latest.zip"
  curl -L --fail --retry 2 --continue-at - -o "$JB_ARCHIVE" https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
  printf '%s  %s\n' '4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583' "$JB_ARCHIVE" | sha256sum -c -
  JB_UNPACK_DIR="$(mktemp -d "$JB_TOOLS_DIR/android-unpack.XXXXXX")"
  unzip -q "$JB_ARCHIVE" -d "$JB_UNPACK_DIR"
  mv "$JB_UNPACK_DIR/cmdline-tools" "$JB_ANDROID_DIR/cmdline-tools/latest"
  rmdir "$JB_UNPACK_DIR"
fi
JB_SDKMANAGER="$JB_ANDROID_DIR/cmdline-tools/latest/bin/sdkmanager"
printf 'y\n%.0s' {1..30} | "$JB_SDKMANAGER" --sdk_root="$JB_ANDROID_DIR" --licenses
"$JB_SDKMANAGER" --sdk_root="$JB_ANDROID_DIR" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
printf '%s\n' 'Android build tooling is installed. Run bash scripts/mobile.sh doctor -v, then build apk --debug.'
