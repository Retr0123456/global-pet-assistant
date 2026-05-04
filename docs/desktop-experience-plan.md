# Desktop Pet Experience Plan

This plan intentionally pauses infrastructure work. The goal is to make the pet feel useful and present on the desktop, not just like a small notification endpoint.

## Priority 0: Keep The Current Runtime Stable

Do not remove or rewrite the current event runtime. Use it as the base layer.

Keep:

- `EventRouter` for real task state.
- `ActionHandler` for actionable notifications.
- right-click menu for controls.
- edge snapping and saved position.
- release packaging.

Do not prioritize yet:

- token auth
- webhook bridge
- diagnostics panel
- hook installer

## Priority 1: Add A Pet Behavior Controller

What to do:

- Add a `PetBehaviorController` that sits between `EventRouter` and `PetSpriteView`.
- It chooses the visible animation from two inputs:
  - base state from runtime events, such as `running`, `waiting`, `failed`, `review`, `idle`
  - transient desktop interactions, such as hover, click, drag-left, drag-right

Why:

- Right now event state directly drives animation. That makes the pet responsive to jobs, but not expressive as a desktop companion.

Concrete behavior:

- base `idle`: play idle loop.
- mouse hover for 600 ms: temporarily play `waving`, then return to base state.
- normal click with no current action: play `jumping`, then return to base state.
- click with current action: open action, then play `review` briefly if the action succeeds.
- drag right: play `running-right` while dragging.
- drag left: play `running-left` while dragging.
- drag stop: snap/save position, then return to base state.
- failed/waiting events should not be permanently overwritten by hover/click; transient animations always return to the current base state.

Files likely touched:

- `Sources/GlobalPetAssistant/PetBehaviorController.swift`
- `Sources/GlobalPetAssistant/AppDelegate.swift`
- `Sources/GlobalPetAssistant/FloatingPetWindow.swift`
- `Sources/GlobalPetAssistant/PetSpriteView.swift`

Acceptance:

- Hovering over the pet waves once.
- Clicking the pet without action jumps once.
- Dragging right/left uses the matching running animation.
- A `failed` event returns to `failed` after hover/click transient animations.

## Priority 2: Add Animation Completion Support

What to do:

- Let `PetSpriteView` play one-shot animations and call back when complete.

Concrete API:

```swift
func playLoop(_ state: PetAnimationState)
func playOnce(_ state: PetAnimationState, completion: @escaping () -> Void)
```

Why:

- `waving` and `jumping` should feel like reactions, not infinite loops.

Acceptance:

- `idle`, `running`, `waiting`, `failed`, `review` still loop.
- `waving` and `jumping` can play once and return to the previous state.
- Reduced Motion still works by rendering a stable frame and completing the transient action.

## Priority 3: Add A Compact Speech Bubble

What to do:

- Show a small bubble above the pet for meaningful events.
- Keep it compact and work-focused.

Concrete first content:

- `title` on first line.
- `message` on second line if present.
- no instructions, no marketing copy, no keyboard shortcut hints.

Behavior:

- show bubble for `waiting`, `failed`, and `review`.
- hide bubble for plain `running` unless the event has a title.
- bubble follows pet position.
- bubble disappears when the event expires or is cleared.
- clicking the bubble performs the same current action as clicking the pet.

Sizing:

- max width: 260 px.
- clamp to visible screen.
- text truncates after 2 lines.
- no oversized hero typography.

Files likely touched:

- `Sources/GlobalPetAssistant/PetBubbleWindow.swift`
- `Sources/GlobalPetAssistant/AppDelegate.swift`
- `Sources/GlobalPetAssistant/EventRouter.swift`

Acceptance:

- `petctl notify --level danger --title "Build failed" --message "Click to open the log"` shows a bubble above the pet.
- Moving the pet keeps the bubble attached.
- Clearing the event hides the bubble.
- Bubble never appears off-screen.

## Priority 4: Add Size Controls

What to do:

- Make pet display size user-selectable and persistent.

Concrete sizes:

- Small: 25 percent atlas size.
- Medium: 35 percent atlas size.
- Large: 50 percent atlas size.

Menu locations:

- menu bar: `Pet Size > Small / Medium / Large`
- right-click menu: same submenu

Storage:

```text
~/.global-pet-assistant/display-preferences.json
```

Implementation notes:

- Replace the fixed `PetSpriteView.displayScale`.
- Resizing should preserve the pet's bottom-right anchor when possible.
- Re-run edge constraint and snap after size change.

Acceptance:

- Changing size updates the pet immediately.
- Relaunch preserves the selected size.
- Edge snapping and saved position still work.

## Priority 5: Add Idle Life Without Becoming Distracting

What to do:

- Add subtle idle behaviors.

Concrete behavior:

- every 90 to 180 seconds while idle, play one `waving` or `jumping` reaction.
- do not idle-react while events are paused.
- do not idle-react while there is an active `failed`, `waiting`, `review`, or `running` event.
- do not idle-react while the mouse is down.
- respect Reduced Motion.

Acceptance:

- With no active events, the pet occasionally reacts.
- During a running/failed/waiting event, idle reactions stop.
- User can pause events without random animation noise.

## Priority 6: Add State Preview Controls

What to do:

- Finish the remaining renderer TODO: state switching controls for non-idle animations.

Concrete UI:

- menu bar submenu: `Preview State`
- right-click submenu: `Preview State`
- states:
  - `idle`
  - `running`
  - `waiting`
  - `failed`
  - `review`
  - `waving`
  - `jumping`
  - `running-left`
  - `running-right`

Behavior:

- Preview is local only; it should not create an event.
- Preview plays for 5 seconds, then returns to the current router state.

Acceptance:

- Every atlas row can be visually checked without using `petctl`.
- TODO Phase 1 state switching controls can be marked complete.

## Priority 7: Add Desktop Presence Settings

What to do:

- Add a small set of behavior toggles, still using menus first.

Concrete toggles:

- `Stay Above All Windows`
- `Show Bubble`
- `Idle Reactions`
- `Click Opens Action`

Storage:

```text
~/.global-pet-assistant/display-preferences.json
```

Acceptance:

- Toggling `Stay Above All Windows` switches between floating and normal level.
- Toggling `Show Bubble` suppresses bubble display but keeps event state.
- Toggling `Idle Reactions` disables random idle animations.
- Toggling `Click Opens Action` lets the pet stay playful without opening files/apps on accidental clicks.

## Suggested Implementation Order

1. `PetSpriteView.playLoop/playOnce`
2. `PetBehaviorController`
3. hover/click/drag transient animations
4. speech bubble
5. size controls
6. idle life
7. state preview controls
8. desktop presence settings

This order keeps each step visible and testable on the desktop.
