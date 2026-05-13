# Changelog

All notable changes will be tracked here.

This project follows a lightweight changelog format inspired by Keep a
Changelog, but it has not committed to semantic versioning before `1.0.0`.

## Unreleased

## 0.4.6 - 2026-05-13

- Fixed compact thread status bar clipping when the selected pet is narrower than the status bar.

## 0.4.5 - 2026-05-13

- Fixed the compact thread status bar so the expand chevron no longer shifts the status counts when the thread panel is opened.

## 0.4.4 - 2026-05-13

- Moved the compact thread status bar out of the pet sprite area so it follows the pet's screen quadrant without covering the pet.
- Kept the pet resize close button visible when the pet is scaled down.
- Increased thread panel and status bar contrast on bright desktop backgrounds.

## 0.4.3 - 2026-05-13

- Added aggregate thread-state selection so visible failed rows beat success rows, success rows beat running or waiting rows, and idle only plays when no tracked rows remain.
- Changed success feedback to use the `waving` animation for long-lived rows, flash events, terminal command success, and projected agent completion.
- Replaced the single thread-count badge with a compact red/yellow/green status bar showing failed, running-or-waiting, and successful row counts.
- Simplified the README and integration docs, with English and Chinese versions for the main install path, Kitty plugin setup, and Codex hook setup.
- Added DMG generation to the release packaging script.

## 0.4.2 - 2026-05-10

- Fixed expanded thread panel placement near screen corners so the panel follows the pet's screen quadrant without pulling the pet away from the dragged position.
- Improved reply control contrast in the thread panel so the input affordance remains visible in light appearance.

## 0.4.1 - 2026-05-09

- Moved the structured kitty integration into `plugins/kitty` as a first-class plugin.
- Added kitty plugin installation for local remote control, clean-install preflight warnings, and release-bundled plugin/helper assets.
- Hardened kitty terminal plugin event handling so command flash quota does not starve Codex observations, noisy shell commands are ignored more consistently, and reply controls require a valid local kitty target.

## 0.4.0 - 2026-05-08

- Added GUI pet switching from the menu bar and pet right-click menu, with the selected pet persisted across launches.
- Added Codex session listening through the new `global-pet-agent-bridge`, Unix hook socket ingestion, `AgentRegistry`, Codex provider normalization, and long-lived agent thread panel rows.
- Added bridge-backed Codex hook installation for `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, and `Stop` while preserving unrelated user hooks.
- Kept generic `LocalPetEvent` routing separate from coding-agent session identity, with Codex sessions projected back to pet animation state only through a one-way event projection.

## 0.3.4 - 2026-05-07

- Replaced the bundled fallback pet with Blobbit, an original generated Codex-compatible default pet.
- Removed the obsolete generated fallback atlas source and renamed bundled pet loading around the default pet.

## 0.3.3 - 2026-05-07

- Canonicalized Codex subagent hook events through transcript session metadata so spawned agents update their parent thread panel row instead of creating separate rows.
- Polished the thread panel glass surface and row layout.
- Installed the bundled fallback pet into the app-owned pet directory on first launch so fresh installs no longer depend on Codex pet state.
- Changed external pet loading to an explicit `petctl import-pet` flow backed by configurable `petImportSourceDirectories`.
- Removed source hardcoding from the kitty command hook example and aligned release resource bundle layout with SwiftPM's runtime lookup path.

## 0.3.2 - 2026-05-05

- Reduced pet animation memory usage by rendering from one atlas image with Core Animation frame rects instead of keeping cropped frame images resident.

## 0.3.1 - 2026-05-05

- Added quick status icons to long-running thread panel rows for running, waiting, success, failure, and approval-required states.
- Tightened the thread panel row layout around the status icon, title, message, and dismiss button.

## 0.2.0 - 2026-05-05

- Added short-lived `flash` events that stay separate from long-running task threads.
- Added `petctl flash` and `petctl run -- <command>` for explicit terminal feedback.
- Added a lightweight flash bubble stack near the pet that does not affect the thread badge.
- Added transient pet reactions for flash events without changing the base task state.
- Added kitty interactive zsh command flash integration and installer.

## 0.1.1 - 2026-05-04

- Added native macOS Liquid Glass notification surfaces.
- Added Codex lifecycle hook example with stable multi-session source keys.
- Added kitty remote-control focus actions for Codex sessions running in kitty.
- Added source action allowlisting and local audit logs.
- Added an original generated app icon and icon packaging support.
- Added open-source readiness documents and asset licensing policy.
