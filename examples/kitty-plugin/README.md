# Global Pet Assistant Kitty Plugin

This is the preferred kitty integration path. It is separate from the legacy
`Tools/install-kitty-command-hook.sh` compatibility hook.

The plugin installs a small Python event emitter plus an opt-in kitty zsh
integration file. The zsh integration emits structured terminal plugin events
to the local app endpoint:

```text
POST http://127.0.0.1:17321/terminal-plugin/events
Authorization: Bearer <local app token>
```

It does not require tmux and it does not modify unrelated shell config.

## Install

From the repository root:

```bash
examples/kitty-plugin/install.sh
```

Then add this single line to the kitty zsh sessions where you want the plugin:

```zsh
source "$HOME/.config/kitty/global-pet-assistant/shell-integration.zsh"
```

Open a new kitty tab or source the line manually in an existing tab.

## Verify Flash

Make sure Global Pet Assistant is running, then run a successful long command:

```zsh
sleep 3
```

Run a failed command:

```zsh
false
```

Both commands should produce a short flash next to the pet. Low-noise commands
such as `cd`, `ls`, `pwd`, and `git status` are ignored.

## Codex Session Events

The integration defines a `gpa-codex` wrapper. Use it instead of `codex` when
you want the kitty plugin to emit Codex session start and end events:

```zsh
gpa-codex
```

The wrapper forwards all arguments to `codex`. The app can use the emitted
terminal context to expose `send-message` for known provider-approved sessions.

## Disable

For one shell session:

```zsh
export GPA_KITTY_PLUGIN=0
```

To remove the installed files:

```bash
rm -rf "$HOME/.config/kitty/global-pet-assistant"
```
