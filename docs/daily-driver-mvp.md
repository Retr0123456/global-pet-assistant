# Daily-driver MVP Task List

This plan turns the current renderer and event runtime into a daily-use local assistant.

## Priority 0: Publish The Current Milestone

What to do:

- Push the current local commit on `main`.

How to do it:

```bash
git status --short --branch
git push origin main
gh repo view --json nameWithOwner,url,visibility
```

Acceptance:

- `git status --short --branch` shows `main...origin/main` with no `ahead`.
- The repo remains private at `https://github.com/Retr0123456/global-pet-assistant`.

## Priority 1: Add Source-level Rate Limiting

What to do:

- Rate limit event writes by `source`.
- Exempt `GET /healthz` and `clear` events.
- Return HTTP `429` with JSON error `rate_limited` when a source exceeds the limit.

Suggested first policy:

- `codex-cli`: 30 events per 60 seconds.
- `claude-code`: 30 events per 60 seconds.
- `ci`: 10 events per 60 seconds.
- unknown/default source: 20 events per 60 seconds.

How to do it:

- Add a small `SourceRateLimiter` type under `Sources/GlobalPetAssistant/`.
- Check the limit in `LocalEventServer` after JSON decode and before `EventRouter.accept`.
- Include `retryAfterMs` in the 429 response.
- Keep the implementation in memory only for now; no database or persistence.

Verification:

```bash
swift build
swift run GlobalPetAssistant

for i in {1..25}; do
  curl -sS -o /dev/null -w "%{http_code}\n" \
    -H 'Content-Type: application/json' \
    -d '{"source":"spam-test","type":"task.tick","level":"running","ttlMs":1000}' \
    http://127.0.0.1:17321/events
done

swift run petctl clear
```

Acceptance:

- A burst from `spam-test` eventually returns `429`.
- A normal `codex-cli` success event still returns `202`.
- `petctl clear` still works while the source is rate limited.

## Priority 2: Add Real Hook Examples

What to do:

- Add copy-pasteable shell examples for Codex CLI, Claude Code, and local scripts.
- Do not build a complex adapter yet. Keep examples as thin wrappers around `petctl`.

Concrete first targets:

- Use `source=codex-cli` for Codex task lifecycle events.
- Use `source=claude-code` for Claude Code task lifecycle events.
- Use `source=local-build` for `swift build` or other local scripts.

Files to add:

- `examples/hooks/codex-task.sh`
- `examples/hooks/claude-task.sh`
- `examples/hooks/local-build.sh`

Example behavior:

```bash
swift run petctl state running \
  --source codex-cli \
  --message "Codex is editing global-pet-assistant" \
  --ttl-ms 30000 \
  --dedupe-key "codex:global-pet-assistant"

swift run petctl notify \
  --source codex-cli \
  --level success \
  --title "Codex task complete" \
  --message "Review the changes in global-pet-assistant" \
  --dedupe-key "codex:global-pet-assistant"

swift run petctl notify \
  --source codex-cli \
  --level danger \
  --title "Codex task failed" \
  --message "Open the repo and inspect the failure"
```

Acceptance:

- Running each example changes the pet state as expected.
- README explains where to copy the examples and what environment variables they accept.
- `Tools/verify-event-runtime.sh` covers at least one hook example.

## Priority 3: Implement Click Actions For Specific Useful Targets

What to do:

- Store the selected active event's `action` in the router.
- Execute the current action when the pet is clicked.
- Start with only `open_url` and `open_folder`.

Concrete first `open_url` target:

- Open the private GitHub repo in the default browser:

```text
https://github.com/Retr0123456/global-pet-assistant
```

Concrete second `open_url` target:

- Open GitHub Actions for this repo when a CI-style event fails:

```text
https://github.com/Retr0123456/global-pet-assistant/actions
```

Concrete first `open_folder` target:

- Open the current project workspace in Finder:

```text
/Users/ryanchen/codespace/global-pet-assistant
```

Concrete second `open_folder` target:

- Open the app-owned pet folder:

```text
/Users/ryanchen/.global-pet-assistant/pets
```

How to do it:

- Extend `petctl notify` with:
  - `--action-url <url>`
  - `--action-folder <path>`
- Add an `ActionHandler` in `Sources/GlobalPetAssistant/`.
- Validate `open_url`:
  - allow `https://github.com/`
  - allow `http://127.0.0.1` for local dev
  - reject other schemes at first
- Validate `open_folder`:
  - path must exist
  - path must be a directory
  - for the first version, allow paths under `/Users/ryanchen/codespace` and `/Users/ryanchen/.global-pet-assistant`
- Wire pet click from `PetWindowContentView` or `PetSpriteView` to `ActionHandler`.
- Keep drag-to-move working. Treat a click as an action only when mouse movement stays below a small threshold.

Verification:

```bash
swift run petctl notify \
  --source codex-cli \
  --level success \
  --title "Open repo" \
  --message "Click the pet to open GitHub" \
  --action-url "https://github.com/Retr0123456/global-pet-assistant" \
  --ttl-ms 60000
```

```bash
swift run petctl notify \
  --source local-build \
  --level warning \
  --title "Open project folder" \
  --message "Click the pet to open the workspace" \
  --action-folder "/Users/ryanchen/codespace/global-pet-assistant" \
  --ttl-ms 60000
```

Acceptance:

- Clicking the pet opens the GitHub repo for the URL event.
- Clicking the pet opens Finder at the project folder for the folder event.
- Invalid URLs and non-directory paths are rejected.
- Dragging the pet does not accidentally trigger an action.

## Priority 4: Own Pet Packages Instead Of Depending On Codex Fallback

What to do:

- Load pets from the app-owned directory before checking `~/.codex/pets`.
- Add a CLI command to open the app pet folder.
- Add an importer from the current Codex pet folder.

Concrete first pet import:

- Import the existing Codex pet:

```text
/Users/ryanchen/.codex/pets/emma
```

- Destination:

```text
/Users/ryanchen/.global-pet-assistant/pets/emma
```

How to do it:

- Update `PetPackage` loading order:
  1. first compatible pet in `~/.global-pet-assistant/pets`
  2. first compatible pet in `~/.codex/pets`
  3. bundled placeholder
- Add `petctl open-folder` to open:

```text
/Users/ryanchen/.global-pet-assistant/pets
```

- Add `petctl import-codex-pet emma` or a small `Tools/import-codex-pet.sh emma`.
- Copy `pet.json` and `spritesheet.*`; do not symlink for the first version.

Verification:

```bash
swift run petctl open-folder
swift run petctl import-codex-pet emma
find ~/.global-pet-assistant/pets/emma -maxdepth 1 -type f
swift run GlobalPetAssistant
```

Acceptance:

- Emma loads from `~/.global-pet-assistant/pets/emma`.
- If the app-owned pet is removed, the app still falls back to `~/.codex/pets/emma`.
- If both are unavailable, the bundled placeholder still loads.

## Priority 5: Daily-use macOS Polish

What to do after the action and pet package flow works:

- Persist pet position.
- Add launch-at-login.
- Add a real menu bar icon.
- Add pause / do-not-disturb mode.
- Add multi-display placement.

Acceptance:

- Relaunching the app keeps the pet where the user left it.
- The app can start after login without manual terminal commands.
- A noisy source can be muted without quitting the app.
