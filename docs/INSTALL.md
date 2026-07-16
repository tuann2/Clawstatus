# Install and use Clawstatus

This guide covers the 0.5.0 stable release and the current source build.

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

It is fine if only one CLI is installed. Use the provider settings in Clawstatus
to disable a CLI you do not want the app to poll.

## Choose an installation channel

| Channel | Recommended for | Version |
| --- | --- | --- |
| Homebrew Cask | Most users who want published artifacts and checksums | 0.5.0 stable |
| GitHub Release DMG | Manual installation of the stable artifact | 0.5.0 stable |
| Current source build | Testing provider Settings and the widget-style HUD | Current `main` |

## Install the current source build

Install Apple Command Line Tools first if needed:

```bash
xcode-select --install
```

Clone the repository, run its checks, and build the ad-hoc-signed app:

```bash
git clone https://github.com/tuann2/Clawstatus.git
cd Clawstatus
swift run --package-path macos ClawlineCheck
./macos/scripts/build-app.sh
codesign --verify --deep --strict macos/dist/Clawstatus.app
```

Quit any running Clawstatus instance, then install the newly built app:

```bash
ditto macos/dist/Clawstatus.app /Applications/Clawstatus.app
xattr -dr com.apple.quarantine /Applications/Clawstatus.app
open -a Clawstatus
```

The build output under `macos/dist/` is generated locally and is not committed
to the repository.

## Install the stable release with Homebrew

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

## Install the stable release from the DMG

Download the DMG and `.sha256` file from the
[Clawstatus 0.5.0 release](https://github.com/tuann2/Clawstatus/releases/tag/v0.5.0).
Verify the installer, open it, and drag Clawstatus to Applications:

```bash
cd ~/Downloads
shasum -a 256 -c Clawstatus-0.5.0-apple-silicon.dmg.sha256
open Clawstatus-0.5.0-apple-silicon.dmg
```

Then remove quarantine from this app only and launch it:

```bash
xattr -dr com.apple.quarantine /Applications/Clawstatus.app
open -a Clawstatus
```

## Upgrade

Upgrade a Homebrew installation:

```bash
brew update
brew upgrade --cask clawstatus
xattr -dr com.apple.quarantine /Applications/Clawstatus.app
```

Upgrade a source installation:

```bash
cd Clawstatus
git pull --ff-only
swift run --package-path macos ClawlineCheck
./macos/scripts/build-app.sh
codesign --verify --deep --strict macos/dist/Clawstatus.app
ditto macos/dist/Clawstatus.app /Applications/Clawstatus.app
open -a Clawstatus
```

Quit Clawstatus before replacing the app. Provider selection, Compact mode,
opacity, and cached usage remain in your user Library and survive upgrades.

## First-run verification

1. Launch Clawstatus and confirm its menu-bar item appears.
2. Open the HUD and use the gear button to select Claude Code, Codex, or both.
3. Choose **Refresh now**. Each enabled provider should become **Live**, or
   retain a **Cached** snapshot while showing its own error state.
4. Double-click the HUD to verify Compact/Full switching.
5. If a CLI is missing, use **Open Terminal**, install or authenticate it, then
   refresh again. Disabled providers are intentionally not polled.

## Usage

- The menu bar shows remaining usage as `C` (Claude) and `X` (Codex), for example
  `C 76% · X 47%`. It omits a provider that has no available snapshot.
- Click the percentage to open the card.
- Use the gear button or right-click **Providers** to show or hide Claude Code
  and Codex independently. Disabled providers are not polled, and the selection
  is remembered across restarts. If both are disabled, the menu bar shows the
  app icon and the card offers a provider settings shortcut.
- Double-click the card to toggle Compact size.
- Right-click the card to choose Compact/Full size and opacity
  (100%, 85%, 70%, or 55%).
- Full size shows a widget-style card and status for each enabled provider.
  Compact size shows one summary row per provider without reset times.
- If a provider card reports that its CLI is missing, use **Open Terminal** in
  the full card or right-click menu, install/authenticate there, then choose
  **Refresh now**.
- Provider selection, size, and opacity are remembered after quitting or
  restarting the Mac.
- Clawstatus normally refreshes every 60 seconds through Claude Code `/usage`
  and a short-lived official Codex app-server process. If both providers keep
  failing, automatic retries back off to at most 5 minutes. **Refresh now**
  retries immediately and restores the normal interval.
- Saved usage is labeled **Cached** after launch until a provider refresh
  succeeds. Stalled CLI calls are timed out so later refreshes can continue.
- Clawstatus does not read, store, log, or refresh OAuth tokens, including
  `~/.codex/auth.json`.

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

## Provider troubleshooting

Verify the provider outside Clawstatus without exposing credentials:

```bash
claude -p /usage
codex login status
```

- If Claude prints usage in Terminal but its card is temporarily unavailable,
  wait for the next poll or use **Refresh now** once. Clawstatus keeps the last
  successful snapshot instead of discarding it.
- If a card says **Unsupported output**, update that provider CLI and
  Clawstatus. Raw CLI output is never written to the app log.
- If only one provider is installed, disable the other provider from Settings
  to prevent unnecessary process launches and error states.
