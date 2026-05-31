#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="astro-lens"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

developer_id_identity() {
  security find-identity -p codesigning -v 2>/dev/null | sed -n 's/^[[:space:]]*[0-9]*) [A-F0-9]* "\(Developer ID Application:.*\)"$/\1/p' | head -n 1
}

if [ -z "${ASTRO_LENS_CODE_SIGN_IDENTITY:-}" ]; then
  RELEASE_SIGN_IDENTITY="$(developer_id_identity)"
  if [ -n "$RELEASE_SIGN_IDENTITY" ]; then
    ASTRO_LENS_CODE_SIGN_IDENTITY="$RELEASE_SIGN_IDENTITY" "$ROOT_DIR/script/build_and_run.sh" --bundle-only
  else
    "$ROOT_DIR/script/build_and_run.sh" --bundle-only
  fi
else
  "$ROOT_DIR/script/build_and_run.sh" --bundle-only
fi
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_BUNDLE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
