#!/usr/bin/env bash
set -euo pipefail
JB_PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$JB_PROJECT_DIR"
JB_API_URL="${JB_API_URL:-https://jbfitness-app.onrender.com/api/v1}"
python3 - "$JB_API_URL" <<'PY'
import sys
from urllib.parse import urlsplit
url = urlsplit(sys.argv[1])
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.path.rstrip('/') != '/api/v1':
    raise SystemExit('JB_API_URL must be an HTTPS backend URL ending in /api/v1, without credentials or query parameters.')
PY
bash scripts/mobile.sh build apk --debug --target lib/main.dart "--dart-define=API_BASE_URL=$JB_API_URL" "$@"
JB_TOOLS_DIR="${JB_TOOLS_DIR:-/home/allen/.local/share/jbfitness-tools}"
JB_ANDROID_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$JB_TOOLS_DIR/android-sdk}}"
if [[ -x "$JB_TOOLS_DIR/jdk21/bin/java" ]]; then
  export JAVA_HOME="$JB_TOOLS_DIR/jdk21"
fi
JB_APK_FILE="apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"
"$JB_ANDROID_DIR/build-tools/36.0.0/apksigner" verify --verbose "$JB_APK_FILE"
mkdir -p artifacts/connected-demo
cp "$JB_APK_FILE" artifacts/connected-demo/JB_Fitness_Connected_Demo.apk
cp docs/CONNECTED_DEMO_INSTALL.txt artifacts/connected-demo/INSTALL.txt
"$JB_ANDROID_DIR/build-tools/36.0.0/aapt" dump badging "$JB_APK_FILE" > artifacts/connected-demo/APK_DETAILS.txt
python3 - <<'PY'
from pathlib import Path
import hashlib
import zipfile

folder = Path('artifacts/connected-demo')
apk = folder / 'JB_Fitness_Connected_Demo.apk'
def checksum(stream):
    return hashlib.file_digest(stream, 'sha256').hexdigest()
with apk.open('rb') as stream:
    expected = checksum(stream)
(folder / 'SHA256SUMS.txt').write_text(f'{expected}  {apk.name}\n')
target = folder / 'JB_Fitness_Connected_Demo.zip'
names = [apk.name, 'SHA256SUMS.txt', 'APK_DETAILS.txt', 'INSTALL.txt']
with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for name in names:
        archive.write(folder / name, arcname=name)
with zipfile.ZipFile(target) as archive:
    with archive.open(apk.name) as stream:
        if checksum(stream) != expected:
            raise SystemExit('Archived APK checksum mismatch.')
    for name in names[1:]:
        if archive.read(name) != (folder / name).read_bytes():
            raise SystemExit('Archived installation file mismatch.')
with target.open('rb') as stream:
    digest = checksum(stream)
(folder / (target.name + '.sha256')).write_text(f'{digest}  {target.name}\n')
print(f'Connected demo packaged: {target} ({target.stat().st_size} bytes). Signature and embedded APK verified.')
PY
