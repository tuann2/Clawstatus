# Clawline for macOS

Clawline is a small native macOS menu-bar monitor for Claude Code usage limits.
It is built with SwiftUI, uses no third-party dependencies, and does not use a
browser or webview.

## What it does

- Reads the existing Claude Code OAuth access token from macOS Keychain service
  `Claude Code-credentials`, with `~/.claude/.credentials.json` as a fallback.
- Requests the read-only Anthropic usage endpoint every 60 seconds.
- Shows the 5-hour and 7-day usage windows in the menu bar.
- Opens a small floating HUD on launch and keeps a menu-bar control for reopening.
- Keeps the last successful usage snapshot in
  `~/Library/Application Support/Clawline/state.json`.
- Never logs or stores the access token and has no telemetry.
- The **Sign in** action opens the installed Claude Code CLI in Terminal; after
  authentication, use refresh or wait for the next 60-second poll.

## Build

Requires macOS 13 or newer and Apple Command Line Tools.

```bash
cd macos
swift run ClawlineCheck
./scripts/build-app.sh
open dist/Clawline.app
```

The packaged application is written to `macos/dist/Clawline.app`. It is signed
ad hoc for local use and is not uploaded or distributed by the build script.

## Project layout

- `macos/Sources/Clawline/` — native application code
- `macos/Sources/ClawlineCore/` — polling, parsing, and local cache logic
- `macos/Sources/ClawlineCheck/` — dependency-free executable checks
- `macos/Resources/Info.plist` — menu-bar application metadata
- `macos/scripts/build-app.sh` — local `.app` packager

The previous browser prototype remains in the repository for now, but it is not
used by the macOS application.
