# Install and use Clawstatus

## Requirements

- Apple Silicon Mac
- macOS 13 Ventura or newer
- Homebrew
- Claude Code installed, updated, and signed in
- Codex CLI installed, updated, and signed in (optional; Claude remains usable without it)

Verify both installed CLIs:

```bash
claude --version
claude auth status
codex --version
codex login status
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

- The menu bar shows remaining usage as `C` (Claude) and `X` (Codex), for example
  `C 76% · X 47%`. It omits a provider that has no available snapshot.
- Click the percentage to open the card.
- Double-click the card to toggle Compact size.
- Right-click the card to choose Compact/Full size and opacity
  (100%, 85%, 70%, or 55%).
- Compact size shows provider bars and percentages only, without reset times.
- Size and opacity are remembered after quitting or restarting the Mac.
- Clawstatus refreshes every 60 seconds through Claude Code `/usage` and a
  short-lived official Codex app-server process. It does not read, store, log,
  or refresh OAuth tokens, including `~/.codex/auth.json`.

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
