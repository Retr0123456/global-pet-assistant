# Global Pet Assistant Kitty Plugin

[中文](README.zh-CN.md) | [Integration Setup](../../docs/integrations.md)

The kitty plugin connects kitty shell activity to Global Pet Assistant. It
installs a kitty global watcher that observes command start/end events and sends
local terminal-plugin events to the app.

## Install

Install Global Pet Assistant first and launch it once:

```bash
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
```

Install the bundled plugin:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

Fully quit and reopen kitty after the first install.

## Verify

Run these commands in kitty:

```zsh
sleep 3
false
```

Expected result: the pet shows a short success flash for `sleep 3` and a short
failure flash for `false`.

## Installed Files

| Path | Purpose |
| --- | --- |
| `~/.config/kitty/global-pet-assistant/` | Watcher, plugin config, and local environment files. |
| `~/.config/kitty/kitty.conf` | Receives one marked include block. |

## Uninstall

```bash
rm -rf "$HOME/.config/kitty/global-pet-assistant"
```

Then remove the marked Global Pet Assistant include block from
`~/.config/kitty/kitty.conf`.

For choosing between Kitty and Codex hooks, see
[Integration Setup](../../docs/integrations.md).
