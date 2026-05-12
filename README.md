# Global Pet Assistant

[中文](README.zh-CN.md)

Global Pet Assistant is a lightweight macOS desktop pet for local development
notifications. It runs as a small floating AppKit pet, listens only on the local
machine, and turns tool events into pet animations, short status flashes, and
actionable thread reminders.

## What It Does

- Shows a transparent always-on-top desktop pet on macOS.
- Plays Codex-compatible pet spritesheet animations for idle, running, waiting,
  success, failure, review, waving, jumping, and directional running states.
- Displays short flash messages for command results, build status, and quick
  local notifications.
- Displays longer-lived thread reminders for coding-agent sessions until the
  user dismisses them.
- Opens trusted actions from notifications, such as apps, URLs, files, folders,
  or supported terminal/session targets.
- Provides a focus timer from the menu bar and pet right-click menu.
- Supports switching compatible pet packages from the menu.
- Supports pet resizing from the pet right-click menu under `Resize Pet`.
- Keeps app state, logs, imported pets, and local tokens under
  `~/.global-pet-assistant`.

## Install

Download the latest DMG from the
[GitHub Releases page](https://github.com/Retr0123456/global-pet-assistant/releases/latest),
open it, and drag `GlobalPetAssistant.app` into `/Applications`.

Launch the app:

```bash
open /Applications/GlobalPetAssistant.app
```

The current beta is not notarized yet. If macOS blocks the first launch, open it
from Finder with Control-click -> Open, or allow it from System Settings.

## Recommended Integration

Pick one starting integration:

- **Kitty plugin**: best if you use kitty and want command flash feedback plus
  terminal context. It observes command start/end events without editing shell
  startup files.
- **Codex hooks**: best if you want Codex lifecycle events such as running,
  waiting for approval, and completed turns.

See the concise setup guide:
[Integration Setup](docs/integrations.md).

## Privacy And Locality

Global Pet Assistant is local-first. The app listens on localhost, creates a
local bearer token on first launch, and reads that token from local helper tools.
It does not require a cloud account.

## Uninstall

Quit the app, remove the application bundle, and optionally remove app-owned
state:

```bash
rm -rf /Applications/GlobalPetAssistant.app
rm -rf ~/.global-pet-assistant
```
