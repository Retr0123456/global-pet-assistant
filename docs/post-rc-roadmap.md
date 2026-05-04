# Post-RC Roadmap

This roadmap starts after the release-candidate runtime is verified. The goal is to move from a working local app to a safer, observable, installable assistant that can survive daily use and support more integrations.

## Priority 0: Ship A Local Beta Build

What to do:

- Treat the current release artifact as the first local beta.
- Install it in a stable local location.
- Keep `petctl` available from the repo while the app bundle is still ad-hoc signed.

Concrete target:

```text
/Applications/GlobalPetAssistant.app
```

How to do it:

```bash
Tools/package-release-app.sh
ditto .build/release/GlobalPetAssistant.app /Applications/GlobalPetAssistant.app
open /Applications/GlobalPetAssistant.app
curl -fsS http://127.0.0.1:17321/healthz
swift run petctl notify --source codex-cli --level success --title "Installed beta is reachable"
```

Acceptance:

- The app launches from `/Applications`.
- `petctl` can reach the installed app.
- Launch-at-login can be enabled from the menu and survives relaunch.

## Priority 1: Add Local Write Authentication

Status: implemented for `POST /events`. The app generates
`~/.global-pet-assistant/token`, `petctl` reads it automatically, and unauthenticated
event writes return `401`.

What to do:

- Keep the local token requirement covered by tests and runtime verification.
- Keep `GET /healthz` unauthenticated as a non-sensitive public health mode.

Why:

- The app can now open URLs, files, folders, and apps. `127.0.0.1` is a good boundary, but write auth should exist before adding more integrations.

Concrete behavior:

- Generate token at:

```text
~/.global-pet-assistant/token
```

- File permissions:

```text
0600
```

- Require this header for `POST /events`:

```text
Authorization: Bearer <token>
```

- `petctl` reads the token automatically.
- Bad or missing token returns:

```json
{"ok":false,"error":"unauthorized"}
```

Acceptance:

- `curl POST /events` without token returns `401`.
- `petctl notify ...` still works without the user passing token flags.
- Existing hook examples still work through `petctl`.

## Priority 2: Add Event History And Diagnostics

Status: partially implemented. The app now writes `events.jsonl` and `runtime.jsonl`, and the Codex hook writes `codex-hook-events.jsonl`. Remaining work is a richer diagnostics command and in-app log viewer.

What to do:

- Persist a small local event log.
- Add a diagnostics command and a menu item to open logs.

Concrete files:

```text
~/.global-pet-assistant/logs/events.jsonl
~/.global-pet-assistant/logs/runtime.log
```

Event log fields:

```json
{
  "timestamp": "2026-05-04T18:30:00Z",
  "source": "codex-cli",
  "type": "task.completed",
  "level": "success",
  "state": "review",
  "accepted": true,
  "rejection": null,
  "hasAction": true
}
```

Commands to add:

```bash
petctl doctor
petctl history --limit 20
petctl open-logs
```

Acceptance:

- `petctl doctor` reports app reachability, health state, config path, token path, pet package, and app version.
- Rejected events are logged with a reason.
- Logs are capped or rotated so they do not grow forever.

## Priority 3: Add A Notification Center Panel

What to do:

- Add a compact AppKit panel showing recent events.
- This should be a work-focused utility panel, not a landing page or decorative dashboard.

Concrete UI:

- Menu bar item: `Open Events`
- Right-click pet item: `Open Events`
- Panel rows:
  - timestamp
  - source
  - title/message
  - state
  - action button if available
  - mute source button

Acceptance:

- The panel shows the last 20 events.
- Clicking an action in the panel uses the same `ActionHandler` allowlist.
- Muting a source from the panel updates `event-preferences.json`.

## Priority 4: Add Hook Installation Helpers

What to do:

- Keep the current examples, but add install helpers for a local checkout.
- Start with repo-local/local-shell hooks rather than depending on unstable private CLI internals.

Commands to add:

```bash
petctl install-hook local-build --repo $HOME/codespace/global-pet-assistant
petctl install-hook codex --repo $HOME/codespace/global-pet-assistant
petctl install-hook claude --repo $HOME/codespace/global-pet-assistant
```

Concrete first install output:

- Copy or symlink scripts from:

```text
examples/hooks/
```

- Into:

```text
~/.global-pet-assistant/hooks/
```

- Generate a small `README.md` explaining exactly how to call them.

Acceptance:

- A user can run one command and get a ready-to-call hook path.
- The generated README contains exact commands for this repo.
- No global shell config is modified automatically.

## Priority 5: Add The Local Webhook Bridge

Status: implemented as `pet-webhook-bridge`. The bridge is off unless started,
binds only to `127.0.0.1`, requires the local bearer token on incoming webhook
requests, and forwards normalized events to `POST /events` with that token.

What to do:

- Keep the bridge behind explicit local startup and bearer-token authentication.
- Keep it explicitly local-only.

Concrete bridge:

```text
pet-webhook-bridge
127.0.0.1:17322
```

Supported first payload:

- GitHub Actions-like failure event from a local script.

Mapping:

- workflow failure -> source `ci`, level `danger`, action URL `https://github.com/Retr0123456/global-pet-assistant/actions`
- workflow success -> source `ci`, level `success`, action URL `https://github.com/Retr0123456/global-pet-assistant/actions`

Acceptance:

- Bridge is off unless explicitly started.
- Bridge forwards to `POST /events` with the local token.
- Bridge never exposes a public network listener.

## Priority 6: Product Packaging

What to do:

- Move beyond ad-hoc local packaging.

Options:

- Keep local-only: `.zip` release artifact plus checksum.
- Public/private distribution: Developer ID signing and notarization.
- Developer install convenience: Homebrew tap or `install.sh`.

Status: implemented in `Tools/package-release-app.sh`.

Concrete local-only target:

```text
.build/release/GlobalPetAssistant.zip
.build/release/GlobalPetAssistant.zip.sha256
```

Acceptance:

- `Tools/package-release-app.sh` emits a SHA-256 checksum.
- README has install, upgrade, and uninstall steps.
- Release artifact can be smoke-tested after unzipping.

## Priority 7: Optional Product Expansion

Do only after the app is stable under daily use:

- Multiple pets / source-specific pet reactions.
- Sound cues with mute controls.
- A small preferences window.
- Unix domain socket transport for `petctl`.
- More adapters for specific tools.
