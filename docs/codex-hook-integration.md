# Codex Hook Integration

This repository includes opt-in Codex hook examples that forward Codex lifecycle events to the local pet event API at `http://127.0.0.1:17321/events`.

## Official Codex Surface

Codex lifecycle hooks are enabled with:

```toml
[features]
codex_hooks = true
```

Codex loads hooks from `hooks.json` or inline `[hooks]` tables next to active config layers. The useful locations include `~/.codex/hooks.json`, `~/.codex/config.toml`, `<repo>/.codex/hooks.json`, and `<repo>/.codex/config.toml`.

The public checkout keeps hook templates under `examples/codex-hooks/` instead of shipping an active `.codex/` layer. Codex only loads project-local hooks after you copy the examples into `.codex/` and trust that config layer.

## Event Mapping

The hook script is `examples/codex-hooks/hooks/codex-pet-event.py`. It reads the Codex hook JSON object from stdin and posts a `LocalPetEvent` JSON payload to the app.

| Codex hook | Pet event | Pet state | Purpose |
| --- | --- | --- | --- |
| `SessionStart` | `codex.session.start` | `running` | Conversation/session opened or resumed. |
| `UserPromptSubmit` | `codex.turn.running` | `running` | User submitted a prompt and Codex started work. |
| `PermissionRequest` | `codex.permission.request` | `waiting` via warning level | Codex is waiting for approval of a command or permission request. |
| `Stop` | `codex.turn.review` | `review` via success level | Codex finished the turn and the result is ready for review. |

The source is `codex-cli:<stable-session-key>` and the dedupe key is `codex:<session_id>`, so repeated lifecycle events for the same Codex thread update one active pet thread instead of creating duplicates. The stable session key includes a hash of the full Codex session id instead of a short prefix, which keeps multiple Codex sessions distinct even when their time-sorted ids share the same prefix. The hook sends Codex's current working directory as a separate `cwd` field; the pet UI uses its last path component as the message area's directory label.

When Codex runs inside kitty and the hook inherits `KITTY_WINDOW_ID` plus `KITTY_LISTEN_ON`, the hook also attaches a `focus_kitty_window` action. Clicking the message area asks kitty to focus the matching window id, which also switches to the containing kitty tab. This requires kitty remote control over a socket, for example:

```conf
allow_remote_control socket-only
listen_on unix:/tmp/global-pet-kitty.sock
```

## Enable The Hooks

Copy the opt-in examples into a local `.codex/` directory:

```bash
mkdir -p .codex
cp examples/codex-hooks/config.toml .codex/config.toml
cp examples/codex-hooks/hooks.json .codex/hooks.json
```

The example `config.toml` enables:

```toml
[features]
codex_hooks = true
```

Restart Codex and trust this repository's `.codex/` config layer if prompted. If you prefer a user-level configuration instead, add the same feature flag to `~/.codex/config.toml` and point your hooks at the absolute path of `examples/codex-hooks/hooks/codex-pet-event.py`.

## Global Push Disable Switch

The hook script supports two Codex-side global off switches. When either switch is active, it exits without contacting the pet app.

Environment variable:

```bash
export CODEX_PET_EVENTS_DISABLED=1
```

Persistent local switch:

```bash
Tools/codex-pet-events.sh disable
Tools/codex-pet-events.sh status
Tools/codex-pet-events.sh enable
```

The persistent switch is the file `~/.codex/global-pet-assistant-disabled`.

## Verification

Validate the hook mapping without contacting the running app:

```bash
Tools/verify-codex-hook-events.sh
```

Manually test the app-facing event path:

```bash
swift run GlobalPetAssistant
Tools/verify-event-runtime.sh
```

The hook script intentionally ignores local app connection failures so Codex work is never blocked by the pet app being closed.

## Audit Logs

The Codex hook script and app runtime both write JSONL logs under `~/.global-pet-assistant/logs`:

```bash
tail -n 50 ~/.global-pet-assistant/logs/codex-hook-events.jsonl
tail -n 50 ~/.global-pet-assistant/logs/events.jsonl
tail -n 50 ~/.global-pet-assistant/logs/runtime.jsonl
```

Use the hook log to confirm whether Codex produced a hook and whether the hook sent or skipped the event. Use the app event log to confirm whether the app accepted, rate-limited, or rejected the payload.
