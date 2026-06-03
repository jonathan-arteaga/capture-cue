#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_paths=(
  "CaptureCue/App"
  "CaptureCue/Features"
  "CaptureCue/DesignSystem"
  "CaptureCue/Models"
  "CaptureCue/Stores"
  "CaptureCue/Resources"
  "CaptureCue/Support"
  "CaptureCue.xcodeproj"
  "Config.xcconfig"
)

for path in "${required_paths[@]}"; do
  if [[ ! -e "$ROOT_DIR/$path" ]]; then
    echo "Missing required path: $path" >&2
    exit 1
  fi
done

xcodebuild -list -project "$ROOT_DIR/CaptureCue.xcodeproj" >/dev/null
