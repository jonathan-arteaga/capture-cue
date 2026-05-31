#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="astro-lens"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="${1:-$DIST_DIR/$APP_NAME.app}"
DMG_PATH="${2:-$DIST_DIR/$APP_NAME.dmg}"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Missing app bundle at $APP_BUNDLE" >&2
  exit 1
fi

if [ ! -f "$DMG_PATH" ]; then
  echo "Missing DMG at $DMG_PATH" >&2
  exit 1
fi

echo "Checking app bundle signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNATURE_DETAILS="$(codesign -dvvv "$APP_BUNDLE" 2>&1)"

if grep -q "Authority=Developer ID Application" <<<"$SIGNATURE_DETAILS"; then
  echo "Developer ID signature detected."
  grep -q "flags=.*runtime" <<<"$SIGNATURE_DETAILS" || {
    echo "Developer ID release builds must enable hardened runtime." >&2
    exit 1
  }
  grep -q "Timestamp=" <<<"$SIGNATURE_DETAILS" || {
    echo "Developer ID release builds must include a secure timestamp." >&2
    exit 1
  }
elif grep -q "Signature=adhoc" <<<"$SIGNATURE_DETAILS"; then
  echo "Ad-hoc signature detected. This artifact is suitable for CI smoke testing only, not broad internal distribution." >&2
else
  echo "Non-Developer ID signature detected. This artifact may not pass Gatekeeper for distribution." >&2
fi

echo "Checking Info.plist privacy usage descriptions..."
for key in NSScreenCaptureUsageDescription NSCameraUsageDescription NSMicrophoneUsageDescription; do
  /usr/libexec/PlistBuddy -c "Print :$key" "$APP_BUNDLE/Contents/Info.plist" >/dev/null
done

echo "Checking camera and microphone entitlements..."
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null)"
grep -q "com.apple.security.device.camera" <<<"$ENTITLEMENTS" || {
  echo "Missing camera entitlement." >&2
  exit 1
}
grep -q "com.apple.security.device.audio-input" <<<"$ENTITLEMENTS" || {
  echo "Missing microphone entitlement." >&2
  exit 1
}

echo "Verifying DMG checksum..."
hdiutil verify "$DMG_PATH" >/dev/null

echo "Release artifact validation complete."
