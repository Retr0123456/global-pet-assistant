# Global Pet Assistant

<p align="center">
  <img src="Assets/AppIcon/AppIcon.png" width="112" height="112" alt="Global Pet Assistant icon">
</p>

<p align="center">
  A local-first macOS desktop pet for coding-agent, terminal, and build status.
</p>

<p align="center">
  <a href="README.zh-CN.md">中文</a>
  · <a href="docs/README.md">Docs</a>
  · <a href="docs/integrations.md">Integrations</a>
  · <a href="https://github.com/Retr0123456/global-pet-assistant/releases/latest">Download</a>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <a href="https://github.com/Retr0123456/global-pet-assistant/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Retr0123456/global-pet-assistant?sort=semver"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-orange.svg">
</p>

Global Pet Assistant renders a transparent always-on-top pet and turns trusted
local events into animation, quick command flashes, and persistent agent-thread
reminders. It runs locally on `127.0.0.1` with a local bearer token; no hosted
account or cloud relay is required.

## What It Does

- Shows Codex session state such as running, waiting for approval, and completed turns.
- Shows Kitty command start/end flashes through the bundled watcher plugin.
- Accepts local script and build events through `petctl` or localhost HTTP.
- Opens only allowlisted apps, URLs, files, folders, or supported terminal targets.
- Imports Codex-compatible pet packages into the app-owned pet directory.

## Install

Download the latest DMG from
[GitHub Releases](https://github.com/Retr0123456/global-pet-assistant/releases/latest),
drag `GlobalPetAssistant.app` into `/Applications`, launch it once, then run:

```bash
open /Applications/GlobalPetAssistant.app
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/setup-integrations.sh
```

The DMG only copies the app. The setup guide shows every external config file it
may modify, creates backups, and lets you choose integrations.

The current beta is not notarized yet. If macOS blocks first launch, open the app
from Finder with Control-click -> Open, or allow it from System Settings.

## Docs

- [Integration Setup](docs/integrations.md): interactive setup, Kitty, Codex, and cleanup.
- [Documentation Hub](docs/README.md): architecture, assets, security, and maintainer notes.
- [Privacy](PRIVACY.md) and [Security Policy](SECURITY.md): local server, token, and log model.

## Develop

Requirements: macOS 26 SDK, Swift 6.2, and Xcode Command Line Tools.

```bash
swift build
swift test
Tools/package-debug-app.sh
open .build/GlobalPetAssistant.app
```

Runtime smoke check:

```bash
Tools/verify-event-runtime.sh
```

## Uninstall

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl uninstall kitty,codex
rm -rf /Applications/GlobalPetAssistant.app
rm -rf ~/.global-pet-assistant
```

For per-module cleanup, see [Integration Setup](docs/integrations.md).
