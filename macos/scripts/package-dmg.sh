#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/Resources/Info.plist")"
app="$root/dist/Clawstatus.app"
staging="$root/.build/clawstatus-dmg"
dmg="$root/dist/Clawstatus-${version}-apple-silicon.dmg"

"$root/scripts/build-app.sh"

rm -rf "$staging" "$dmg" "$dmg.sha256"
mkdir -p "$staging"
cp -R "$app" "$staging/Clawstatus.app"
ln -s /Applications "$staging/Applications"

/usr/bin/hdiutil create \
    -volname "Clawstatus" \
    -srcfolder "$staging" \
    -ov \
    -format UDZO \
    "$dmg"

rm -rf "$staging"
(
    cd "$(dirname "$dmg")"
    /usr/bin/shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256"
)

printf '%s\n' "$dmg"
