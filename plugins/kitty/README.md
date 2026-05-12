# Global Pet Assistant Kitty Plugin

## Release Download

Download the current release before installing the plugin from an app bundle:

- Latest release page: <https://github.com/Retr0123456/global-pet-assistant/releases/latest>
- Current release page: <https://github.com/Retr0123456/global-pet-assistant/releases/tag/v0.4.2>
- Current DMG asset: <https://github.com/Retr0123456/global-pet-assistant/releases/download/v0.4.2/GlobalPetAssistant.dmg>
- Current checksum asset: <https://github.com/Retr0123456/global-pet-assistant/releases/download/v0.4.2/GlobalPetAssistant.dmg.sha256>

Install the app first, then run the plugin installer from the installed app
bundle. The release app includes the kitty plugin under:

```text
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/
```

If you downloaded the current DMG and checksum into the same directory, you can
verify the DMG before opening it:

```bash
shasum -a 256 -c GlobalPetAssistant.dmg.sha256
```

This is the preferred kitty integration path. It is separate from the legacy
`Tools/install-kitty-command-hook.sh` compatibility hook.

## What The Plugin Installs

The installer installs a kitty global watcher and a small optional Python
emitter. The watcher emits structured terminal plugin events to the local app
endpoint:

```text
POST http://127.0.0.1:17321/terminal-plugin/events
Authorization: Bearer <local app token>
```

It does not require tmux or shell startup-file edits. The installer adds an
include to `~/.config/kitty/kitty.conf` so kitty loads the watcher and exposes a
local Unix remote-control socket that the app can use for reply/send-message on
provider-approved sessions.

The managed kitty include enables:

- `watcher ~/.config/kitty/global-pet-assistant/global_pet_assistant_watcher.py`
- `allow_remote_control socket-only`
- `listen_on unix:~/.config/kitty/global-pet-assistant/kitty.sock`

## Install From Release App

After installing the DMG into `/Applications`, launch Global Pet Assistant once.
This creates `~/.global-pet-assistant/token`, which the plugin uses for local
authentication.

Manually verify that the app is reachable:

```bash
curl -fsS http://127.0.0.1:17321/healthz
```

Run the bundled kitty plugin installer:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

Fully quit and reopen kitty after the first install. Opening a new tab is not
enough for the first watcher/config load in every kitty setup.

## Install From Source Checkout

From the repository root, launch the app at least once, verify `healthz`, then
run:

```bash
plugins/kitty/install.sh
```

Use this source-checkout command only when you are developing or testing the
repository directly. New users should prefer the release app installer path.

## Manual Commands Checklist

For a normal release-app install, the user manually runs these commands:

```bash
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

After fully restarting kitty, the user manually verifies command flash:

```zsh
sleep 3
false
```

Codex lifecycle hooks are optional and require one extra manual command:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/install-codex-hooks.sh
```

## Installer Options

To install without editing kitty config:

```bash
GPA_KITTY_PLUGIN_CONFIGURE_KITTY=0 /Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

The old zsh integration is still available as an explicit compatibility path:

```bash
GPA_KITTY_PLUGIN_INSTALL_ZSHRC=1 /Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

The default watcher path should be used for new installs. The zsh path exists
only for older local setups that still need compatibility with the pre-plugin
command flash hook.

## Verify Flash

Make sure Global Pet Assistant is running, fully restart kitty, then manually
run a successful long command:

```zsh
sleep 3
```

Run a failed command:

```zsh
false
```

Both commands should produce a short flash next to the pet. Low-noise commands
such as `cd`, `ls`, `pwd`, and `git status` are ignored by the app projection.

## Codex Session Events

The watcher automatically emits Codex session start and end observations when a
kitty shell runs `codex` or `cdx`.

The legacy zsh compatibility path also defines a `gpa-codex` wrapper:

```zsh
gpa-codex
```

The wrapper forwards all arguments to `codex`. The app can use watcher-emitted
terminal context to expose `send-message` for known provider-approved sessions
when the kitty remote-control socket is configured.

For richer Codex lifecycle events such as tool use and approval-needed state,
also install the Codex hooks.

```bash
Tools/install-codex-hooks.sh
# or, from an installed release app:
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/install-codex-hooks.sh
```

## Installed Files

The installer writes these files:

| Path | Purpose |
| --- | --- |
| `~/.config/kitty/global-pet-assistant/global_pet_assistant_watcher.py` | Kitty watcher loaded by `kitty.conf`. |
| `~/.config/kitty/global-pet-assistant/global_pet_assistant.py` | Optional legacy emitter used by the compatibility zsh path. |
| `~/.config/kitty/global-pet-assistant/env.json` | Watcher endpoint and kitty control endpoint configuration. |
| `~/.config/kitty/global-pet-assistant/env.zsh` | Legacy zsh compatibility environment. |
| `~/.config/kitty/global-pet-assistant/kitty.conf` | Managed kitty include generated by the installer. |
| `~/.config/kitty/kitty.conf` | Gets one marked include block pointing to the managed include. |

## Disable

For one shell session:

```zsh
export GPA_KITTY_PLUGIN=0
```

## Uninstall

To remove the installed plugin files:

```bash
rm -rf "$HOME/.config/kitty/global-pet-assistant"
```

Also remove the marked `global-pet-assistant kitty remote control` block from
`~/.config/kitty/kitty.conf`. If you opted into the legacy zsh compatibility
path, remove the marked `global-pet-assistant kitty plugin` block from
`~/.zshrc`.
