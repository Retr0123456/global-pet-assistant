# Contributing

Thanks for helping improve Global Pet Assistant.

## Development Requirements

- macOS 26 or newer SDK for the Liquid Glass AppKit APIs.
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

`Tools/verify-event-runtime.sh` launches the app itself, so stop any already
running copy first if the local event port is busy.

## Change Guidelines

- Keep the app local-first. Do not add public network listeners by default.
- Do not add shell-command actions without explicit allowlisting and a security review.
- Keep third-party integrations thin wrappers around the local event API.
- Add tests for event routing, rate limiting, action validation, and package parsing.
- Keep generated binaries, app bundles, logs, and local pet assets out of git.

## Pull Request Checklist

- `swift build` passes.
- `swift test` passes.
- New user-facing behavior is documented in `README.md` or `docs/`.
- New visual assets include a license note in `docs/assets-and-licensing.md`.
- Security-sensitive behavior is reflected in `SECURITY.md` or the architecture docs.
