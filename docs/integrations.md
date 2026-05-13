# Integration Setup

[中文](integrations.zh-CN.md) | [Documentation](README.md) | [Project README](../README.md)

Install Global Pet Assistant, launch it once, then run the bundled setup guide.
Dragging the DMG into `/Applications` does not modify terminal or coding-agent
configuration; the setup guide shows a plan before writing external files.

```bash
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
```

`healthz` should return JSON. If it fails, confirm that the app is running
before installing any integration.

## Guided Setup

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/setup-integrations.sh
```

The guide uses the bundled `petctl` binary. `petctl` is not automatically added
to `PATH` by the DMG install; optional global registration is available through
the `petctl-shim` module.

Useful non-interactive commands:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl install --dry-run
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl install --with kitty,codex --yes
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl doctor
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl uninstall kitty --dry-run
```

## Choose A Path

| Path | Best for | What it sends |
| --- | --- | --- |
| [Kitty Plugin](#kitty-plugin) | Terminal-heavy workflows in kitty. | Command start/end events, exit status, working directory, and terminal context. |
| [Codex Hooks](#codex-hooks) | Coding-agent sessions. | Running, waiting-for-approval, completed turns, and persistent thread reminders. |

## Kitty Plugin

The Kitty plugin installs a kitty global watcher. It observes shell command
start/end events and sends local `terminal-plugin` events to Global Pet
Assistant.

It does not need tmux and does not edit shell startup files by default.

### Install

Recommended:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl install --with kitty
```

Manual module script:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

Fully quit and reopen kitty after the first install. Opening a new tab is not
enough for every kitty configuration.

### Verify

Run in kitty:

```zsh
sleep 3
false
```

Expected result:

- `sleep 3` shows a short success flash.
- `false` shows a short failure flash.

### Files

| Path | Purpose |
| --- | --- |
| `~/.config/kitty/global-pet-assistant/` | Installed watcher, plugin config, shell integration, and local environment files. |
| `~/.config/kitty/kitty.conf` | Receives one managed include block. |

### Uninstall

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl uninstall kitty
```

This removes Global Pet Assistant managed files and marked config blocks only.

## Codex Hooks

Codex hooks send Codex lifecycle events to the local app through the bundled
`global-pet-agent-bridge`. They are useful when you want the pet to reflect
agent session state instead of only shell command results.

### Install

Recommended:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl install --with codex
```

Manual module script:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/codex/install.sh
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

### Disable

Disable temporarily for one shell:

```bash
export GLOBAL_PET_ASSISTANT_DISABLE_CODEX_HOOKS=1
```

To remove the hook permanently, run:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl uninstall codex
```

## Local Event API

Scripts can also send events directly through `petctl` or localhost HTTP.

```bash
petctl notify --source local-build --level success --title "Build passed"
petctl state running --source codex-cli --message "Editing files"
```

For raw HTTP writes, read the local token first:

```bash
PET_TOKEN="$(tr -d '\r\n' < ~/.global-pet-assistant/token)"
curl -X POST http://127.0.0.1:17321/events \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $PET_TOKEN" \
  -d '{"source":"ci","type":"build.failed","level":"danger","title":"CI failed"}'
```

Unknown sources may send state notifications, but click actions are only honored
for allowlisted sources.

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

If an integration stops working, confirm the app is running, then restart the
terminal or Codex session that should emit events.
