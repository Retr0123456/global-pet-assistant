# Contributing

Thanks for helping improve Global Pet Assistant. This project is still pre-1.0,
so the highest-value contributions are small, well-tested changes that preserve
the local-first security model.

## Development Requirements

- macOS 26 SDK or newer for the current AppKit surface.
- Swift 6.2 or newer.
- Xcode Command Line Tools installed.

## Local Workflow

```bash
swift build
swift test
Tools/package-debug-app.sh
open .build/GlobalPetAssistant.app
```

For runtime checks:

```bash
swift run GlobalPetAssistant
Tools/verify-event-runtime.sh
```

`Tools/verify-event-runtime.sh` launches the app itself. Stop any already
running copy first if local port `17321` is busy.

## Project Boundaries

Global Pet Assistant should stay:

- **Local-first**: no public listeners or hosted services by default.
- **Native**: AppKit owns the floating desktop surface.
- **Integration-friendly**: adapters should be thin wrappers around the generic
  local event API.
- **Conservative about actions**: opening apps, URLs, files, folders, or
  terminal/session targets must stay source-aware and allowlist-driven.

Do not add arbitrary shell-command execution from event payloads without an
explicit security design, user approval flow, and maintainer review.

## Change Guidelines

- Keep renderer behavior independent from event sources.
- Keep generated binaries, app bundles, logs, and local pet assets out of git.
- Add or update tests for event routing, rate limiting, action validation, hook
  parsing, terminal-plugin behavior, and pet package parsing when touched.
- Document user-facing behavior in `README.md`, `README.zh-CN.md`, or `docs/`.
- Record new visual assets in `docs/assets-and-licensing.md`.
- Reflect security-sensitive behavior in `SECURITY.md` or the architecture docs.

## Pull Request Checklist

- [ ] `swift build` passes.
- [ ] `swift test` passes.
- [ ] Focused verifier passes when the touched area has one.
- [ ] User-facing behavior is documented.
- [ ] New visual assets include a license note.
- [ ] Security-sensitive behavior is documented or called out for review.

Useful focused verifiers:

```bash
Tools/verify-codex-hook-events.sh
Tools/verify-kitty-plugin.sh
Tools/verify-event-runtime.sh
```
