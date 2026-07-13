#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/dist/Clawline.app"
contents="$app/Contents"

swift build --package-path "$root" -c release

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$root/.build/release/Clawline" "$contents/MacOS/Clawline"
cp "$root/Resources/Info.plist" "$contents/Info.plist"

/usr/bin/codesign --force --deep --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"

printf '%s\n' "$app"
