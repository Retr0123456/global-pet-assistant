# Notification And Focus Architecture Reduction Plan

## Purpose

This document records the architecture reduction from notification plus terminal
control to notification plus focus.

Global Pet Assistant should first be a reliable desktop pet and local
development notification surface. It should show correct pet state, play smooth
pet animation, display short command flashes, display long-lived coding-agent
threads, and bring the user back to the relevant work surface. It should not
type back into terminals.

## Product Boundary

The active product boundary is:

- Pet runtime: reliable state, smooth spritesheet playback, stable floating
  window behavior, and predictable transient interactions.
- Command flash notifications: short shell, build, terminal plugin, and local
  script results.
- Coding-agent thread notifications: long-lived agent status from trusted hooks
  or structured plugin events.
- Focus actions: app-level focus by default, terminal window/tab/session focus
  when a trusted terminal plugin provides structured target metadata.

The current product boundary excludes:

- Reverse input through terminal plugins.
- Generic keyboard injection into a terminal or TUI.
- Permission approval or denial by typing text.
- Reading or scraping raw terminal screen history.
- Treating a terminal integration as a coding-agent provider.

Future agent control can be reconsidered only through a first-class agent or
app-server protocol that exposes structured send, approve, and deny semantics.

## Target Architecture

```text
shell hooks / local scripts / terminal plugins / agent hooks
        |
        v
NotificationIngress
        |
        +--> CommandFlashProjection
        |       |
        |       v
        |   EventRouter -> PetStateMachine -> PetRenderer
        |
        +--> AgentSessionEventReceiver
                |
                v
            AgentRegistry -> AgentThreadProjection -> ThreadPanel

ThreadPanel / notification action
        |
        v
FocusRouter
        |
        +--> app focus
        +--> terminal window focus
        +--> terminal tab/session focus
```

The two event classes stay separate:

- `CommandFlashEvent`: short-lived command lifecycle feedback. It may update the
  flash layer and temporary pet state. It does not create agent sessions.
- `AgentSessionEvent`: long-lived coding-agent lifecycle state. It updates
  `AgentRegistry`, thread rows, and projected pet state.

## Architecture Reductions

### Terminal Plugin Capability

Current direction:

```text
terminal-plugin: observe + focus
```

Rejected direction:

```text
terminal-plugin: observe + send-message + approve + deny
```

Required changes:

- Rename or reinterpret `TerminalTransport` as a terminal integration/focus
  abstraction instead of a control abstraction.
- Replace terminal-plugin `sendMessage` capability with a focus capability.
- Keep `TerminalSessionContext` as the only place for terminal-specific
  identity such as kitty window, tab, or session metadata.
- Keep terminal plugin events structured, schema-versioned, authenticated, and
  rate limited.

### Agent Control

Required changes:

- Remove terminal-plugin as an `AgentControl` transport.
- Keep `AgentCapability.sendMessage`, `approvePermission`, and
  `denyPermission` only for future first-class agent transports.
- Do not grant `sendMessage` from `CodexProvider`, `ClaudeCodeProvider`, or other
  providers only because terminal context exists.
- Thread rows backed only by terminal-plugin focus metadata should not show a
  reply input.

### Focus Router

Required changes:

- Introduce one focus path for app, folder, file, URL, and terminal targets.
- Keep existing `focus_kitty_window` behavior as a concrete terminal focus
  action.
- Add a generic model for terminal focus targets before adding more terminal
  integrations.
- Prefer app-level focus when no terminal plugin target exists.
- Prefer tab/session-level focus only when the plugin provides a trusted target.

### Pet Runtime

Required work before expanding terminal integrations:

- Verify state priority for `failed`, `waiting`, `running`, `review`, and
  `idle`.
- Keep pointer animations layered over event state, then return to the router
  state after transient animation.
- Verify smooth spritesheet playback without decoding during animation.
- Keep flash reminders short-lived, capped, and separate from long-lived thread
  rows.
- Keep thread panel rows compact, stateful, and readable.

## Execution Plan

### Phase 1: Document And Freeze The Boundary

- Update `README.md` with the notification plus focus boundary.
- Keep this document as the implementation checklist for the reduction.
- Add a note to terminal architecture docs that `send-message` is deferred or
  rejected for terminal-plugin transports.
- Update kitty implementation docs so kitty is a notification and focus
  integration, not an input transport.

Acceptance:

- README clearly says terminal plugins do not perform reverse input.
- Architecture docs do not present terminal-plugin `send-message` as current
  scope.

### Phase 2: Remove Terminal Reverse Input From Runtime

- Remove or disable `KittyTerminalTransport.sendMessage`.
- Remove or replace `TerminalPluginAgentControl`.
- Update `TerminalTransport` to expose observation and focus behavior only.
- Update tests that expect terminal-plugin `sendMessage`.
- Ensure terminal plugin failures never fall back to raw keyboard or shell text
  injection.

Acceptance:

- `swift test` has no expectations that terminal-plugin transport can send
  message text.
- No runtime path sends arbitrary user text into kitty.

### Phase 3: Update Agent Capabilities And Thread UI

- Stop assigning `.sendMessage` to terminal-plugin-backed sessions.
- Keep terminal context on known sessions only for display and focus.
- Hide or remove reply controls for terminal-plugin-only sessions.
- Keep approval-required as a visible state, but do not expose approve or deny
  actions unless a future first-class transport supports them.

Acceptance:

- Thread panel can show long-lived agent rows without a reply input.
- Waiting and approval-required sessions remain visible and distinguishable.
- Existing focus actions still work for supported sources.

### Phase 4: Harden Notification And Focus Basics

- Add focused tests for command flash projection.
- Add focused tests for agent session lifecycle projection.
- Add focused tests for focus action validation.
- Verify animation playback and state transitions with the app running.
- Verify kitty plugin command success/failure flash still works.

Acceptance:

- Command flash events do not create agent sessions.
- Agent session events do not become generic flash-only events.
- App-level focus works without a terminal plugin.
- Kitty focus works when trusted kitty target metadata exists.

## File Targets

Likely runtime files:

- `Sources/GlobalPetAssistant/AgentDiscovery/transports/TerminalTransport.swift`
- `Sources/GlobalPetAssistant/AgentDiscovery/transports/KittyTerminalTransport.swift`
- `Sources/GlobalPetAssistant/AgentDiscovery/transports/TerminalPluginAgentControl.swift`
- `Sources/GlobalPetAssistant/AgentDiscovery/providers/CodexProvider.swift`
- `Sources/GlobalPetAssistant/AgentDiscovery/AgentSession.swift`
- `Sources/GlobalPetAssistant/ThreadPanelSnapshot.swift`
- `Sources/GlobalPetAssistant/FloatingPetWindow.swift`
- `Sources/GlobalPetAssistant/ActionHandler.swift`

Likely tests:

- `tests/GlobalPetAssistantTests/KittyTerminalTransportTests.swift`
- `tests/GlobalPetAssistantTests/TerminalPluginAgentControlTests.swift`
- `tests/GlobalPetAssistantTests/TerminalPluginProviderIntegrationTests.swift`
- `tests/GlobalPetAssistantTests/AgentThreadProjectionTests.swift`
- `tests/GlobalPetAssistantTests/ActionHandlerTests.swift`

Likely docs:

- `README.md`
- `docs/agent-discovery-architecture.md`
- `docs/terminal-plugin-transport-architecture.md`
- `docs/kitty-terminal-transport-implementation-plan.md`
- `docs/codex-session-listening-refactor-plan.md`

## Non-Goals

- Do not add support for raw terminal/TUI agents.
- Do not add tmux fallback control.
- Do not use shell interpolation to control terminal sessions.
- Do not make terminal plugins responsible for identifying coding agents.
- Do not reintroduce reverse input as a hidden debug path.

## Final State

The reduced architecture should make Global Pet Assistant a reliable state,
notification, and focus companion:

- It knows what happened.
- It shows the right pet state.
- It keeps short and long notifications separate.
- It brings the user back to the right work surface.
- It does not type or approve actions on the user's behalf.
