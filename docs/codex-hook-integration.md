# Codex Hook Integration

[中文](codex-hook-integration.zh-CN.md) | [Integration Setup](integrations.md)

Codex hooks send Codex lifecycle events to Global Pet Assistant through the
bundled `global-pet-agent-bridge`. Use this integration if you want the pet to
show Codex session state such as running, waiting for approval, and completed
turns.

## Install

Install Global Pet Assistant first and launch it once:

```bash
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
```

Install the bundled hooks:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/install-codex-hooks.sh
```

Restart Codex sessions after installing.

## What Gets Installed

The installer writes managed entries to `~/.codex/hooks.json` and enables Codex
hooks in `~/.codex/config.toml`:

```toml
[features]
codex_hooks = true
```

Managed hook commands contain:

```text
global-pet-agent-bridge --source codex
```

## Expected Behavior

- `UserPromptSubmit` marks the Codex session as running.
- `PermissionRequest` marks the session as waiting.
- `Stop` marks the turn as completed and shows it in the thread panel until
  dismissed.

## Disable

Temporarily disable hooks for one shell:

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_CODEX_HOOKS=1
```

To remove the integration, delete managed commands containing
`global-pet-agent-bridge --source codex` from `~/.codex/hooks.json`.

## Logs

```bash
tail -n 50 ~/.global-pet-assistant/logs/agent-hooks.jsonl
tail -n 50 ~/.global-pet-assistant/logs/runtime.jsonl
tail -n 50 ~/.global-pet-assistant/logs/events.jsonl
```

For choosing between Kitty and Codex hooks, see
[Integration Setup](integrations.md).
