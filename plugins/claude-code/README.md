# Global Pet Assistant Claude Code Hooks

This directory is the supported Claude Code hook installation surface.

The installer writes a user-level Claude Code settings file that forwards hook
events to the local Global Pet Assistant app through:

```text
global-pet-agent-bridge --source claude-code
```

Claude Code hook commands receive hook JSON on stdin. The bridge wraps that JSON
with local terminal context and sends it to the app hook socket.

## Install From Release App

Launch Global Pet Assistant once, then run:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/claude-code/install.sh
```

Compatibility wrapper:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/install-claude-code-hooks.sh
```

The installer updates:

| Path | Purpose |
| --- | --- |
| `~/.claude/settings.json` | Adds managed Claude Code hook commands with an absolute bridge path. |

Restart Claude Code sessions after installing.

## Install From Source Checkout

From the repository root:

```bash
plugins/claude-code/install.sh
```

The installer builds `global-pet-agent-bridge` from source if no installed app
or explicit `GLOBAL_PET_AGENT_BRIDGE` path is available.

## Managed Events

The installer manages these Claude Code hook events:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PermissionRequest`
- `PermissionDenied`
- `PostToolUse`
- `PostToolUseFailure`
- `PostToolBatch`
- `Notification`
- `SubagentStart`
- `SubagentStop`
- `Stop`
- `StopFailure`
- `SessionEnd`

Unrelated hook entries in `~/.claude/settings.json` are preserved. Re-running
the installer replaces only prior Global Pet Assistant Claude Code hook entries.

## Disable

Temporarily disable Global Pet Assistant agent hooks for a shell session:

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_AGENT_HOOKS=1
```

To remove the install, delete hook commands in `~/.claude/settings.json` that
contain:

```text
global-pet-agent-bridge --source claude-code
```

## Templates

Static templates live under `plugins/claude-code/templates/` for reference and
repo-local experiments. The installer is preferred for daily use because it
preserves unrelated settings and writes an absolute bridge path.
