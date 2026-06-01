#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CaptureCue"
BUNDLE_ID="com.jonathanarteaga.CaptureCue"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/CaptureCue.entitlements"

default_sign_identity() {
  if [ -n "${CAPTURE_CUE_CODE_SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$CAPTURE_CUE_CODE_SIGN_IDENTITY"
    return
  fi

  local identity
  identity="$(security find-identity -p codesigning -v 2>/dev/null | sed -n 's/^[[:space:]]*[0-9]*) [A-F0-9]* "\(Apple Development:.*\)"$/\1/p' | head -n 1)"
  if [ -n "$identity" ]; then
    printf '%s\n' "$identity"
  else
    printf '%s\n' "-"
  fi
}

SIGN_IDENTITY="$(default_sign_identity)"
CODESIGN_ARGS=(--force --deep --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS")
if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
  CODESIGN_ARGS+=(--options runtime --timestamp)
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --package-path "$ROOT_DIR"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [ -d "$ROOT_DIR/Resources" ]; then
  rsync -a "$ROOT_DIR/Resources/" "$APP_RESOURCES/"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>CaptureCue</string>
  <key>CFBundleIconFile</key>
  <string>CaptureCue</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSCameraUsageDescription</key>
  <string>CaptureCue can include camera video in recordings when you enable presenter mode.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>CaptureCue can record narration when you enable microphone audio.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>CaptureCue records selected screens and windows so you can create polished product demos.</string>
</dict>
</plist>
PLIST

codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --bundle-only|bundle)
    echo "$APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--bundle-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
