# Codex Hook Integration

This repository includes opt-in Codex hook support that forwards Codex lifecycle events to the local pet through the agent hook bridge and Unix socket.

## Official Codex Surface

Codex lifecycle hooks are enabled with:

```toml
[features]
codex_hooks = true
```

Codex loads hooks from `hooks.json` or inline `[hooks]` tables next to active config layers. The useful locations include `~/.codex/hooks.json`, `~/.codex/config.toml`, `<repo>/.codex/hooks.json`, and `<repo>/.codex/config.toml`.

The public checkout keeps hook templates under `examples/codex-hooks/` instead of shipping an active `.codex/` layer. Codex only loads project-local hooks after you copy the examples into `.codex/` and trust that config layer.

## Event Flow

The managed hook command is `global-pet-agent-bridge --source codex`. The bridge is a short-lived process that reads Codex hook JSON from stdin, captures terminal environment such as `TTY`, `TERM_PROGRAM`, `TMUX_PANE`, and `KITTY_WINDOW_ID`, writes one newline-delimited `AgentHookEnvelope` to the app socket, and exits.

Default socket:

```text
~/.global-pet-assistant/run/agent-hooks.sock
```

Override socket:

```bash
export GLOBAL_PET_AGENT_SOCKET=/path/to/agent-hooks.sock
```

The app receives envelopes through `AgentHookSocketServer`, sends Codex envelopes to `CodexProvider`, stores durable sessions in `AgentRegistry`, and projects only minimal animation state back into `LocalPetEvent`. `LocalPetEvent.source` is not the canonical Codex session id.

| Codex hook | Agent status | Purpose |
| --- | --- | --- |
| `SessionStart` | `started` | Conversation/session opened or resumed. |
| `UserPromptSubmit` | `running` | User submitted a prompt and Codex started work. |
| `PreToolUse` | `running` | Codex is about to use a tool. |
| `PostToolUse` | `running` | Codex finished a tool call. |
| `PermissionRequest` | `waiting` | Codex is waiting for approval of a command or permission request. |
| `Stop` | `completed` | Codex finished the turn and the result is ready for review. |

The legacy Python hook remains in `examples/codex-hooks/hooks/codex-pet-event.py` for compatibility during migration, but it is no longer the managed installer path.

## Enable The Hooks

For daily use across multiple working directories, install the hook at the
Codex user level:

```bash
Tools/install-codex-hooks.sh
```

This writes `~/.codex/hooks.json` with an absolute bridge path, preserves
unrelated hook entries, updates this project's managed entries idempotently, and ensures
`~/.codex/config.toml` contains:

```toml
[features]
codex_hooks = true
```

Restart Codex sessions after installing. User-level hooks are the recommended
setup when you launch Codex from multiple working directories.

For repo-local testing only, copy the opt-in examples into a local `.codex/`
directory:

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

Restart Codex and trust this repository's `.codex/` config layer if prompted.
Repo-local hooks only apply when Codex loads that repo's `.codex/` config layer.

## Disable Or Remove

Temporarily disable the managed bridge without editing hooks:

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_CODEX_HOOKS=1
```

Remove managed entries from `~/.codex/hooks.json` by deleting hook commands that contain:

```text
global-pet-agent-bridge --source codex
```

The old Python hook switch `CODEX_PET_EVENTS_DISABLED=1` still applies only to the legacy `codex-pet-event.py` compatibility script.

## Verification

Build and install the bridge-backed hooks:

```bash
swift build --product global-pet-agent-bridge
Tools/install-codex-hooks.sh
```

Manually test the app-facing event path:

```bash
swift run GlobalPetAssistant
swift run global-pet-agent-bridge --source codex < Tests/GlobalPetAssistantTests/Fixtures/sample-codex-user-prompt.json
```

The bridge intentionally ignores local app socket connection failures so Codex work is never blocked by the pet app being closed or not yet initialized. Generic events should still be verified separately with `Tools/verify-event-runtime.sh`.

## Audit Logs

The Codex bridge and app runtime both write JSONL logs under `~/.global-pet-assistant/logs`:

```bash
tail -n 50 ~/.global-pet-assistant/logs/agent-hooks.jsonl
tail -n 50 ~/.global-pet-assistant/logs/events.jsonl
tail -n 50 ~/.global-pet-assistant/logs/runtime.jsonl
```

Use the hook log to confirm whether Codex produced a hook envelope. Use `runtime.jsonl` to confirm whether the app hook socket accepted or rejected the envelope. Use `events.jsonl` only for generic `LocalPetEvent` ingress through `LocalEventServer`.
