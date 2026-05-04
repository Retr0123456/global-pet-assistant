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
- Startup pet loading: first compatible pet in `~/.global-pet-assistant/pets`, then `~/.codex/pets`, then bundled placeholder fallback
- App-owned state root: `~/.global-pet-assistant`
- Event safety: localhost-only HTTP, request size limits, source-level rate limiting, source action allowlisting, and conservative click-action validation

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
swift run petctl notify \
  --source codex-cli \
  --level success \
  --title "Open repo" \
  --action-url "https://github.com/Retr0123456/global-pet-assistant"
swift run petctl notify \
  --source local-build \
  --level warning \
  --title "Open project folder" \
  --action-folder "/Users/ryanchen/codespace/global-pet-assistant"
swift run petctl notify \
  --source local-build \
  --level danger \
  --title "Open build log" \
  --action-file "/Users/ryanchen/.global-pet-assistant/logs/local-build-latest.log"
swift run petctl notify \
  --source codex-cli \
  --level success \
  --title "Open Codex" \
  --action-app "com.openai.codex"

curl -fsS http://127.0.0.1:17321/healthz
```

`/healthz` returns the app liveness status plus the router snapshot (`state` and `activeEvents`) so scripts can distinguish a reachable app from an idle or busy pet.

Source-level rate limits are in memory and reset when the app restarts:

| Source | Limit |
| --- | ---: |
| `codex-cli` | 30 events / 60 seconds |
| `claude-code` | 30 events / 60 seconds |
| `ci` | 10 events / 60 seconds |
| unknown/default | 20 events / 60 seconds |

`GET /healthz` and `clear` events are exempt. A limited source receives HTTP `429` with JSON error `rate_limited` and `retryAfterMs`.

Action allowlisting is loaded from `~/.global-pet-assistant/config.json`. The app writes a default config on first launch. If that file becomes invalid JSON or no longer matches the schema, the app backs it up as `config.invalid-<timestamp>.json` and regenerates defaults. Unknown sources can still update pet state, but events with actions are rejected with HTTP `403` and JSON error `action_not_allowed`.

Hook examples live under `examples/hooks/`:

```bash
examples/hooks/codex-task.sh running
examples/hooks/codex-task.sh success
examples/hooks/claude-task.sh running
examples/hooks/local-build.sh swift build
```

Each example is a thin wrapper around `petctl`. Copy the relevant script into the hook directory used by Codex CLI, Claude Code, or a local build pipeline, or call it in place from this checkout. Common environment variables:

| Variable | Meaning |
| --- | --- |
| `PETCTL` | Command used to invoke `petctl`; defaults to `swift run petctl`. |
| `PET_SOURCE` | Event source; defaults to `codex-cli`, `claude-code`, or `local-build`. |
| `PET_DEDUPE_KEY` | Dedupe key used to replace repeated task events. |
| `PET_MESSAGE` | Message shown in the event payload. |
| `PET_TITLE` | Title for notify-style events. |
| `PET_TTL_MS` | TTL for running/waiting events. |
| `PET_ACTION_FOLDER` | Folder opened when an actionable failure/success notification is clicked. |
| `PET_LOG_PATH` | Latest local build log path; defaults to `/Users/ryanchen/.global-pet-assistant/logs/local-build-latest.log`. |

Pet package commands:

```bash
swift run petctl open-folder
swift run petctl import-codex-pet emma
find ~/.global-pet-assistant/pets/emma -maxdepth 1 -type f
```

The importer copies `pet.json` and the manifest's referenced spritesheet into the app-owned pet folder. It does not symlink into Codex state.

Manual event-runtime verification:

```bash
Tools/verify-event-runtime.sh
```

Run unit tests:

```bash
swift test
```

Build a local debug `.app` that can be opened through macOS LaunchServices:

```bash
Tools/package-debug-app.sh
open .build/GlobalPetAssistant.app
```

Build a signed release `.app` zip:

```bash
Tools/package-release-app.sh
open .build/release/GlobalPetAssistant.app
```

The menu bar item uses a system icon and includes show/hide, pause events, mute current source, unmute all sources, launch-at-login, move-to-next-display, open pet folder, and quit controls. Right-clicking the pet exposes the fast controls: open action, clear current event, mute source, unmute all sources, pause/resume events, and open pet folder. Pet position is saved under `~/.global-pet-assistant` after drag moves, snaps to visible screen edges within 24 px, and is restored on relaunch.

Regenerate the bundled placeholder atlas:

```bash
swift Tools/GeneratePlaceholderAtlas.swift Sources/GlobalPetAssistant/Resources/SamplePets/placeholder/spritesheet.png
```

## Documentation

- [Architecture](docs/architecture.md)
- [Desktop Pet Experience Plan](docs/desktop-experience-plan.md)
- [Daily-driver MVP Task List](docs/daily-driver-mvp.md)
- [Release Candidate Plan](docs/release-candidate-plan.md)
- [Post-RC Roadmap](docs/post-rc-roadmap.md)
- [TODO](TODO.md)
