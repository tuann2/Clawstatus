# Repository Guidelines

## Project Structure

This repository contains a native macOS menu-bar application:

- `macos/Sources/Clawline/` — SwiftUI and AppKit interface
- `macos/Sources/ClawlineCore/` — Claude CLI polling, parsing, and cache logic
- `macos/Sources/ClawlineCheck/` — dependency-free verification executable
- `macos/Resources/` — application bundle metadata
- `macos/scripts/` — build and packaging scripts

## Build and Verification

Run from the repository root:

- `swift run --package-path macos ClawlineCheck` — validate parsing and credential handling
- `./macos/scripts/build-app.sh` — build and locally ad-hoc-sign `macos/dist/Clawstatus.app`
- `open macos/dist/Clawstatus.app` — launch the packaged menu-bar app

## Coding Style

- Use Swift concurrency and SwiftUI/AppKit APIs available on macOS 13 or newer.
- Keep the application dependency-free.
- Use 4 spaces and standard Swift naming: `PascalCase` types, `camelCase` members.
- Never log, cache, or serialize OAuth credentials. The only persisted application state is a usage snapshot.

## Commit Guidance

- Use short imperative messages, for example `Add Claude usage parser`.
- Keep source and generated artifacts separate. Do not commit `macos/.build/` or `macos/dist/`.
