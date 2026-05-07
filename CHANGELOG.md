# Changelog

All notable changes will be tracked here.

This project follows a lightweight changelog format inspired by Keep a
Changelog, but it has not committed to semantic versioning before `1.0.0`.

## Unreleased

- Added GUI pet switching from the menu bar and pet right-click menu, with the selected pet persisted across launches.

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
