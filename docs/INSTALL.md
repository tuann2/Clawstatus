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
normally preserves macOS quarantine, which makes Gatekeeper reject this build.
The command below explicitly disables quarantine for this cask. Only use it if
you trust this repository; the cask pins and verifies the release SHA-256.

```bash
brew tap tuann2/clawstatus https://github.com/tuann2/Clawstatus
HOMEBREW_CASK_OPTS=--no-quarantine brew install --cask clawstatus
```

Open it from Applications or run:

```bash
open -a Clawstatus
```

## Upgrade

```bash
brew update
HOMEBREW_CASK_OPTS=--no-quarantine brew upgrade --cask clawstatus
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

If Clawstatus was installed manually and macOS shows “Not Opened”, remove the
manual copy and reinstall it with the Homebrew commands above. Do not disable
Gatekeeper system-wide.

The permanent distribution fix is signing with an Apple Developer ID and
notarizing the app. Once notarized builds are available, the
`HOMEBREW_CASK_OPTS=--no-quarantine` override will no longer be necessary.
