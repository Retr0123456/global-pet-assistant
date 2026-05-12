# Codex Session Listening Refactor Plan

## Purpose

This document is the implementation plan for the first clean slice of the agent
architecture: Codex session listening.

The product remains a general desktop pet runtime that accepts events from any
local source. Codex is added as a first-class long-lived session integration,
not as a replacement for generic events.

The implementation rule for this refactor is:

```text
Refactor or add clean modules before modifying existing modules.
It is acceptable for an intermediate branch to not run.
It is not acceptable to keep unclear ownership, hidden coupling, or agent-shaped
generic event code.
```

## Scope

In scope:

- Codex CLI hook-backed session listening.
- A new agent discovery module with real Codex provider logic.
- `AgentRegistry` as the source of truth for Codex sessions.
- Hook bridge and hook socket ingestion for Codex lifecycle events.
- Projection from Codex sessions into pet animation and long-lived thread data.
- Empty shells for Claude Code and OpenCode providers.
- Empty shell for the app-server control transport.
- Empty shells for terminal plugin transport, process scanner, workspace scanner,
  and app-server scanner.
- Tests and verification criteria for the Codex path and generic event
  compatibility.

Out of scope for this slice:

- Claude Code behavior.
- OpenCode behavior.
- Codex app-server websocket integration.
- Codex approval or denial from the pet UI.
- Codex follow-up message sending.
- Tmux injection.
- Raw terminal/TUI control.
- Kitty terminal plugin behavior.
- Process scanning as a required discovery path.
- Rollout JSONL history rendering in the UI.

Rollout JSONL parsing may be introduced as a later read-only enrichment phase,
but it must not be required for the first session-listening milestone.

## Reference Material

Reference plan and behavior source:

```text
/Users/ryanchen/codespace/ping-island/docs/codex-session-discovery.md
```

Important reference decisions to reuse:

- Codex hook events are the strongest first real-time path for Codex CLI.
- The hook bridge should read hook stdin and terminal environment.
- Session identity should prefer Codex session/thread ids and only fall back to
  terminal evidence.
- Terminal context matters for distinguishing CLI-style sessions from desktop or
  app-server contexts.
- Terminal plugin context, such as kitty session identity, should be treated as
  structured context only. It does not replace provider identity.
- Rollout JSONL is a history/enrichment fallback, not the primary real-time
  session source.
- App-server is the richer control path, but it is out of scope for this first
  slice.

## Current State To Replace

Current Codex hook flow:

```text
Codex hook
  -> examples/codex-hooks/hooks/codex-pet-event.py
  -> map hook payload directly into LocalPetEvent
  -> POST http://127.0.0.1:17321/events
  -> EventRouter
  -> pet state and current Thread Panel rows
```

This is useful but not clean enough for long-term multi-agent support because:

- `LocalPetEvent.source` is acting as a pseudo session identity.
- Codex metadata is squeezed into generic event fields.
- There is no durable agent session store.
- The Thread Panel only understands active generic router events.
- Future controls would be tempted to become generic `LocalPetAction`s.

Target Codex session listening flow:

```text
Codex hook
  -> global-pet-agent-bridge --source codex
  -> Unix socket envelope
  -> AgentHookSocketServer
  -> HookEventReceiver
  -> CodexProvider
  -> AgentRegistry
  -> AgentThreadProjection
  -> long-lived agent thread panel

AgentRegistry
  -> AgentEventProjection
  -> LocalPetEvent
  -> EventRouter
  -> pet animation and generic status reaction
```

The projection into `EventRouter` is one-way. `EventRouter` must not become the
agent session store.

## Final Module Shape

Create a new module directory:

```text
Sources/GlobalPetAssistant/AgentDiscovery/
  AgentDiscoveryService.swift
  AgentRegistry.swift
  AgentSession.swift
  AgentProvider.swift
  AgentControlTransport.swift
  AgentControl.swift
  AgentEvent.swift
  AgentThreadProjection.swift
  AgentEventProjection.swift
  AgentHookEnvelope.swift
  AgentHookSocketServer.swift
  TerminalPluginEvent.swift
  TerminalPluginEventReceiver.swift
  TerminalCommandFlashProjection.swift

  providers/
    CodexProvider.swift
    ClaudeCodeProvider.swift
    OpenCodeProvider.swift

  transports/
    AgentAppServerTransport.swift
    TerminalTransport.swift
    KittyTerminalTransport.swift

  sources/
    HookEventReceiver.swift
    TerminalPluginSource.swift
    WorkspaceScanner.swift
    ProcessScanner.swift
    AppServerScanner.swift

  hooks/
    HookInstaller.swift
    CodexHookProfile.swift
```

Add a new bridge executable target:

```text
Sources/globalPetAgentBridge/main.swift
```

Package product:

```text
global-pet-agent-bridge
```

The bridge is a short-lived command process. It reads Codex hook stdin, enriches
the payload with environment and terminal context, sends one envelope to the app
socket, and exits.

Raw TUI is intentionally not a compatibility target. Terminal environment data
may be kept as context when Codex hooks provide it, but this plan does not use
terminal control for discovery, observation, or message injection.

Terminal plugin support is a later trusted-terminal slice. The first concrete
implementation should be `KittyTerminalTransport`, but this Codex listening
slice only adds clean placeholders and does not send messages through kitty.

## Naming Rules

Use these names consistently:

- `AgentSession.id`: canonical coding-agent session identity.
- `LocalPetEvent.source`: generic event source label only.
- `AgentCapabilityRouteKind`: session capability route for observation, focus,
  or future first-class agent control.
- `TerminalTransport`: trusted terminal plugin control abstraction.
- `KittyTerminalTransport`: first `TerminalTransport` implementation, not an
  agent provider.
- `LocalEventServer`: pet event ingress server only.
- `AgentHookSocketServer`: agent hook ingestion server only.
- `AgentAppServerTransport`: future Codex app-server-style control transport.

Do not introduce a generic `AgentTransport` name. It is too easy to confuse with
the existing generic event transport language.

## Phase 0: Pre-Refactor Guardrails

Goal: make the architectural boundary explicit before code starts moving.

Tasks:

- Add this plan document.
- Keep `docs/agent-discovery-architecture.md` as the high-level design source.
- Add a short link from the high-level agent architecture doc to this refactor
  plan.
- Add a temporary TODO section in this document for open implementation
  questions instead of hiding decisions in code comments.

Acceptance criteria:

- No runtime code is changed.
- The plan clearly states that generic events and agent sessions are separate
  pipelines.
- The plan clearly states that only Codex session listening is in scope.
- The plan clearly rejects adding agent-only fields to `LocalPetEvent`.

## Phase 1: Add Clean Agent Models And Empty Shells

Goal: create the permanent agent architecture skeleton before wiring Codex.

Add:

- `AgentKind`
- `AgentCapabilityRouteKind`
- `AgentStatus`
- `AgentCapability`
- `AgentSession`
- `AgentSessionUpdate`
- `AgentDiscoveryCandidate`
- `AgentProvider`
- `AgentControlTransport`
- `AgentControl`
- `AgentEvent`
- `AgentRegistry`
- `AgentRegistrySnapshot`
- `AgentThreadSnapshot`
- `AgentThreadProjection`
- `AgentEventProjection`
- `TerminalSessionContext`
- `TerminalPluginEvent`
- `TerminalPluginEventReceiver`
- `TerminalTransport`

Create placeholders:

- `ClaudeCodeProvider`
- `OpenCodeProvider`
- `AgentAppServerTransport`
- `KittyTerminalTransport`
- `TerminalPluginSource`
- `WorkspaceScanner`
- `ProcessScanner`
- `AppServerScanner`

Placeholder behavior:

- Compile.
- Return empty candidates or unsupported capability results.
- Log nothing by default.
- Do not mutate registry.
- Do not pretend support exists.

Registry requirements:

- Upsert by `AgentSession.id`.
- Preserve `createdAt` on merge.
- Refresh `lastSeenAt` on accepted updates.
- Merge metadata conservatively.
- Preserve stronger known fields over weaker inferred fields.
- Track `AgentKind` and `AgentCapabilityRouteKind`.
- Support expiry without deleting completed sessions immediately.

Suggested merge strength:

```text
hook event > terminal plugin event > app-server snapshot > rollout JSONL > process scan > workspace marker
```

For this first slice, only `hook event` is implemented. `terminal plugin event`
is included in the model so kitty can be added later without treating terminal
screen text as an identity source.

Acceptance criteria:

- Agent model code exists under `AgentDiscovery/`.
- Empty non-Codex providers and transports exist but expose no behavior.
- `KittyTerminalTransport` exists only as an unsupported placeholder.
- `LocalPetEvent` is unchanged.
- `EventRouter` is unchanged.
- `LocalEventServer` is unchanged.
- Unit tests cover registry upsert, merge, last-seen refresh, expiry, and
  hook-event metadata merge. Source precedence for future non-hook inputs may be
  covered as static ordering tests, but those sources must not be implemented in
  this slice.

## Phase 2: Define Hook Envelope And Bridge Protocol

Goal: stop mapping Codex hooks directly into `LocalPetEvent`.

Add `AgentHookEnvelope`:

```swift
struct AgentHookEnvelope: Codable, Equatable {
    var source: AgentHookSource
    var receivedAt: Date
    var rawPayload: JSONValue
    var arguments: [String]
    var environment: AgentHookEnvironment
    var terminal: AgentTerminalContext
    var metadata: [String: JSONValue]
}
```

Required envelope fields:

- source: `codex`
- raw hook payload
- current working directory
- terminal TTY if available
- parent process id if cheaply available
- `TERM_PROGRAM`
- `__CFBundleIdentifier`
- `ITERM_SESSION_ID`
- `TERM_SESSION_ID`
- `TMUX`
- `TMUX_PANE`
- `KITTY_WINDOW_ID`
- `KITTY_LISTEN_ON`
- SSH and IDE remote hints if available
- transcript path / rollout path / session file path if present in payload

Socket protocol:

- Use a Unix domain socket for agent hook ingestion.
- Proposed default:

```text
~/.global-pet-assistant/run/agent-hooks.sock
```

- Allow override:

```text
GLOBAL_PET_AGENT_SOCKET
```

- Use one newline-delimited JSON envelope per connection.
- Enforce a body size limit.
- The bridge should time out quickly for non-blocking events.
- For this slice, the bridge does not wait for approval responses.

Acceptance criteria:

- The bridge protocol is documented in code and tests.
- The bridge can encode representative Codex hook stdin into
  `AgentHookEnvelope`.
- The app-side decoder rejects invalid JSON and oversized payloads.
- No hook envelope is directly routed to `EventRouter`.
- No approval response protocol is implemented yet.

## Phase 3: Add `global-pet-agent-bridge`

Goal: introduce a new bridge executable without modifying generic event routing.

Bridge responsibilities:

- Parse `--source codex`.
- Read stdin as JSON.
- Capture selected environment variables.
- Detect current `PWD` and TTY evidence.
- Build `AgentHookEnvelope`.
- Send the envelope to `AgentHookSocketServer`.
- Exit successfully if the app is not running, so Codex is never blocked by the
  pet app.
- Write a local audit line under `~/.global-pet-assistant/logs/agent-hooks.jsonl`
  only if logging can be done without blocking.

Bridge non-responsibilities:

- Do not map to `LocalPetEvent`.
- Do not call `http://127.0.0.1:17321/events`.
- Do not decide final `AgentSession.id`.
- Do not infer final `AgentStatus`.
- Do not approve or deny permissions.
- Do not send tmux text.

Compatibility transition:

- Keep `examples/codex-hooks/hooks/codex-pet-event.py` until cutover is proven.
- New hook installer should point to `global-pet-agent-bridge`.
- Old hook script should be treated as legacy compatibility, not the new
  architecture path.

Acceptance criteria:

- `swift run global-pet-agent-bridge --source codex` can read a sample Codex hook
  payload and produce/send a valid envelope.
- If the socket is unavailable, bridge exits `0`.
- Bridge has tests for source parsing, JSON stdin handling, environment capture,
  and missing app behavior.
- Bridge does not import or depend on `LocalPetEvent`.

## Phase 4: Add App-Side Hook Ingestion

Goal: receive bridge envelopes inside the app and convert them into source
candidates.

Add:

- `AgentHookSocketServer`
- `HookEventReceiver`
- `AgentHookEvent`

`AgentHookSocketServer` responsibilities:

- Listen on the configured Unix socket.
- Decode one envelope per connection.
- Enforce payload size and JSON validity.
- Forward the envelope to `HookEventReceiver`.
- Never call `EventRouter` directly.
- Never execute control actions.

`HookEventReceiver` responsibilities:

- Accept `AgentHookEnvelope`.
- Route `source == codex` to `CodexProvider`.
- Ignore unsupported sources cleanly.
- Emit `AgentSessionUpdate` through an `AgentDiscoveryService`-owned ingestion
  interface. `HookEventReceiver` must not mutate `AgentRegistry` directly.

Socket lifecycle:

- Start after `AppStorage.ensureLayout()`.
- Stop on app termination.
- Remove stale socket file on clean startup if safe.
- Log startup, decode failure, accepted envelope, ignored envelope, and provider
  failure to `runtime.jsonl` or a dedicated `agent-hooks.jsonl`.

Acceptance criteria:

- App starts hook socket server without changing `LocalEventServer`.
- Invalid hook envelopes are rejected without crashing.
- Unsupported sources are ignored without creating sessions.
- Codex envelopes reach `CodexProvider`.
- Existing `petctl notify/state/flash/clear` continues to work through
  `LocalEventServer`.

## Phase 5: Implement `CodexProvider`

Goal: normalize Codex hook envelopes into durable `AgentSessionUpdate`s.

Codex event coverage:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PostToolUse`
- `PermissionRequest`
- `Stop`

Session identity priority:

```text
payload.session_id
payload.sessionId
payload.thread_id
payload.threadId
payload.conversation_id
payload.conversationId
env.CODEX_SESSION_ID
env.CODEX_THREAD_ID
env.CODEX_CONVERSATION_ID
transcript session_meta parent_thread_id when this is a subagent
terminal session fallback
TTY fallback
cwd fallback only as last resort
```

Canonical identity rule:

- Use the real Codex session/thread id when present.
- If transcript `session_meta` identifies a subagent with a parent thread id,
  use the parent id as the canonical session id for the primary long-lived row.
- Preserve subagent metadata as session metadata or latest message context.
- Use hashed fallback ids for terminal-derived identities to avoid leaking long
  terminal strings into UI keys.

Status mapping:

| Codex hook | Agent status | Notes |
| --- | --- | --- |
| `SessionStart` | `started` or `running` | Prefer `started` internally, projected as running. |
| `UserPromptSubmit` | `running` | Title from prompt, cwd from payload/env. |
| `PreToolUse` | `running` | Update latest tool name and message. |
| `PostToolUse` | `running` | Update tool result summary if present. |
| `PermissionRequest` | `waiting` | Set `pendingPermissionDescription`; no approve/deny capability yet. |
| `Stop` | `completed` | Preserve session as long-lived until expiry/archive policy. |

Metadata to preserve:

- raw hook event name
- cwd
- title candidate
- preview/message candidate
- terminal context
- tty
- terminal integration session metadata if present
- transcript path
- rollout path
- session file path
- tool name and tool input preview
- pending permission description
- subagent label if present

Capability policy for first slice:

```text
observe
```

Do not expose:

```text
read-history
send-message
approve-permission
deny-permission
```

These are intentionally disabled until rollout parsing or app-server transport
is explicitly implemented.

Acceptance criteria:

- A sample `SessionStart` creates one Codex `AgentSession`.
- A sample `UserPromptSubmit` updates the same session.
- A sample `PermissionRequest` updates status to `waiting` and projects
  `approval-required` in thread UI projection.
- A sample `Stop` updates status to `completed` without deleting the session.
- Two hook events with the same Codex session id never create duplicate sessions.
- Subagent metadata does not create duplicate primary rows when parent thread id
  is available.
- Fallback terminal-derived ids are stable for repeated events from the same
  terminal context.

## Phase 6: Wire `AgentRegistry` To App Runtime

Goal: make Codex sessions available to the app without changing generic event
ownership.

Add `AgentDiscoveryService`:

- Owns `AgentRegistry`.
- Owns hook receiver integration.
- Publishes registry snapshots.
- Produces pet event projection snapshots.

App startup changes:

- Add `private var agentDiscoveryService: AgentDiscoveryService?`.
- Start it after storage/token/config initialization.
- Stop it on termination.
- Inject closures for:
  - agent registry snapshot updates
  - projected `LocalPetEvent`s for pet animation

Projection rule:

```text
AgentSession update
  -> AgentEventProjection makes one LocalPetEvent
  -> AppDelegate.acceptEvent(projectedEvent)
```

Projected event source should be generic and stable:

```text
agent:codex:<short-session-key>
```

This projected source is not canonical agent identity. It is only the generic
event source label needed by `EventRouter`.

Acceptance criteria:

- `AgentDiscoveryService` starts and stops with the app.
- Codex hook events update `AgentRegistry`.
- Registry updates can project pet state changes.
- `EventRouter` does not know about `AgentSession`.
- `LocalPetEvent` remains generic.
- The pet still reacts to Codex running/waiting/completed/failed projections.

## Phase 7: Build Long-Lived Agent Thread Projection

Goal: prepare the Thread Panel for agent sessions without treating router events
as sessions.

Add:

- `AgentThreadSnapshot`
- `AgentThreadProjection`
- `ThreadPanelSnapshot`
- `GenericThreadSnapshot` if needed to decouple existing
  `PetThreadSnapshot` from panel rendering.

Desired panel data model:

```swift
struct ThreadPanelSnapshot: Equatable {
    var genericThreads: [PetThreadSnapshot]
    var agentThreads: [AgentThreadSnapshot]
    var activeCount: Int
}
```

Agent thread status projection:

| Agent status | Thread status |
| --- | --- |
| `started` | `running` |
| `running` | `running` |
| `waiting` with pending permission | `approval-required` |
| `waiting` | `waiting` |
| `completed` | `success` |
| `failed` | `failed` |
| `unknown` | `info` |

Panel behavior:

- Agent sessions remain visible beyond the short `EventRouter` TTL.
- Generic events continue to expire by `EventRouter` rules.
- Flash messages remain owned by the existing flash layer and are not refactored
  in this slice.
- Dismissing an agent row hides/archives that agent view entry.
- Dismissing a generic row clears that `EventRouter` source.

Implementation rule:

- Prefer introducing `ThreadPanelSnapshot` and adapting `FloatingPetWindow` once,
  rather than adding agent-specific conditionals throughout the existing thread
  row code.
- Shared row rendering may be reused only after both generic and agent snapshots
  are projected into a neutral display row model.

Acceptance criteria:

- Codex sessions appear as long-lived agent rows.
- Existing generic `petctl notify` rows still appear.
- Completed Codex session row remains visible according to agent expiry policy,
  not generic event TTL.
- Thread row rendering does not inspect `AgentSession` directly.

## Phase 8: Hook Installer Cutover

Goal: install Codex hooks for the new bridge without losing user hooks.

Add or refactor:

- `HookInstaller`
- `CodexHookProfile`
- `Tools/install-codex-hooks.sh`

Codex hook events to install:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PostToolUse`
- `PermissionRequest`
- `Stop`

For this slice:

- The hook command should be non-blocking.
- `PermissionRequest` should be observed but not answered.
- Do not use an 86400-second blocking timeout yet.
- Preserve existing non-managed user hook entries.
- Mark managed entries clearly so they can be updated or removed safely.

Target command:

```text
<repo-or-installed-path>/global-pet-agent-bridge --source codex
```

Acceptance criteria:

- Installer preserves unrelated user hooks.
- Installer can update its own managed entries idempotently.
- Installed hooks invoke `global-pet-agent-bridge --source codex`.
- Uninstall or disable path is documented before enabling by default.
- Existing global disable switch semantics are either preserved or replaced with
  an explicit equivalent.

## Deferred: Codex Rollout JSONL Interfaces

Goal: reserve a clean future home for history enrichment without making it part
of the Codex session-listening milestone.

Do not implement these files in the first slice unless the Codex hook-backed
identity work is already complete. When the time comes, use these names:

- `CodexRolloutParser`
- `CodexThreadSnapshot`
- `CodexRolloutSyncScheduler`

Placeholder behavior:

- Expose protocols and empty unsupported results.
- Do not scan `~/.codex/sessions` automatically yet.
- Do not mutate `AgentRegistry`.
- Do not expose `read-history` capability.

Future parser requirements:

- Prefer explicit `session_file_path`, `rollout_path`, or `transcript_path`.
- Fall back to `~/.codex/sessions/**/rollout-*.jsonl` only when needed.
- Cache by file path and modification date.
- Parse `session_meta`, `turn_context`, `event_msg`, and `response_item`.
- Sync into `AgentRegistry` only when it adds missing metadata or history.

Future acceptance criteria:

- Rollout parser placeholders compile.
- No automatic filesystem scan is started.
- `read-history` remains absent from Codex capabilities.
- Future implementation has a named home and does not need to modify
  `LocalPetEvent`.

## Deferred: Control Contracts

Goal: prevent accidental dirty control behavior.

Do not add runtime control classes in the Codex session-listening slice. Reserve
these names for future control work:

- `CodexApprovalController`
- `CodexFollowUpController`
- `CodexAppServerTransport`

Until those slices are implemented, capability flags are the only contract:
Codex hook-backed sessions must not expose `send-message`,
`approve-permission`, or `deny-permission`.

Forbidden in this slice:

- Approval by generic `LocalPetAction`.
- Approval by blind tmux text injection.
- Denial by blind terminal typing.
- Follow-up text through hooks unless a specific pending intervention response
  protocol is implemented.
- App-server connection attempts.

Acceptance criteria:

- UI does not show working approve/deny buttons for Codex.
- If a permission is pending, the row may show `approval-required`, but control
  actions are disabled or absent.
- No code path sends text to tmux.
- No code path sends text through kitty.
- No code path launches `codex app-server`.

## Verification Plan

### Unit Tests

Required test groups:

- `AgentRegistryTests`
  - create session
  - merge same id
  - preserve createdAt
  - refresh lastSeenAt
  - hook-event metadata merge
  - expiry policy

- `CodexProviderTests`
  - maps `SessionStart`
  - maps `UserPromptSubmit`
  - maps `PreToolUse`
  - maps `PostToolUse`
  - maps `PermissionRequest`
  - maps `Stop`
  - canonicalizes session id
  - uses terminal fallback only when needed
  - handles subagent parent thread id
  - preserves transcript/rollout paths

- `AgentHookEnvelopeTests`
  - bridge envelope encoding
  - socket decoder accepts valid envelope
  - socket decoder rejects invalid payload
  - size limit
  - missing optional terminal fields

- `AgentEventProjectionTests`
  - running projects to pet running
  - waiting permission projects to warning/waiting
  - completed projects to success/review
  - failed projects to danger/failed
  - projection source does not become canonical agent id

- `AgentThreadProjectionTests`
  - Codex running row
  - Codex waiting row
  - Codex approval-required row
  - Codex completed row remains long-lived
  - generic rows and agent rows remain distinct

### Local Manual Verification

Commands and checks:

```bash
swift test
swift run GlobalPetAssistant
swift run petctl notify --level success --title "Generic event still works"
swift run global-pet-agent-bridge --source codex < Tests/GlobalPetAssistantTests/Fixtures/sample-codex-user-prompt.json
```

Expected results:

- Generic petctl event still appears and expires by generic rules.
- Codex sample creates or updates one agent session.
- Codex projected pet state changes once.
- Agent row stays visible beyond generic event TTL.
- No Claude Code or OpenCode session is created.
- No approval or tmux control is attempted.

### Hook Verification

After installer cutover:

```bash
Tools/install-codex-hooks.sh
```

Then start a new Codex CLI session and verify:

- `SessionStart` creates a Codex agent session.
- `UserPromptSubmit` marks it running.
- `PermissionRequest` marks it waiting/approval-required.
- `Stop` marks it completed.
- Repeated events update the same session.
- Closing the pet app does not break Codex hook execution.

### Regression Verification

Existing behavior that must continue:

- `swift run petctl notify`
- `swift run petctl state`
- `swift run petctl flash`
- `swift run petctl clear`
- `Tools/verify-event-runtime.sh`
- Existing action allowlist behavior.
- Existing flash layer separation.
- Existing generic source mute/pause behavior, unless explicitly refactored into
  a new generic event store.

## Final Acceptance Criteria

The refactor is complete for this slice when all of these are true:

- Codex CLI hook events are ingested through the new agent hook bridge/socket
  path.
- Codex sessions are stored in `AgentRegistry` by `AgentSession.id`.
- Generic `LocalPetEvent.source` is not used as canonical agent identity.
- `EventRouter` does not store `AgentSession`.
- `LocalPetEvent` has no agent-only fields.
- Codex rows are available through `AgentThreadSnapshot`.
- Generic events still work independently.
- Claude Code and OpenCode have empty provider shells only.
- App-server, process, terminal plugin, workspace, and rollout paths are
  placeholders or unsupported.
- Tmux control and tmux scanning are not part of this plan.
- Kitty terminal plugin control is not implemented in this plan.
- Raw TUI sessions are explicitly unsupported.
- Approve, deny, and follow-up controls are not implemented.
- Tests cover registry, Codex provider mapping, hook envelope, event projection,
  and thread projection.
- Documentation states how to install, verify, disable, and remove the Codex hook
  path.

## Rejected Shortcuts

- Adding `agentSessionId`, `agentKind`, `transport`, `pid`, `tty`,
  `tmuxPaneId`, or kitty ids to `LocalPetEvent`.
- Reusing `LocalEventServer` as the hook socket or agent control server.
- Continuing to route Codex hook payloads directly to `EventRouter`.
- Letting `EventRouter` own agent expiry or merge policy.
- Treating `dedupeKey` as a durable agent session id.
- Creating Claude/OpenCode behavior before Codex is clean.
- Implementing approval by terminal text injection.
- Starting Codex app-server before the app-server transport contract exists.
- Building process or terminal scanning before hook-backed identity is solid.
- Adding tmux control or tmux scanning to the Codex session-listening slice.
- Implementing `KittyTerminalTransport.sendMessage` in the Codex
  session-listening slice.
- Supporting arbitrary raw TUI sessions, including sessions that happen to run
  inside tmux.

## Open Questions

- Should completed Codex sessions expire by time, max count, or explicit user
  archive?
- Should subagent sessions always collapse into the parent thread row, or should
  the panel support expandable subagent children later?
- Should the hook bridge live only as a Swift executable, or should the existing
  Python hook remain as a compatibility launcher for installed source checkouts?
- Should agent hook socket logs share `runtime.jsonl`, or use a dedicated
  `agent-hooks.jsonl` file?
- What is the minimum UI change that cleanly introduces `ThreadPanelSnapshot`
  without preserving the old router-only panel model too long?
