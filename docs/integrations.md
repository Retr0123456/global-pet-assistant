# Integration Setup

[中文](integrations.zh-CN.md) | [README](../README.md)

Install Global Pet Assistant first, launch it once, then choose one integration
to start with.

```bash
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
```

The `healthz` command should return JSON. If it fails, make sure the app is
running before installing integrations.

## Choose One

- Use the **Kitty plugin** if you want command start/end feedback and terminal
  context from kitty.
- Use **Codex hooks** if you want Codex lifecycle events such as running,
  waiting for approval, and completed turns.

You can install both later, but starting with one keeps the signal easier to
debug.

## Kitty Plugin

The kitty plugin installs a kitty global watcher. It observes shell command
start/end events and sends local terminal-plugin events to Global Pet Assistant.
It does not need tmux and does not edit shell startup files by default.

Install from the release app:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

Fully quit and reopen kitty after the first install. Opening a new tab is not
enough for every kitty setup.

Verify in kitty:

```zsh
sleep 3
false
```

Expected result:

- `sleep 3` shows a short success flash.
- `false` shows a short failure flash.

Useful files:

| Path | Purpose |
| --- | --- |
| `~/.config/kitty/global-pet-assistant/` | Installed watcher and plugin config. |
| `~/.config/kitty/kitty.conf` | Receives one managed include block. |

Uninstall:

```bash
rm -rf "$HOME/.config/kitty/global-pet-assistant"
```

Then remove the marked Global Pet Assistant include block from
`~/.config/kitty/kitty.conf`.

## Codex Hooks

Codex hooks send Codex lifecycle events to the local app through the bundled
`global-pet-agent-bridge`. They are useful when you want the pet to reflect
Codex session state instead of only shell command results.

Install from the release app:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/install-codex-hooks.sh
```

Restart Codex sessions after installing. The installer writes managed entries to
`~/.codex/hooks.json` and enables:

```toml
[features]
codex_hooks = true
```

Expected result:

- A Codex prompt submission marks the session as running.
- Approval-needed states appear as waiting.
- Completed turns appear in the thread panel until dismissed.

Disable temporarily for one shell:

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_CODEX_HOOKS=1
```

To remove the hook permanently, delete managed commands containing
`global-pet-agent-bridge --source codex` from `~/.codex/hooks.json`.

## Troubleshooting

Check app reachability:

```bash
curl -fsS http://127.0.0.1:17321/healthz
```

Check recent logs:

```bash
tail -n 50 ~/.global-pet-assistant/logs/runtime.jsonl
tail -n 50 ~/.global-pet-assistant/logs/events.jsonl
tail -n 50 ~/.global-pet-assistant/logs/agent-hooks.jsonl
```

If an integration stops working, first confirm that the app is running, then
restart the terminal or Codex session that should emit events.
