# Interactive Integration Installer Plan

## Purpose

This plan defines how Global Pet Assistant should install external tool
integrations after a DMG drag-install.

The DMG flow installs `GlobalPetAssistant.app` into `/Applications`, but it does
not register `petctl` on the user's `PATH` and it should not modify user
configuration files during drag-copy. External configuration changes must happen
only after the user explicitly starts an installer and confirms the exact files
that will be changed.

## Product Boundary

The installer should:

- Help users choose which integrations to enable.
- Detect dependencies and existing configuration paths.
- Explain every external file or directory it may modify.
- Create backups before changing user-owned configuration.
- Use managed blocks for edits inside existing config files.
- Support verification, reinstall, dry-run, and uninstall flows.

The installer should not:

- Modify shell, terminal, Codex, or Claude Code configuration during DMG copy.
- Require users to know hidden App bundle paths.
- Assume `petctl` is already globally registered.
- Write outside app-owned or integration-owned paths without confirmation.
- Touch unrelated user configuration outside marked managed blocks.

## Current Constraint

Current release packaging places tools inside the App bundle:

```text
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/global-pet-agent-bridge
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/install-codex-hooks.sh
/Applications/GlobalPetAssistant.app/Contents/Resources/plugins/kitty/install.sh
```

That is useful for distribution, but inconvenient for first-time users because:

- `petctl` is not available as `petctl` unless the user adds it to `PATH`.
- Running nested App bundle scripts is awkward and hard to discover.
- The current docs expose separate integration scripts instead of one guided
  setup entrypoint.

## Target User Flow

After installing the DMG, the user should be able to run one visible bootstrap
script from the App bundle:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/setup-integrations.sh
```

The script should launch an interactive installer:

```text
Global Pet Assistant Setup

App:
  /Applications/GlobalPetAssistant.app
  healthz: reachable

Detected:
  Kitty: found
  Codex: found
  Claude Code: not found

Recommended:
  [x] Kitty Command Flashes
  [x] Codex Session Reminders

Advanced:
  [ ] Legacy Kitty zsh integration

The selected modules may modify:
  ~/.config/kitty/kitty.conf
  ~/.config/kitty/global-pet-assistant/
  ~/.codex/hooks.json
  ~/.codex/config.toml

Backups will be created before changes.
Only Global Pet Assistant managed blocks will be updated.

Continue? [y/N]
```

## Entry Points

### Primary Bundle Script

Add a bundled setup script:

```text
Tools/setup-integrations.sh
```

Package it into:

```text
GlobalPetAssistant.app/Contents/Resources/Tools/setup-integrations.sh
```

Responsibilities:

- Resolve the App bundle root from its own path.
- Locate bundled `petctl` under `Contents/Resources/bin/petctl`.
- Prefer running the Swift CLI installer through the bundled `petctl`.
- Fall back to module shell scripts only when the CLI installer is unavailable.
- Print the exact bundled `petctl` path for advanced/manual users.

This script is the stable command shown in README and onboarding docs.

### Optional PATH Registration

The interactive installer may offer to create a user-level shim:

```text
~/.local/bin/petctl -> /Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl
```

This must be optional because modifying shell startup or PATH is an external
configuration change. The installer should first check whether `~/.local/bin` is
already on `PATH`. If not, it should explain the options:

- create the shim only and tell the user how to call it directly;
- add a managed PATH block to the user's shell profile;
- skip global registration.

Default: skip shell startup changes.

### App Onboarding

The App can later expose a menu item:

```text
Set Up Integrations...
```

The first implementation can open Terminal with the bundled setup script command
or show copyable instructions. A native settings UI can come later after the CLI
module model is stable.

## Module Model

Each integration should have a manifest describing its behavior. Start with JSON
or TOML so both shell and Swift code can read it.

Example:

```json
{
  "id": "kitty",
  "title": "Kitty Command Flashes",
  "category": "terminal",
  "recommended": true,
  "requires": {
    "commands": ["kitty"],
    "paths": []
  },
  "modifies": [
    "~/.config/kitty/kitty.conf",
    "~/.config/kitty/global-pet-assistant/"
  ],
  "install": {
    "script": "plugins/kitty/install.sh"
  },
  "verify": {
    "script": "Tools/verify-kitty-plugin.sh"
  },
  "uninstall": {
    "removePaths": ["~/.config/kitty/global-pet-assistant/"],
    "managedBlocks": [
      {
        "path": "~/.config/kitty/kitty.conf",
        "begin": "# >>> global-pet-assistant kitty remote control >>>",
        "end": "# <<< global-pet-assistant kitty remote control <<<"
      }
    ]
  }
}
```

Initial modules:

- `kitty`: command flashes through the Kitty watcher.
- `codex`: Codex session lifecycle hooks.
- `claude-code`: Claude Code hooks when the standardized installer exists in
  this checkout.
- `petctl-shim`: optional user-level command registration.
- `kitty-legacy-zsh`: advanced compatibility mode only.

## Configuration Ownership

### App-Owned State

Global Pet Assistant owns:

```text
~/.global-pet-assistant/
```

This includes app runtime config, logs, token, run sockets, UI preferences, and
installed pet packages. The App can create and migrate these files at startup.

### External Managed State

External integrations are user-owned configuration. They require explicit
confirmation before write.

Examples:

```text
~/.config/kitty/kitty.conf
~/.config/kitty/global-pet-assistant/
~/.codex/hooks.json
~/.codex/config.toml
~/.claude/settings.json
~/.zshrc
```

Rules:

- Create timestamped backups before modifying an existing file.
- Edit only marked Global Pet Assistant blocks inside shared config files.
- Preserve unrelated user entries.
- Reinstall idempotently.
- Provide an uninstall action for every install action.

## Installer Commands

Extend bundled `petctl` with:

```bash
petctl install
petctl install --dry-run
petctl install --with kitty,codex
petctl install --yes
petctl doctor
petctl uninstall kitty
petctl uninstall codex
```

`setup-integrations.sh` should call:

```bash
"$BUNDLED_PETCTL" install
```

Non-interactive CI or advanced users can call:

```bash
/Applications/GlobalPetAssistant.app/Contents/Resources/bin/petctl install --with kitty,codex --yes
```

## Dependency Detection

Each module should implement a `detect` phase before install:

- Commands: `command -v kitty`, `command -v codex`.
- App bundles: search `/Applications`, `~/Applications`, and Launch Services
  metadata where useful.
- Config paths: detect existing config files but do not require them.
- App runtime: check `http://127.0.0.1:17321/healthz`.

If a dependency is not found:

- mark the module as unavailable or degraded;
- explain the missing dependency;
- optionally ask for a manual path;
- never guess a hard-coded custom path.

## Safety Flow

Every install should run through the same phases:

1. Discover App bundle paths and local app reachability.
2. Load module manifests.
3. Detect dependencies.
4. Build a plan.
5. Print the exact files and directories that may change.
6. Ask for confirmation unless `--yes` is provided.
7. Backup existing external config files.
8. Apply managed-block or module-specific changes.
9. Run verification.
10. Print restart steps and uninstall commands.

`--dry-run` stops after step 5.

## Backup Policy

Before modifying an existing external config file, create:

```text
<path>.global-pet-assistant-backup-YYYYMMDD-HHMMSS
```

Directory installs should prefer app-owned integration directories such as:

```text
~/.config/kitty/global-pet-assistant/
```

Shared files should only receive a small include block pointing at that
integration-owned directory.

## Verification

Verification should be module-specific and composable.

Initial checks:

- App: `curl -fsS http://127.0.0.1:17321/healthz`.
- Kitty: existing `Tools/verify-kitty-plugin.sh` plus user-facing `sleep 3` and
  `false` instructions.
- Codex: validate JSON/TOML, verify managed hook entries, and tell the user to
  restart Codex sessions.
- `petctl-shim`: check `command -v petctl` in a fresh login shell only if PATH
  registration was selected.

## Packaging Changes

Update both release and debug packaging scripts to include:

```text
Tools/setup-integrations.sh
plugins/*/manifest.json
```

The package should continue to include the raw module installers so advanced
users and tests can call them directly.

## Documentation Changes

README quick start should become:

```bash
open /Applications/GlobalPetAssistant.app
/Applications/GlobalPetAssistant.app/Contents/Resources/Tools/setup-integrations.sh
```

Integration docs should still keep direct module commands under an advanced or
manual section.

The docs should explicitly say:

- Dragging the DMG does not modify terminal or agent configuration.
- The setup script will show all external files before modifying them.
- `petctl` is bundled inside the App; global registration is optional.

## Implementation Phases

### Phase 1: Bundled Setup Script

- Add `Tools/setup-integrations.sh`.
- Resolve bundled `petctl` and App bundle paths.
- Print current direct install commands as a guided menu.
- Package the script in debug and release App bundles.
- Update README to point at the setup script.

### Phase 2: Module Manifests

- Add manifests for Kitty and Codex.
- Teach setup script to read manifests or maintain a simple hard-coded module
  table until Swift support lands.
- Add dry-run output that lists modifications.
- Add backup creation around shared config edits.

### Phase 3: `petctl install`

- Move installer planning into Swift.
- Add `install`, `doctor`, and `uninstall` subcommands.
- Keep existing shell installers as low-level module executors.
- Add tests for planning, managed block replacement, backup naming, and
  idempotent reinstall.

### Phase 4: App Onboarding

- Add a menu item or first-run panel that opens the setup command.
- Later, replace terminal launch with native UI that uses the same module
  manifests and installer engine.

## Acceptance Criteria

- A DMG-installed user can run one documented setup command without knowing the
  nested `petctl` path.
- The installer never modifies external config before showing a plan.
- Kitty and Codex installs are selectable independently.
- Re-running install does not duplicate managed blocks.
- Uninstall removes only Global Pet Assistant managed state.
- Direct module scripts remain available for debugging and compatibility.
- Release and debug App bundles contain the same setup entrypoint.
