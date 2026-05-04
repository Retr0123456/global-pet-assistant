# Release Candidate Plan

This plan starts after the Daily-driver MVP is complete. The goal is to make the app testable, safer for third-party inputs, and ready to package as a real macOS app.

Status: implemented in the release-candidate pass that added pure logic tests, source action allowlisting, `open_file`/`open_app`, pet context controls, edge snapping, crash recovery, and release packaging.

## Priority 0: Checkpoint The Completed MVP

What to do:

- Review the current uncommitted display-size changes.
- Commit and push the completed Daily-driver MVP.

Original display-size checkpoint files:

- `Sources/GlobalPetAssistant/PetSpriteView.swift`
- `Sources/GlobalPetAssistant/FloatingPetWindow.swift`

How to do it:

```bash
git diff -- Sources/GlobalPetAssistant/PetSpriteView.swift Sources/GlobalPetAssistant/FloatingPetWindow.swift
swift build
Tools/verify-event-runtime.sh
Tools/package-debug-app.sh
open .build/GlobalPetAssistant.app
git status --short --branch
git add .
git commit -m "Complete daily-driver MVP"
git push origin main
```

Acceptance:

- The pet size looks intentional on screen.
- `swift build` passes.
- `Tools/verify-event-runtime.sh` passes.
- `main` is pushed and clean.

## Priority 1: Add A Real Test Suite

What to do:

- Add SwiftPM tests for the pure logic now carrying product behavior.

Files to add:

- `Tests/GlobalPetAssistantTests/EventRouterTests.swift`
- `Tests/GlobalPetAssistantTests/SourceRateLimiterTests.swift`
- `Tests/GlobalPetAssistantTests/ActionHandlerTests.swift`
- `Tests/GlobalPetAssistantTests/PetPackageTests.swift`

How to do it:

- Add a `.testTarget` to `Package.swift`.
- Use `@testable import GlobalPetAssistant`.
- Keep tests focused on deterministic logic; do not launch AppKit windows from unit tests.

Required tests:

- `EventRouter`:
  - `failed` beats `waiting`, `review`, and `running`.
  - newer same-source event replaces the old event.
  - `dedupeKey` removes the previous event from another source.
  - TTL expiry returns the router to `idle`.
  - `clear` removes all active events.
- `SourceRateLimiter`:
  - default source eventually returns denied.
  - `codex-cli` gets the higher configured limit.
  - retry-after value is positive when denied.
  - old timestamps fall out of the window.
- `ActionHandler`:
  - allows `https://github.com/Retr0123456/global-pet-assistant`.
  - allows `http://127.0.0.1:<port>`.
  - rejects `ftp://...`.
  - allows a project folder under the current user's workspace root.
  - rejects a file path when the action type is `open_folder`.
- `PetPackage`:
  - accepts a Codex-compatible package layout.
  - rejects `spritesheetPath` path traversal such as `../spritesheet.webp`.

Verification:

```bash
swift test
swift build
```

Acceptance:

- `swift test` passes locally.
- Tests fail if priority, TTL, dedupe, rate limiting, or action validation is broken.

## Priority 2: Add Source Action Allowlisting

What to do:

- Make actions source-aware.
- Unknown sources may still notify state, but cannot open URLs, files, folders, or apps.

Concrete first config:

```json
{
  "trustedSources": {
    "codex-cli": {
      "actions": ["open_url", "open_folder", "open_file", "open_app"],
      "urlHosts": ["github.com"],
      "folderRoots": ["/Users/example/codespace", "/Users/example/.global-pet-assistant"],
      "appBundleIds": ["com.openai.codex", "com.microsoft.VSCode"]
    },
    "claude-code": {
      "actions": ["open_folder", "open_file"],
      "folderRoots": ["/Users/example/codespace", "/Users/example/.global-pet-assistant"]
    },
    "local-build": {
      "actions": ["open_folder", "open_file"],
      "folderRoots": ["/Users/example/codespace", "/Users/example/.global-pet-assistant/logs"]
    },
    "ci": {
      "actions": ["open_url"],
      "urlHosts": ["github.com"]
    }
  }
}
```

How to do it:

- Add `AppConfiguration` loaded from `~/.global-pet-assistant/config.json`.
- Generate the default config if it does not exist.
- Pass `event.source` into action validation.
- If an event includes a disallowed action, reject it with HTTP `403` and JSON error `action_not_allowed`.
- Notifications without actions should still work for unknown sources.

Verification:

```bash
swift run petctl notify \
  --source unknown-tool \
  --level success \
  --title "Should reject action" \
  --action-url "https://github.com/Retr0123456/global-pet-assistant"

swift run petctl notify \
  --source codex-cli \
  --level success \
  --title "Should allow action" \
  --action-url "https://github.com/Retr0123456/global-pet-assistant"
```

Acceptance:

- Unknown source with action is rejected.
- `codex-cli` with GitHub URL is accepted.
- Unknown source without action is accepted.

## Priority 3: Finish The Action Surface

What to do:

- Implement `open_file`.
- Implement `open_app`.
- Add matching `petctl` flags.

Concrete `open_file` target:

```text
$HOME/.global-pet-assistant/logs/local-build-latest.log
```

How to make that file useful:

- Update `examples/hooks/local-build.sh` to write build output to that path.
- On build failure, send a `danger` event with `open_file` pointing to the latest log.

Concrete `open_app` targets:

```text
com.openai.codex
com.microsoft.VSCode
com.openai.chat
com.apple.Terminal
```

How to do it:

- Extend `LocalPetAction` handling for:
  - `open_file` with `path`
  - `open_app` with `bundleId`
- Extend `petctl notify` with:
  - `--action-file <path>`
  - `--action-app <bundle-id>`
- For `open_file`, require:
  - path exists
  - path is not a directory
  - path is under an allowlisted root
- For `open_app`, require:
  - bundle ID is allowlisted for the source
  - app can be resolved by LaunchServices

Verification:

```bash
mkdir -p ~/.global-pet-assistant/logs
echo "example build failure" > ~/.global-pet-assistant/logs/local-build-latest.log

swift run petctl notify \
  --source local-build \
  --level danger \
  --title "Build failed" \
  --message "Click to open the build log" \
  --action-file "$HOME/.global-pet-assistant/logs/local-build-latest.log"

swift run petctl notify \
  --source codex-cli \
  --level success \
  --title "Open Codex" \
  --action-app "com.openai.codex"
```

Acceptance:

- Clicking the pet opens the build log file.
- Clicking the pet opens Codex for `com.openai.codex`.
- Unknown or unallowed app bundle IDs are rejected.

## Priority 4: Add Right-click Controls

What to do:

- Add a contextual menu on the pet.

Concrete menu items:

- `Open Action`
- `Clear Current Event`
- `Mute Source`
- `Unmute All Sources`
- `Pause Events`
- `Resume Events`
- `Open Pet Folder`

How to do it:

- Track the selected event source in `EventRouterSnapshot`.
- Store muted sources in app configuration.
- Use `rightMouseDown` or `menu(for:)` on the pet content view.
- Keep the existing menu bar controls, but make right-click the fast path.

Acceptance:

- Right-clicking the pet shows the context menu.
- Muting `spam-test` stops future `spam-test` state changes.
- Clearing the current event falls back to the next active event or `idle`.

## Priority 5: Add Edge Snapping

What to do:

- Snap the floating pet to screen edges after drag.
- Preserve the snapped position across relaunch.

Suggested behavior:

- Snap when the pet is within 24 px of a visible screen edge.
- Preserve explicit free-floating placement when outside the snap threshold.
- Revalidate the saved position when display layout changes.

Acceptance:

- Dragging near the right edge snaps to the right edge.
- Dragging near the bottom edge snaps to the bottom edge.
- Relaunch preserves the snapped position.
- Moving between displays does not put the pet off-screen.

## Priority 6: Add Crash Recovery And Release Packaging

What to do:

- Make app startup robust.
- Package a distributable app artifact.

Crash recovery behavior:

- If config is invalid, back it up and regenerate defaults.
- If a custom pet fails validation, fall back to the next valid pet.
- If the event server port is busy, show a visible menu-bar warning.
- On startup, clear stale running/review events; do not restore old failed state blindly.

Packaging behavior:

- Create `Tools/package-release-app.sh`.
- Build `.build/release/GlobalPetAssistant.app`.
- Include resource bundle and Info.plist.
- Add ad-hoc signing first:

```bash
codesign --force --deep --sign - .build/release/GlobalPetAssistant.app
```

- Zip the app:

```bash
ditto -c -k --keepParent .build/release/GlobalPetAssistant.app .build/release/GlobalPetAssistant.zip
```

Acceptance:

- Release app launches by double click.
- `petctl` can talk to the release app.
- App survives invalid config and invalid custom pet package.
- A zipped artifact is available under `.build/release/`.

## Priority 7: Decide Whether To Build The Webhook Bridge

Status: implemented as an explicit local-only `pet-webhook-bridge` executable.

What to do:

- Keep this behind allowlisting, tests, and bearer-token authentication.
- Keep it local-only by default.

Concrete first bridge:

- `pet-webhook-bridge` listens on `127.0.0.1:17322`.
- It accepts GitHub-style JSON payloads from local tools only.
- It forwards normalized events to `http://127.0.0.1:17321/events`.

Do not do yet:

- Do not expose a public webhook listener.
- Do not accept arbitrary shell commands.
- Do not open actions from webhook events unless the source is allowlisted.

Acceptance:

- Local bridge can convert a GitHub Actions failure payload into a `ci` danger event.
- The bridge is disabled unless explicitly started.
