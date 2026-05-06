# Open Source Checklist

Use this checklist before making the repository public.

## Repository Hygiene

- [x] Source license exists.
- [x] Asset licensing policy exists.
- [x] Privacy policy exists.
- [x] Security reporting policy exists.
- [x] Contributing guide exists.
- [x] Code of Conduct exists.
- [x] Changelog exists.
- [x] Generated binaries, app bundles, logs, and iconset intermediates are ignored.
- [x] Repo-local Codex hooks are opt-in examples, not active by default.
- [x] Replace example GitHub URLs with the final public repository URL.
- [x] Review screenshots, logs, and docs for private machine paths before the first public release.

## Build And Test

- [x] `swift build`
- [x] `swift test`
- [x] `Tools/verify-codex-hook-events.sh`
- [x] `Tools/package-release-app.sh`
- [x] Launch packaged app and check `http://127.0.0.1:17321/healthz`

## Assets

- [x] App icon has a documented source and policy.
- [x] Generated `AppIcon.iconset` is ignored.
- [x] App icon generator uses local macOS tools and does not require the Swift toolchain.
- [x] Do not commit third-party pet assets unless their redistribution license is documented.
- [x] For Codex-compatible pet assets, document that users can import local copies with `petctl import-pet <name>`.

## Security Review

- [x] Local event server binds to `127.0.0.1`.
- [x] Local token authentication protects `POST /events`.
- [x] Local webhook bridge binds to `127.0.0.1` and requires the local token.
- [x] Event bodies are size-limited.
- [x] No arbitrary shell-command action is supported.
- [x] Action execution is source allowlisted.

## Release

- [x] Decide public bundle identifier ownership.
- [x] Decide whether release builds are ad-hoc signed, Developer ID signed, or notarized.
- [x] Package script emits a SHA-256 checksum for downloadable archives.
- [x] Add install, upgrade, and uninstall instructions for public users.

Initial release decision: keep `io.github.globalpetassistant.GlobalPetAssistant`
as the public bundle identifier, ship repository-built archives as ad-hoc signed
local beta artifacts, and require Developer ID signing plus notarization before
recommending downloadable public end-user releases.
