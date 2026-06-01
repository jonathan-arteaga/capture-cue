#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CaptureCue"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="${1:-$DIST_DIR/$APP_NAME.dmg}"

usage() {
  cat >&2 <<USAGE
usage: $0 [path/to/CaptureCue.dmg]

Required credentials, choose one:
  CAPTURE_CUE_NOTARY_KEYCHAIN_PROFILE
  or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD
USAGE
}

if [ ! -f "$DMG_PATH" ]; then
  "$ROOT_DIR/script/package_dmg.sh" >/dev/null
fi

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Missing app bundle at $APP_BUNDLE" >&2
  exit 1
fi

echo "Validating app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNATURE_DETAILS="$(codesign -dvvv "$APP_BUNDLE" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$SIGNATURE_DETAILS" || {
  echo "CaptureCue.app must be signed with a Developer ID Application certificate before notarization." >&2
  exit 1
}
grep -q "flags=.*runtime" <<<"$SIGNATURE_DETAILS" || {
  echo "CaptureCue.app must be signed with hardened runtime before notarization." >&2
  exit 1
}

echo "Verifying DMG..."
hdiutil verify "$DMG_PATH" >/dev/null

echo "Submitting DMG for notarization..."
if [ -n "${CAPTURE_CUE_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$CAPTURE_CUE_NOTARY_KEYCHAIN_PROFILE" \
    --wait
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
else
  usage
  exit 2
fi

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Assessing notarized DMG..."
spctl -a -vv -t open "$DMG_PATH"

echo "$DMG_PATH"
