#!/usr/bin/env bash
# Build and sign a release APK locally.
#
#   KEYSTORE=~/.keystores/pingtools.jks \
#   KEYSTORE_PASSWORD=... KEY_ALIAS=... KEY_PASSWORD=... \
#   ./scripts/release.sh
#
# The unsigned APK is produced by Gradle; apksigner from build-tools adds the
# v2/v3 signature. Nothing secret is committed to the repository.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${KEYSTORE:?Set KEYSTORE to the keystore path}"
: "${KEYSTORE_PASSWORD:?Set KEYSTORE_PASSWORD}"
: "${KEY_ALIAS:?Set KEY_ALIAS}"
: "${KEY_PASSWORD:?Set KEY_PASSWORD}"

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$SDK" ]]; then
  echo "ANDROID_SDK_ROOT/ANDROID_HOME is not set" >&2
  exit 1
fi

APKSIGNER="$(find "$SDK/build-tools" -name apksigner -type f | sort -V | tail -1)"
if [[ -z "$APKSIGNER" ]]; then
  echo "apksigner not found in $SDK/build-tools" >&2
  exit 1
fi

./gradlew :app:assembleRelease --console=plain

UNSIGNED="app/build/outputs/apk/release/app-release-unsigned.apk"
if [[ ! -f "$UNSIGNED" ]]; then
  # AGP may name it app-release.apk when a signingConfig is present.
  UNSIGNED="$(find app/build/outputs/apk/release -name '*.apk' | head -1)"
fi

VERSION="$(grep -oP 'versionName = "\K[^"]+' app/build.gradle.kts)"
mkdir -p dist
OUT="dist/PingTools-${VERSION}-release.apk"

"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-pass "pass:$KEYSTORE_PASSWORD" \
  --ks-key-alias "$KEY_ALIAS" \
  --key-pass "pass:$KEY_PASSWORD" \
  --out "$OUT" \
  "$UNSIGNED"

"$APKSIGNER" verify --print-certs "$OUT"
echo "Signed APK: $OUT"
