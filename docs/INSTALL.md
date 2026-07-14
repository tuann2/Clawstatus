# Install and use Clawstatus

## Requirements

- Apple Silicon Mac
- macOS 13 Ventura or newer
- Homebrew
- Claude Code installed, updated, and signed in

Verify Claude Code first:

```bash
claude --version
claude auth status
```

## Install with Homebrew

Clawstatus is currently ad-hoc signed rather than Apple-notarized. Homebrew
downloads the release and verifies the SHA-256 pinned in the cask, but macOS
will still reject the quarantined app. Install it first, then remove quarantine
from Clawstatus only. This does not disable Gatekeeper for any other app.

```bash
brew tap tuann2/clawstatus https://github.com/tuann2/Clawstatus
brew install --cask clawstatus
xattr -dr com.apple.quarantine /Applications/Clawstatus.app
open -a Clawstatus
```

Do not use `sudo spctl --master-disable` or disable Gatekeeper system-wide.

## Upgrade

```bash
brew update
brew upgrade --cask clawstatus
xattr -dr com.apple.quarantine /Applications/Clawstatus.app
```

## Usage

- The menu bar always shows the remaining percentage of the current 5-hour
  session.
- Click the percentage to open the card.
- Double-click the card to toggle Compact size.
- Right-click the card to choose Compact/Full size and opacity
  (100%, 85%, 70%, or 55%).
- Compact size shows only the two usage percentages and progress bars.
- Size and opacity are remembered after quitting or restarting the Mac.
- Clawstatus refreshes through the official Claude Code `/usage` command every
  60 seconds. It does not read or store OAuth tokens.

## Uninstall

```bash
brew uninstall --cask clawstatus
brew untap tuann2/clawstatus
```

To also remove saved UI preferences and the last usage snapshot:

```bash
rm -rf "$HOME/Library/Application Support/Clawstatus"
defaults delete com.internal.clawstatus
```

## Gatekeeper troubleshooting

If macOS shows “Not Opened”, close the dialog and run:

```bash
xattr -dr com.apple.quarantine /Applications/Clawstatus.app
open -a Clawstatus
```

This command targets only Clawstatus. If the app is somewhere else, replace the
path with its actual location. Do not disable Gatekeeper system-wide.

The permanent distribution fix is signing with an Apple Developer ID and
notarizing the app. Once notarized builds are available, the `xattr` step will
no longer be necessary.
