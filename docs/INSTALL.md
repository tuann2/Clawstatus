# Install and use Clawstatus

## Requirements

- Apple Silicon Mac
- macOS 13 Ventura or newer
- Homebrew (only required for the recommended installation method)
- At least one installed, updated, and signed-in provider: Claude Code, Codex
  CLI, or both

Verify both installed CLIs:

```bash
claude --version
claude auth status
codex --version
codex login status
```

It is fine if only one CLI is installed. Clawstatus hides providers that do not
have an available usage snapshot.

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

## Install from the DMG

Download the DMG and `.sha256` file from the
[Clawstatus 0.4.0 release](https://github.com/tuann2/Clawstatus/releases/tag/v0.4.0).
Verify the installer, open it, and drag Clawstatus to Applications:

```bash
cd ~/Downloads
shasum -a 256 -c Clawstatus-0.4.0-apple-silicon.dmg.sha256
open Clawstatus-0.4.0-apple-silicon.dmg
```

Then remove quarantine from this app only and launch it:

```bash
xattr -dr com.apple.quarantine /Applications/Clawstatus.app
open -a Clawstatus
```

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
