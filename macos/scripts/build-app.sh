#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/dist/Clawstatus.app"
contents="$app/Contents"

swift build --package-path "$root" -c release

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$root/.build/release/Clawstatus" "$contents/MacOS/Clawstatus"
cp "$root/Resources/Info.plist" "$contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$contents/Resources/AppIcon.icns"

/usr/bin/codesign --force --deep --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"

printf '%s\n' "$app"
