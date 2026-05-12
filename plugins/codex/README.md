# Global Pet Assistant Codex Hooks

This directory is the supported Codex hook installation surface.

The installer writes a user-level Codex hook configuration that forwards Codex
lifecycle events to the local Global Pet Assistant app through:

```text
global-pet-agent-bridge --source codex
```

## Install From Release App

Launch Global Pet Assistant once, then run:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/codex/install.sh
```

Compatibility wrapper:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/install-codex-hooks.sh
```

The installer updates:

| Path | Purpose |
| --- | --- |
| `~/.codex/config.toml` | Ensures `[features] codex_hooks = true`. |
| `~/.codex/hooks.json` | Adds managed Codex hook commands with an absolute bridge path. |

Restart Codex sessions after installing.

## Install From Source Checkout

From the repository root:

```bash
plugins/codex/install.sh
```

The installer builds `global-pet-agent-bridge` from source if no installed app
or explicit `GLOBAL_PET_AGENT_BRIDGE` path is available.

## Managed Events

The installer manages these Codex hook events:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PostToolUse`
- `PermissionRequest`
- `Stop`

Unrelated hook entries in `~/.codex/hooks.json` are preserved. Re-running the
installer replaces only prior Global Pet Assistant Codex hook entries.

## Disable

Temporarily disable all Global Pet Assistant agent hooks for a shell session:

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_AGENT_HOOKS=1
```

The old Codex-specific switch still works for compatibility:

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_CODEX_HOOKS=1
```

To remove the install, delete hook commands in `~/.codex/hooks.json` that
contain:

```text
global-pet-agent-bridge --source codex
```

## Templates

Static templates live under `plugins/codex/templates/` for reference and
repo-local experiments. The installer is preferred for daily use because it
preserves unrelated settings and writes an absolute bridge path.
