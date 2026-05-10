# Global Pet Assistant Kitty Plugin

This is the preferred kitty integration path. It is separate from the legacy
`Tools/install-kitty-command-hook.sh` compatibility hook.

The plugin installs a kitty global watcher and a tiny optional Python emitter.
The watcher emits structured terminal plugin events to the local app endpoint:

```text
POST http://127.0.0.1:17321/terminal-plugin/events
Authorization: Bearer <local app token>
```

It does not require tmux or shell startup-file edits. The installer adds an
include to `~/.config/kitty/kitty.conf` so kitty loads the watcher and exposes a
local Unix remote-control socket that the app can use for reply/send-message on
provider-approved sessions.

## Install

From the repository root:

```bash
plugins/kitty/install.sh
```

From an installed release app:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

The installer copies the plugin files and writes a kitty include file
automatically. Fully quit and reopen kitty after the first install so kitty
loads the watcher and the remote-control include needed for replies.

If Global Pet Assistant has never been launched, start it once before verifying.
That creates `~/.global-pet-assistant/token`, which the plugin uses for local
authentication.

To install without editing kitty config:

```bash
GPA_KITTY_PLUGIN_CONFIGURE_KITTY=0 plugins/kitty/install.sh
```

The old zsh integration is still available as an explicit compatibility path:

```bash
GPA_KITTY_PLUGIN_INSTALL_ZSHRC=1 plugins/kitty/install.sh
```

## Verify Flash

Make sure Global Pet Assistant is running, fully restart kitty, then run a
successful long command:

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

## Disable

For one shell session:

```zsh
export GPA_KITTY_PLUGIN=0
```

To remove the installed files:

```bash
rm -rf "$HOME/.config/kitty/global-pet-assistant"
```

Also remove the marked `global-pet-assistant kitty remote control` block from
`~/.config/kitty/kitty.conf`. If you opted into the legacy zsh compatibility
path, remove the marked `global-pet-assistant kitty plugin` block from
`~/.zshrc`.
