# TODO

## Phase 0: Project Shape

- [x] Choose app name and bundle identifier.
- [x] Decide whether the first implementation uses AppKit-only views or SwiftUI hosted in AppKit.
- [x] Create the Swift package or Xcode project.
- [x] Add a small sample Codex-compatible pet asset for local testing.
- [x] Define initial app state storage under `~/.global-pet-assistant`.

## Phase 1: Renderer

- [x] Create transparent floating `NSPanel` or `NSWindow`.
- [x] Add always-on-top behavior.
- [x] Render one spritesheet using Core Animation.
- [x] Implement atlas validation for `1536x1872` 8x9 resources.
- [x] Implement frame timing for `idle`, `running`, `waiting`, `failed`, `review`, `jumping`, `running-left`, and `running-right`.
- [x] Add Reduced Motion support.
- [x] Add drag-to-move and basic click handling.
- [x] Add state switching controls for non-idle animations.

## Phase 2: Pet Packages

- [x] Load custom pets from `~/.global-pet-assistant/pets`.
- [x] Parse `pet.json`.
- [x] Validate `spritesheetPath` without allowing path traversal.
- [x] Support PNG and WebP.
- [x] Add "Open pet folder" menu item.
- [x] Load the first compatible Codex pet from `~/.codex/pets` as a development fallback.
- [x] Add optional importer from `~/.codex/pets`.

## Phase 3: Event Runtime

- [x] Define event schema.
- [x] Implement local event server.
- [x] Start with localhost HTTP or Unix domain socket.
- [x] Add request size limits.
- [x] Add source-level rate limiting.
- [x] Add event deduplication.
- [x] Add notification TTL handling.
- [x] Implement state priority routing.

## Phase 4: CLI

- [x] Create `petctl notify`.
- [x] Create `petctl state`.
- [x] Create `petctl clear`.
- [x] Create `petctl open-folder`.
- [x] Add shell examples for Codex CLI and Claude Code hooks.

## Phase 5: Actions

- [x] Implement `open_url`.
- [x] Implement `open_app` by bundle identifier.
- [x] Implement `open_file`.
- [x] Implement `open_folder`.
- [x] Add action allowlisting for unknown sources.
- [x] Add right-click menu for clearing or muting notifications.

## Phase 6: macOS Polish

- [x] Add menu bar icon.
- [x] Add launch-at-login option.
- [x] Add multi-display placement.
- [x] Add edge snapping.
- [x] Persist pet position.
- [x] Add pause or do-not-disturb mode.
- [x] Add crash recovery behavior.

## Phase 7: Adapters

- [x] Add Codex CLI hook examples.
- [x] Add Claude Code hook examples.
- [x] Add CI failure notification example.
- [x] Add generic webhook-to-local bridge only if a safe local boundary is clear.
