#!/usr/bin/env bash
# Build the Flutter release APK, verify its signature and copy it to dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/mobile"

FLUTTER="${FLUTTER:-/home/scott/flutter/bin/flutter}"
if [[ ! -x "$FLUTTER" ]]; then
  echo "Flutter not found at $FLUTTER (set FLUTTER=...)" >&2
  exit 1
fi

if [[ ! -f android/key.properties ]]; then
  echo "mobile/android/key.properties is missing; release signing is not configured." >&2
  exit 1
fi

"$FLUTTER" pub get
"$FLUTTER" build apk --release

VERSION="$(grep -oP '^version:\s*\K[0-9.]+' pubspec.yaml)"
APK="build/app/outputs/flutter-apk/app-release.apk"
OUT="$ROOT/dist/PingTools-Flutter-${VERSION}.apk"
mkdir -p "$ROOT/dist"
cp "$APK" "$OUT"

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
APKSIGNER="$(find "$SDK/build-tools" -name apksigner -type f 2>/dev/null | sort -V | tail -1)"
if [[ -n "$APKSIGNER" ]]; then
  "$APKSIGNER" verify --print-certs "$OUT" | head -4
fi

sha256sum "$OUT" | tee "$OUT.sha256"
echo "Release APK: $OUT"
