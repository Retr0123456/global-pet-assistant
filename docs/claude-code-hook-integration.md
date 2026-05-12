# Claude Code Hook Integration

Global Pet Assistant can receive Claude Code lifecycle events through Claude
Code hooks and `global-pet-agent-bridge`.

## Official Claude Code Surface

Official reference: <https://code.claude.com/docs/en/hooks>

Claude Code hook settings are JSON and can live in user settings such as
`~/.claude/settings.json` or project settings such as `.claude/settings.json`.
Global Pet Assistant uses the user-level settings path for daily use.

Hook commands receive JSON on stdin. The managed command is:

```text
global-pet-agent-bridge --source claude-code
```

## Enable The Hooks

For daily use across multiple working directories, install the hook at the
Claude Code user level:

```bash
plugins/claude-code/install.sh
```

If you installed from the release app:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/claude-code/install.sh
```

Compatibility wrapper:

```bash
Tools/install-claude-code-hooks.sh
```

The installer writes `~/.claude/settings.json` with an absolute bridge path,
preserves unrelated hook entries, and updates this project's managed entries
idempotently. Restart Claude Code sessions after installing.

## Event Flow

The bridge captures hook stdin plus terminal environment such as `TTY`,
`TERM_PROGRAM`, `TMUX_PANE`, and `KITTY_WINDOW_ID`, then writes one
newline-delimited `AgentHookEnvelope` to:

```text
~/.global-pet-assistant/run/agent-hooks.sock
```

The app receives the envelope through `AgentHookSocketServer`, sends
`claude-code` envelopes to `ClaudeCodeProvider`, stores sessions in
`AgentRegistry`, and projects minimal animation state back into generic pet
events.

| Claude Code hook | Agent status | Purpose |
| --- | --- | --- |
| `SessionStart` | `started` | Conversation/session opened. |
| `UserPromptSubmit` | `running` | User submitted a prompt and Claude Code started work. |
| `PreToolUse` | `running` | Claude Code is about to use a tool. |
| `PermissionRequest` | `waiting` | Claude Code is waiting for tool approval. |
| `PermissionDenied` | `failed` | A tool permission was denied. |
| `PostToolUse` | `running` | Claude Code finished a tool call. |
| `PostToolUseFailure` | `failed` | Claude Code tool execution failed. |
| `PostToolBatch` | `running` | A batch of tool calls resolved. |
| `Notification` | `running` | Claude Code emitted a notification hook. |
| `SubagentStart` | `running` | A Claude Code subagent started. |
| `SubagentStop` | `completed` | A Claude Code subagent finished. |
| `Stop` | `completed` | Claude Code finished the turn. |
| `StopFailure` | `failed` | Claude Code failed to stop cleanly. |
| `SessionEnd` | `completed` | Claude Code session terminated. |

## Disable Or Remove

Temporarily disable the managed bridge without editing settings:

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_AGENT_HOOKS=1
```

Remove managed entries from `~/.claude/settings.json` by deleting hook commands
that contain:

```text
global-pet-agent-bridge --source claude-code
```

## Verification

Verify installer behavior without touching your real user settings:

```bash
Tools/verify-agent-hook-installers.sh
```

Manually test the app-facing event path:

```bash
swift run GlobalPetAssistant
printf '{"hook_event_name":"UserPromptSubmit","session_id":"claude-test","prompt":"Test Claude Code hooks"}' \
  | swift run global-pet-agent-bridge --source claude-code
```
