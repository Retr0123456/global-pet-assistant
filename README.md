# Global Pet Assistant

Global Pet Assistant is a lightweight macOS desktop pet and local notification runtime. It is inspired by the Codex App pet feature, but is designed as a standalone system-level assistant that can receive events from Codex CLI, Claude Code, CI systems, local scripts, and other third-party tools.

The project goal is to separate the pet into two layers:

- A native macOS pet renderer built with AppKit and Core Animation.
- A local event interface that any trusted tool can use to drive pet state, notifications, and actions.

## Status

- Public source beta for macOS 26 and the AppKit Liquid Glass SDK.
- Public beta release downloads are published on GitHub, but they are not notarized yet. You can also build from source or package a local beta from this checkout.
- The event API is local-only. Mutating writes require a bearer token generated on first app launch.
- Blobbit, an original generated default pet, is bundled and installed into the app-owned pet folder on first launch. Users can import compatible local pet packages.

## Goals

- Provide a global, always-available notification pet on macOS.
- Use a lightweight native implementation instead of Electron.
- Support the Codex pet spritesheet resource format.
- Expose a stable local event API for CLI tools, agents, CI notifications, and local apps.
- Support clickable actions such as opening an app, URL, file, folder, or agent session.
- Keep the event API local-first and safe by default.

## Design Boundary

Global Pet Assistant is a desktop pet, local notification runtime, and safe focus
surface for development tools. The product boundary is notification plus focus:

- Keep pet state, animation playback, window behavior, and transient desktop
  interactions reliable before expanding integrations.
- Accept short command flash notifications from shells, build scripts, terminal
  plugins, and local tools.
- Accept long-lived coding-agent lifecycle notifications from trusted hooks or
  structured plugin events, then show them in the thread panel.
- Focus the relevant app, terminal window, tab, or session when a trusted
  integration provides enough structured target metadata.
- Do not use terminal plugins for reverse input, text injection, permission
  approval, permission denial, or raw TUI control.

Terminal integrations are notification and focus adapters. Without a terminal
plugin, the app can focus the terminal application. With a trusted terminal
plugin, the app can focus a more specific terminal surface such as a kitty window,
tab, or session. Any future agent-control feature must come from a first-class
agent or app-server protocol, not from typing into a terminal.

## Primary Use Cases

- Codex CLI or Claude Code hooks notify the pet when a task starts, completes, fails, or waits for input.
- CI or local build systems notify the pet when a build fails or recovers.
- Third-party apps send local notifications to the pet through a generic event API.
- The pet acts as a small global notification assistant, not just a decorative mascot.

## Recommended Architecture

```text
hooks / scripts / terminal plugins / agents
        |
        v
notification ingress
        |
        +--> command flash projection
        |
        +--> agent session registry
        |
        v
event router + thread projection
        |
        +--> pet state machine
        |
        +--> focus router
        |
        v
AppKit / Core Animation renderer
```

## Core Scope

1. Native macOS transparent floating pet window.
2. Core Animation spritesheet renderer.
3. Codex-compatible 8x9 pet atlas support.
4. Local event API over localhost HTTP or Unix domain socket.
5. `petctl` command-line helper for scripts and agent hooks.
6. Pet states: `idle`, `running`, `waiting`, `failed`, `review`, `waving`, `jumping`, `running-left`, and `running-right`.
7. Click action for the latest actionable notification.
8. Menu bar and right-click controls for visibility, muting, focus timers, animation preview, and pet folder access.

## Current Implementation

The repository currently starts with a Swift Package executable instead of an Xcode project. This keeps the first implementation buildable with the installed Swift toolchain and avoids depending on `xcodebuild`.

- App name: `GlobalPetAssistant`
- App bundle identifier: `io.github.globalpetassistant.GlobalPetAssistant`
- Minimum platform: macOS 26 with the AppKit Liquid Glass SDK
- Runtime shape: AppKit lifecycle and floating `NSPanel`
- Renderer shape: Core Animation layer playback from a Codex-compatible atlas, with Liquid Glass AppKit controls for notification surfaces
- Bundled default pet: `Sources/GlobalPetAssistant/Resources/BundledPets/blobbit`
- App icon: original generated image under `Assets/AppIcon`
- Startup pet loading: first compatible pet in `~/.global-pet-assistant/pets`; Blobbit is installed there on first launch as the bundled default fallback
- App-owned state root: `~/.global-pet-assistant`
- Event safety: localhost-only HTTP, request size limits, source-level rate limiting, source action allowlisting, and conservative click-action validation

Build and run:

```bash
swift build
swift run GlobalPetAssistant
```

Local event API:

```bash
PET_TOKEN="$(tr -d '\r\n' < ~/.global-pet-assistant/token)"

curl -X POST http://127.0.0.1:17321/events \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $PET_TOKEN" \
  -d '{"source":"manual","type":"task.completed","level":"success","title":"Task complete"}'

swift run petctl notify --level success --title "Task complete"
swift run petctl flash --level success --message "swift test passed"
swift run petctl flash --level danger --message "build failed"
swift run petctl run -- swift test
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
  --action-folder "$PWD"
swift run petctl notify \
  --source local-build \
  --level danger \
  --title "Open build log" \
  --action-file "$HOME/.global-pet-assistant/logs/local-build-latest.log"
swift run petctl notify \
  --source codex-cli \
  --level success \
  --title "Open Codex" \
  --action-app "com.openai.codex"

curl -fsS http://127.0.0.1:17321/healthz
```

## Kitty Plugin

The preferred kitty integration is a kitty global watcher. It observes shell
command start/end events, posts structured terminal events to the local app, and
can provide kitty target metadata for trusted focus/reply actions.

Release downloads and the complete installation, verification, disable, and
legacy compatibility instructions live in the
[Kitty Plugin Install Guide](plugins/kitty/README.md).

`/healthz` returns the app liveness status plus the router snapshot (`state` and `activeEvents`) so scripts can distinguish a reachable app from an idle or busy pet.

Thread panel notifications are long-lived: they stay visible until the user
dismisses the row with the panel close button. Transient flash messages still
use short TTL expiry.

`GET /healthz` does not require authentication. `POST /events` requires a local
bearer token from `~/.global-pet-assistant/token`. The app creates that token on
first launch with file permissions set to `0600`, and `petctl` reads it
automatically.

Source-level rate limits are in memory and reset when the app restarts:

| Source | Limit |
| --- | ---: |
| `codex-cli` | 30 events / 60 seconds |
| `claude-code` | 30 events / 60 seconds |
| `ci` | 10 events / 60 seconds |
| unknown/default | 20 events / 60 seconds |

`GET /healthz` and `clear` events are exempt. A limited source receives HTTP `429` with JSON error `rate_limited` and `retryAfterMs`.

Action allowlisting and pet import source directories are loaded from `~/.global-pet-assistant/config.json`. The app writes a default config on first launch. If that file becomes invalid JSON or no longer matches the schema, the app backs it up as `config.invalid-<timestamp>.json` and regenerates defaults. Unknown sources can still update pet state, but events with actions are rejected with HTTP `403` and JSON error `action_not_allowed`.

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
| `PET_LOG_PATH` | Latest local build log path; defaults to `~/.global-pet-assistant/logs/local-build-latest.log`. |

Codex lifecycle hooks are available as opt-in examples under `examples/codex-hooks/`.
They are not enabled by default in the public checkout.

To enable them for every Codex session on this machine:

```bash
Tools/install-codex-hooks.sh
```

If you installed from a release app instead of a source checkout:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/install-codex-hooks.sh
```

This installs a user-level hook under `~/.codex/`, so sessions launched from
different directories can all notify the same pet app.

To enable them for this repository only:

```bash
mkdir -p .codex
cp examples/codex-hooks/config.toml .codex/config.toml
cp examples/codex-hooks/hooks.json .codex/hooks.json
```

The example config enables:

```toml
[features]
codex_hooks = true
```

After restarting Codex, trust this repository's `.codex/` config layer if
prompted. The example hook forwards `SessionStart`, `UserPromptSubmit`,
`PermissionRequest`, and `Stop` to this app's event API. Use
`Tools/codex-pet-events.sh disable` to globally stop Codex-side event pushes to
the pet app, and `Tools/codex-pet-events.sh enable` to turn them back on. See
[Codex Hook Integration](docs/codex-hook-integration.md).

Local webhook bridge:

```bash
swift run pet-webhook-bridge
```

The bridge is off unless explicitly started. It binds only to `127.0.0.1:17322`,
requires the same local bearer token for incoming `POST /github-actions`
requests, and forwards normalized `ci` events to `POST /events` with that token:

```bash
PET_TOKEN="$(tr -d '\r\n' < ~/.global-pet-assistant/token)"

curl -X POST http://127.0.0.1:17322/github-actions \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $PET_TOKEN" \
  -d '{
    "workflow_run": {
      "id": 12345,
      "name": "CI",
      "conclusion": "failure",
      "html_url": "https://github.com/Retr0123456/global-pet-assistant/actions/runs/12345"
    },
    "repository": {
      "full_name": "Retr0123456/global-pet-assistant"
    }
  }'
```

Pet package commands:

```bash
swift run petctl open-folder
swift run petctl open-logs
swift run petctl import-pet <name>
swift run petctl import-codex-pet <name>
find ~/.global-pet-assistant/pets/<name> -maxdepth 1 -type f
```

The importer searches `petImportSourceDirectories` from
`~/.global-pet-assistant/config.json`, which defaults to `~/.codex/pets`.
It validates `pet.json`, requires a safe manifest-local spritesheet filename, checks
that the atlas is `1536x1872`, and then copies the package into the app-owned pet
folder. It does not symlink into Codex state. `import-codex-pet` is kept as a
compatibility alias for `import-pet`.

Pet packages are not open-sourced by default. The app can render
Codex-compatible pet packages directly, but third-party pet spritesheets or
character art should only be committed when their redistribution license is
clear. See [Assets And Licensing](docs/assets-and-licensing.md).

GUI pet switching is available from the menu bar item and the pet right-click
menu under `Switch Pet`. The submenu lists compatible installed packages from
`~/.global-pet-assistant/pets`, marks the current pet with a checkmark, and
applies a new selection immediately. The selected pet persists across launches.

Manual event-runtime verification:

```bash
Tools/verify-event-runtime.sh
Tools/verify-codex-hook-events.sh
```

Audit logs are written as JSONL under `~/.global-pet-assistant/logs`:

| File | Purpose |
| --- | --- |
| `runtime.jsonl` | App startup, pet loading, event-server bind/listen failures, show/hide actions. |
| `events.jsonl` | Local event API receive/accept/reject decisions, source, type, state, title, TTL, and error details. |
| `codex-hook-events.jsonl` | Codex hook mapping, disabled/ignored status, send success, and send failure details. |

Run unit tests:

```bash
swift test
```

Build a local debug `.app` that can be opened through macOS LaunchServices:

```bash
Tools/package-debug-app.sh
open .build/GlobalPetAssistant.app
```

Build an ad-hoc signed release `.app` zip and checksum:

```bash
Tools/package-release-app.sh
open .build/release/GlobalPetAssistant.app
```

In restricted agent sandboxes where SwiftPM's own sandbox cannot start, set:

```bash
SWIFT_BUILD_FLAGS=--disable-sandbox Tools/package-release-app.sh
```

## Install

Download the latest beta DMG from
<https://github.com/Retr0123456/global-pet-assistant/releases/latest>, drag
`GlobalPetAssistant.app` into `/Applications`, then launch it:

```bash
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
```

Local beta install from a built checkout:

```bash
Tools/package-release-app.sh
ditto .build/release/GlobalPetAssistant.app /Applications/GlobalPetAssistant.app
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
```

Release apps include helper binaries under
`GlobalPetAssistant.app/Contents/Resources/bin`. From a source checkout, keep
using `swift run petctl`; from an installed release app, use the bundled helper:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl notify --level success --title "Installed app is reachable"
```

## Upgrade

```bash
Tools/package-release-app.sh
osascript -e 'tell application "Global Pet Assistant" to quit' || true
ditto .build/release/GlobalPetAssistant.app /Applications/GlobalPetAssistant.app
open /Applications/GlobalPetAssistant.app
```

App state, logs, preferences, and imported pet packages live under
`~/.global-pet-assistant` and are not removed by replacing the app bundle.

## Uninstall

Quit the app from the menu bar, then remove the app bundle:

```bash
rm -rf /Applications/GlobalPetAssistant.app
```

Remove app-owned state only if you also want to delete logs, preferences, and
imported pet packages:

```bash
rm -rf ~/.global-pet-assistant
```

If you installed local Codex hook examples, remove the local project hook layer:

```bash
rm -rf .codex
```

## Runtime Files

Global Pet Assistant stores local state in `~/.global-pet-assistant`:

| Path | Purpose |
| --- | --- |
| `config.json` | Source action allowlist and pet import source directories. |
| `event-preferences.json` | Pause and muted-source preferences. |
| `selected-pet` | Current GUI-selected pet package id. |
| `window-origin.json` | Saved pet position. |
| `pets/` | App-owned imported pet packages. |
| `logs/` | Runtime, event, and hook audit logs. |
| `token` | Local bearer token required for `POST /events`. |

Launch-at-login is controlled from the menu bar item. Enabling it registers the
installed app with macOS Login Items; disabling it removes that registration.

## Release Identity

- Bundle identifier: `io.github.globalpetassistant.GlobalPetAssistant`.
- Current package script: ad-hoc signed local beta zip; GitHub beta releases can
  wrap the packaged app in a DMG.
- Public stable releases should use Developer ID signing and notarization.
- `Tools/package-release-app.sh` writes `GlobalPetAssistant.zip.sha256` next to
  the release zip.

Regenerate the app icon from `Assets/AppIcon/AppIcon.png`:

```bash
Tools/generate-app-icon.sh
```

The menu bar item uses a system icon and includes show/hide, pause events, mute current source, unmute all sources, focus timer, preview state, open pet folder, and quit controls. Right-clicking the pet exposes the fast controls: open action, clear current event, mute source, unmute all sources, pause/resume events, preview state, and open pet folder. Pet position is saved under `~/.global-pet-assistant` after drag moves, snaps to visible screen edges within 24 px, and is restored on relaunch.

The bundled default pet is an original generated Codex-compatible package under
`Sources/GlobalPetAssistant/Resources/BundledPets/blobbit`.

## Documentation

- [Architecture](docs/architecture.md)
- [Notification And Focus Architecture Reduction Plan](docs/notification-focus-architecture-reduction-plan.md)
- [Assets And Licensing](docs/assets-and-licensing.md)
- [Codex Hook Integration](docs/codex-hook-integration.md)
- [Kitty Plugin Install Guide](plugins/kitty/README.md)
- [Desktop Pet Experience Plan](docs/desktop-experience-plan.md)
- [Daily-driver MVP Task List](docs/daily-driver-mvp.md)
- [Release Candidate Plan](docs/release-candidate-plan.md)
- [Post-RC Roadmap](docs/post-rc-roadmap.md)
- [Open Source Checklist](docs/open-source-checklist.md)
- [Security Policy](SECURITY.md)
- [Privacy](PRIVACY.md)
- [Contributing](CONTRIBUTING.md)
- [TODO](TODO.md)
