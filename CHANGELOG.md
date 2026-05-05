# Changelog

All notable changes will be tracked here.

This project follows a lightweight changelog format inspired by Keep a
Changelog, but it has not committed to semantic versioning before `1.0.0`.

## Unreleased

- No unreleased changes yet.

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
