# Global Pet Assistant

Global Pet Assistant is a lightweight macOS desktop pet and local notification runtime. It is inspired by the Codex App pet feature, but is designed as a standalone system-level assistant that can receive events from Codex CLI, Claude Code, CI systems, local scripts, and other third-party tools.

The project goal is to separate the pet into two layers:

- A native macOS pet renderer built with AppKit, SwiftUI, and Core Animation.
- A local event interface that any trusted tool can use to drive pet state, notifications, and actions.

## Goals

- Provide a global, always-available notification pet on macOS.
- Use a lightweight native implementation instead of Electron.
- Support the Codex pet spritesheet resource format.
- Expose a stable local event API for CLI tools, agents, CI notifications, and local apps.
- Support clickable actions such as opening an app, URL, file, folder, or agent session.
- Keep the event API local-first and safe by default.

## Primary Use Cases

- Codex CLI or Claude Code hooks notify the pet when a task starts, completes, fails, or waits for input.
- CI or local build systems notify the pet when a build fails or recovers.
- Third-party apps send local notifications to the pet through a generic event API.
- The pet acts as a small global notification assistant, not just a decorative mascot.

## Recommended Architecture

```text
third-party hooks / apps / agents
        |
        v
global event API
        |
        v
event router + priority queue
        |
        v
pet state machine
        |
        v
AppKit / SwiftUI / Core Animation renderer
```

## MVP Scope

1. Native macOS transparent floating pet window.
2. Core Animation spritesheet renderer.
3. Codex-compatible 8x9 pet atlas support.
4. Local event API over localhost HTTP or Unix domain socket.
5. `petctl` command-line helper for scripts and agent hooks.
6. Basic states: `idle`, `running`, `waiting`, `failed`, `review`, and `jumping`.
7. Click action for the latest actionable notification.
8. Menu bar controls for show, hide, open pet folder, and quit.

## Current Implementation

The repository currently starts with a Swift Package executable instead of an Xcode project. This keeps the first implementation buildable with the installed Swift toolchain and avoids depending on `xcodebuild`.

- App name: `GlobalPetAssistant`
- Future app bundle identifier: `com.ryanchen.GlobalPetAssistant`
- Runtime shape: AppKit lifecycle and floating `NSPanel`
- Renderer shape: Core Animation layer playback from a Codex-compatible atlas
- Bundled test pet: `Sources/GlobalPetAssistant/Resources/SamplePets/placeholder`
- Startup pet loading: first compatible pet in `~/.codex/pets`, then bundled placeholder fallback
- App-owned state root: `~/.global-pet-assistant`

Build and run:

```bash
swift build
swift run GlobalPetAssistant
```

Local event API:

```bash
curl -X POST http://127.0.0.1:17321/events \
  -H 'Content-Type: application/json' \
  -d '{"source":"manual","type":"task.completed","level":"success","title":"Task complete"}'

swift run petctl notify --level success --title "Task complete"
swift run petctl state running --message "Working..."
swift run petctl clear

curl -fsS http://127.0.0.1:17321/healthz
```

`/healthz` returns the app liveness status plus the router snapshot (`state` and `activeEvents`) so scripts can distinguish a reachable app from an idle or busy pet.

Manual event-runtime verification:

```bash
Tools/verify-event-runtime.sh
```

Build a local debug `.app` that can be opened through macOS LaunchServices:

```bash
Tools/package-debug-app.sh
open .build/GlobalPetAssistant.app
```

Regenerate the bundled placeholder atlas:

```bash
swift Tools/GeneratePlaceholderAtlas.swift Sources/GlobalPetAssistant/Resources/SamplePets/placeholder/spritesheet.png
```

## Documentation

- [Architecture](docs/architecture.md)
- [TODO](TODO.md)
