# Architecture

## Product Definition

Global Pet Assistant is a local notification runtime with a pet renderer. The pet is the visible surface, but the core product is the local event protocol, event router, notification queue, and state machine.

The system should not depend on Codex App internals. It should support Codex-compatible resources, while using its own storage, event API, and runtime process.

## Native macOS Runtime

The preferred implementation is:

```text
Swift / AppKit
+ transparent NSPanel or NSWindow
+ SwiftUI or NSView controls
+ Core Animation spritesheet renderer
+ local event server
```

The first repository implementation uses a Swift Package executable target. AppKit owns the application lifecycle and floating panel. SwiftUI is intentionally deferred until there is a settings or richer menu UI that benefits from it.

AppKit should own the floating window behavior:

- Transparent window.
- Always-on-top mode.
- Optional click-through transparent regions.
- Drag-to-move behavior.
- Multi-display placement.
- Screen-edge snapping.
- Menu bar control.
- Launch at login.

Core Animation should own sprite playback:

- Preload spritesheets into memory.
- Avoid decoding images during animation.
- Switch frame source rects or layer contents positions.
- Target smooth playback around 15 FPS or the per-state frame durations.
- Respect Reduced Motion by holding the first frame or using minimal motion.

## Pet Resource Format

The renderer should support the Codex pet atlas format:

```text
Format: PNG or WebP
Dimensions: 1536x1872
Grid: 8 columns x 9 rows
Cell: 192x208
Background: transparent
```

Rows:

| Row | State | Used columns |
| --- | --- | ---: |
| 0 | idle | 0-5 |
| 1 | running-right | 0-7 |
| 2 | running-left | 0-7 |
| 3 | waving | 0-3 |
| 4 | jumping | 0-4 |
| 5 | failed | 0-7 |
| 6 | waiting | 0-5 |
| 7 | running | 0-5 |
| 8 | review | 0-5 |

Custom pet packages should live in this app's own directory to avoid writing into Codex App state:

```text
~/.global-pet-assistant/pets/<pet-name>/
├── pet.json
└── spritesheet.webp
```

Recommended manifest:

```json
{
  "id": "pet-name",
  "displayName": "Pet Name",
  "description": "One short sentence.",
  "spritesheetPath": "spritesheet.webp"
}
```

The app can later add an import command that copies compatible pets from `~/.codex/pets`.

## Event API

The event system should expose a stable local interface. Recommended transports:

- Localhost HTTP for broad compatibility.
- Unix domain socket for safer local CLI integration.
- `petctl` CLI as the ergonomic wrapper for scripts and agent hooks.

Example commands:

```bash
petctl notify --source codex-cli --level success --title "Task complete"
petctl state running --source claude-code --message "Editing files"
curl -X POST http://127.0.0.1:17321/events -d '{"source":"ci","type":"build.failed","level":"danger","title":"CI failed"}'
```

Recommended event schema:

```json
{
  "source": "codex-cli",
  "type": "task.completed",
  "level": "success",
  "title": "Task completed",
  "message": "Edited 3 files",
  "state": "review",
  "action": {
    "type": "open_url",
    "url": "codex://thread/example"
  },
  "ttlMs": 600000,
  "dedupeKey": "codex-thread-example"
}
```

## State Machine

Global notifications can conflict, so the pet needs explicit state priority:

```text
failed > waiting > running > review > idle
```

Rules:

- Track state by source.
- Let newer events from the same source replace old running states.
- Preserve failed and waiting states longer than running states.
- Auto-expire running states.
- Deduplicate repeated notifications by `dedupeKey`.
- Rate limit noisy sources.
- Fall back to `idle` when no active notification remains.

Suggested state mapping:

| Event level/state | Pet state |
| --- | --- |
| `danger`, `failed` | `failed` |
| `warning`, `waiting` | `waiting` |
| `success`, `completed`, unread actionable result | `review` |
| `info`, `started`, `running` | `running` |
| no active event | `idle` |

Pointer interactions may temporarily override the current state:

- Hover or click: `jumping` or `waving`.
- Drag right: `running-right`.
- Drag left: `running-left`.

After the transient animation ends, the pet should return to the state selected by the router.

## Action System

Notifications may include a click action. Supported action types should be conservative:

```json
{
  "type": "open_app",
  "bundleId": "com.openai.codex"
}
```

```json
{
  "type": "open_url",
  "url": "https://github.com/org/repo/actions/runs/123"
}
```

```json
{
  "type": "open_file",
  "path": "/Users/example/project/build.log"
}
```

Avoid allowing arbitrary shell command execution by default. If command execution is added later, it should require explicit user approval and source allowlisting.

## Security Model

The event API should be local and locked down:

- Bind HTTP only to `127.0.0.1`.
- Prefer Unix socket for CLI integrations.
- Require a local token for HTTP writes.
- Limit request body size.
- Rate limit high-volume sources.
- Validate URLs and file paths before opening.
- Require source allowlisting for all URL, folder, file, and app-opening actions.
- Reject unknown-source actions while still accepting unknown-source state notifications.
- Do not expose a network-facing webhook listener by default.

The default source allowlist lives in `~/.global-pet-assistant/config.json`. A broken config is backed up and replaced with defaults on startup so the app does not fail closed into an unusable state.

## Adapter Strategy

Adapters should be thin wrappers around the generic event API:

- `codex-hook-adapter`
- `claude-code-hook-adapter`
- `github-actions-adapter`
- `generic-webhook-adapter`
- local script examples using `petctl`

The first version should prioritize the generic API and `petctl`. Specific adapters can be added after the event contract is stable.

## Implementation Notes

- Avoid Electron for the core app.
- Avoid GIF playback for pet animation.
- Avoid image decoding during animation.
- Keep the renderer independent from event sources.
- Keep the event protocol independent from the selected pet.
- Store app-owned state under `~/.global-pet-assistant`.
- Treat Codex pet support as a compatible import/rendering format, not as a dependency on Codex App.
