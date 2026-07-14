# Clawstatus for macOS

Clawstatus is a small native macOS menu-bar monitor for Claude Code usage limits.
It is built with SwiftUI, uses no third-party dependencies, and does not use a
browser or webview.

## What it does

- Runs the installed Claude Code CLI headlessly with
  `claude -p --no-session-persistence /usage` every 60 seconds and reads its
  plain-text usage report. The process runs in an isolated app-owned directory
  with tools, MCP servers, and project/user settings disabled, so it does not
  request access to Desktop, Documents, projects, or other protected folders.
- Always shows the remaining percentage of the current 5-hour session directly
  in the menu bar (for example, `76%`).
- Shows the 5-hour and 7-day usage windows in the floating HUD.
- Opens a small floating HUD on launch and keeps a menu-bar control for reopening.
- Keeps the last successful usage snapshot in
  `~/Library/Application Support/Clawstatus/state.json`.
- Never reads, saves, logs, or refreshes OAuth tokens; Claude Code handles its
  own authentication and the only saved data is the last usage snapshot.
- The **Sign in** action opens the installed Claude Code CLI in Terminal; after
  authentication, use refresh or wait for the next 60-second poll.

## Build

Requires macOS 13 or newer and Apple Command Line Tools.

```bash
cd macos
swift run ClawlineCheck
./scripts/build-app.sh
open dist/Clawstatus.app
```

The packaged application is written to `macos/dist/Clawstatus.app`. It is signed
ad hoc for local use and is not uploaded or distributed by the build script.

## Install on Apple Silicon

Requirements: Apple Silicon, macOS 13 or newer, and an installed, signed-in
Claude Code CLI that supports headless `/usage`.

Create the drag-to-Applications installer:

```bash
./macos/scripts/package-dmg.sh
```

Open `macos/dist/Clawstatus-0.2.0-apple-silicon.dmg`, then drag Clawstatus to
Applications. This build is ad-hoc signed rather than Apple-notarized, so on the
first launch use Control-click → Open and confirm once if Gatekeeper asks.

## Project layout

- `macos/Sources/Clawline/` — native application code
- `macos/Sources/ClawlineCore/` — polling, parsing, and local cache logic
- `macos/Sources/ClawlineCheck/` — dependency-free executable checks
- `macos/Resources/Info.plist` — menu-bar application metadata
- `macos/scripts/build-app.sh` — local `.app` packager

The previous browser prototype remains in the repository for now, but it is not
used by the macOS application.
