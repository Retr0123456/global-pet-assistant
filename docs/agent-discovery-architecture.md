# Agent Discovery Architecture

## Positioning

Global Pet Assistant is still a general local event runtime with a pet renderer.
Any local tool, script, app, CI bridge, or workflow can send events and get a
visible response from the desktop pet.

Coding agents are a first-class integration, not the product boundary. They get
a durable session model, richer discovery, and stronger controls because they
have long-running state and permission workflows. They must not force generic
events to become coding-agent-shaped.

## Architectural Rule

Keep two independent state pipelines:

```text
Generic local events
  -> LocalPetEvent
  -> EventRouter
  -> pet animation, flash layer, generic active event snapshots

Coding agent sessions
  -> AgentSource
  -> AgentProvider
  -> AgentControlTransport
  -> AgentRegistry
  -> AgentThreadSnapshot
  -> long-lived agent thread panel
```

Agents can project their state into the generic event pipeline when the pet needs
to react, but the generic event pipeline must not store or understand full agent
session metadata.

```text
AgentRegistry
  -> AgentEventProjection
  -> LocalPetEvent
  -> EventRouter
```

## Non-Negotiable Boundaries

- `LocalPetEvent.source` is an event source label, not the canonical coding
  agent session identity.
- `AgentSession.id` is the canonical identity for a coding agent session.
- `EventRouter` owns pet animation priority, TTL, generic active events, and
  flash messages.
- `AgentRegistry` owns agent session identity, merge, capabilities, last-seen
  tracking, and agent-specific expiry.
- Agent control is never implemented as a generic `LocalPetAction`.
- The pet event server accepts general events; it is not an agent control API.
- A provider identifies what the agent is. A control transport identifies how
  the app can observe or control it. A source identifies where a candidate came
  from.

## Core Types

These types should live under a dedicated agent module, for example
`Sources/GlobalPetAssistant/AgentDiscovery/`.

```swift
enum AgentKind: String, Codable, Equatable {
    case codex
    case claudeCode = "claude-code"
    case opencode
}

enum AgentControlTransportKind: String, Codable, Equatable {
    case agentAppServer = "agent-app-server"
    case tmux
}

enum AgentStatus: String, Codable, Equatable {
    case started
    case running
    case waiting
    case completed
    case failed
    case unknown
}

enum AgentCapability: String, Codable, Equatable {
    case observe
    case readHistory = "read-history"
    case sendMessage = "send-message"
    case approvePermission = "approve-permission"
    case denyPermission = "deny-permission"
}

struct AgentSession: Codable, Equatable, Identifiable {
    var id: String
    var kind: AgentKind
    var controlRoutes: [AgentControlTransportKind: Set<AgentCapability>]
    var status: AgentStatus
    var capabilities: Set<AgentCapability>
    var createdAt: Date
    var lastSeenAt: Date

    var pid: Int?
    var cwd: String?
    var tty: String?
    var tmuxPaneId: String?

    var title: String?
    var message: String?
    var pendingPermissionDescription: String?
}
```

`capabilities` is the union of all values in `controlRoutes`; it is kept as a
convenience projection for UI and guard checks, not as a separate source of
truth.

The agent model can grow without changing the generic event contract. Only
fields needed by non-agent integrations should be added to `LocalPetEvent`.

## Module Layout

```text
AgentDiscovery/
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

  providers/
    CodexProvider.swift
    ClaudeCodeProvider.swift
    OpenCodeProvider.swift

  transports/
    AgentAppServerTransport.swift
    TmuxControlTransport.swift

  sources/
    HookEventReceiver.swift
    WorkspaceScanner.swift
    ProcessScanner.swift
    TerminalScanner.swift
    TmuxScanner.swift
    AppServerScanner.swift

  hooks/
    HookInstaller.swift
    CodexHookProfile.swift
```

Hook bridge code is a separate short-lived executable, not app runtime code:

```text
Sources/globalPetAgentBridge/main.swift
```

`hooks/` is for installer/profile logic. Hook events should feed the same
source/provider/registry path as scanner discoveries.

## Responsibilities

### AgentDiscoveryService

Orchestrates sources, providers, transports, and registry updates. It should not
contain provider-specific matching rules.

Responsibilities:

- Run discovery sources on a schedule or from push events.
- Ask providers to classify candidates.
- Ask transports to describe available capabilities.
- Upsert resulting sessions into `AgentRegistry`.
- Emit registry snapshots to UI and projection layers.

### AgentRegistry

The single source of truth for coding agent sessions.

Responsibilities:

- Upsert sessions by `AgentSession.id`.
- Merge partial discoveries from multiple sources.
- Merge weak enrichment signals into identities established by authoritative
  sources such as hooks or future app-server snapshots.
- Track `createdAt` and `lastSeenAt`.
- Expire stale sessions by agent-specific policy.
- Expose snapshots sorted for the agent thread panel.

Registry merge must be conservative. A weak signal can refresh `lastSeenAt`, but
it must not overwrite stronger fields such as transport, capabilities, or a known
pending approval state unless the provider says the update is authoritative.

### AgentProvider

Identifies what an agent is and normalizes provider-specific data.

Examples:

- `CodexProvider` recognizes Codex hook payloads, session ids, transcript paths,
  process commands, and app-server health output.
- `ClaudeCodeProvider` recognizes Claude Code hook payloads, process commands,
  and workspace markers.
- `OpenCodeProvider` recognizes OpenCode process commands and workspace markers.

Provider output should be an agent candidate with normalized identity and
provider confidence. Providers do not perform control operations.

### AgentControlTransport

Describes how a known session can be observed or controlled.

Potential capability policy:

| Transport | Capabilities |
| --- | --- |
| `agent-app-server` | Contract-dependent: may expose `observe`, `read-history`, `send-message`, `approve-permission`, `deny-permission` after a concrete protocol exists. |
| `tmux` | `observe`, `send-message` |

Current implementation policy:

| Transport | First exposed behavior |
| --- | --- |
| `agent-app-server` | Placeholder only until the protocol exists. |
| `tmux` | Planned separately for known sessions only; see the tmux transport plan. |

Transports are capability providers, not identity providers. They may contribute
metadata such as `pid`, `tty`, or `tmuxPaneId`, but they should not decide
whether a session is Codex, Claude Code, or OpenCode.

### AgentControl

The future command interface for agent sessions. This contract is deferred until
the relevant control transport slice is implemented; Codex hook-backed session
listening exposes capability flags only and does not implement these methods.

Future operations:

```swift
protocol AgentControl {
    func sendMessage(_ text: String, to session: AgentSession) async throws
    func approvePermission(for session: AgentSession) async throws
    func denyPermission(for session: AgentSession) async throws
}
```

Every control method must check:

- The session exists in `AgentRegistry`.
- The requested capability is present.
- The transport supports the operation.
- The provider allows the operation for the current status.
- The user or config has explicitly enabled that class of control.

Approval and denial must start as app-server-only capabilities. Tmux text
injection is not approval semantics unless a provider implements a safe,
provider-specific protocol for it.

### Sources

Sources discover candidates. They do not own final identity.

Recommended long-term implementation order:

| Source | First phase behavior |
| --- | --- |
| `HookEventReceiver` | Real implementation for Codex hook events first. Claude Code and OpenCode remain provider shells until separately implemented. |
| `WorkspaceScanner` | Placeholder in the first slice. Later reads known session files, logs, or config markers under cwd. |
| `TmuxScanner` | Placeholder in the first slice. Later validates or enriches known sessions; it must not create high-confidence sessions by itself. |
| `AppServerScanner` | Placeholder until agent-side app-server protocol is defined. |
| `ProcessScanner` | Placeholder or diagnostic-only because cwd/tty access can be permission-sensitive on macOS. |
| `TerminalScanner` | Placeholder or diagnostic-only because terminal window introspection is app-specific. |

Best-effort scanners must never be required for correctness. Hook and app-server
signals should be treated as stronger than process or terminal inference.

## UI Projection

The long-lived agent thread panel should read `AgentThreadSnapshot`, not
`LocalPetEvent` directly.

```swift
struct AgentThreadSnapshot: Equatable, Identifiable {
    var id: String
    var kind: AgentKind
    var controlRoutes: [AgentControlTransportKind: Set<AgentCapability>]
    var status: PetThreadStatus
    var title: String
    var context: String
    var directoryName: String
    var messagePreview: String
    var capabilities: Set<AgentCapability>
    var lastSeenAt: Date
}
```

Status mapping is a projection concern:

| Agent state | Thread status |
| --- | --- |
| `started`, `running` | `running` |
| `waiting` with pending permission | `approval-required` |
| `waiting` | `waiting` |
| `completed` | `success` |
| `failed` | `failed` |
| `unknown` | `info` |

The existing `PetThreadStatus` can remain a UI vocabulary. It should not become
the storage model for agent lifecycle.

## Event Projection

Agent sessions should project only the minimum event needed for the pet to react.

Examples:

```text
AgentStatus.running
  -> LocalPetEvent(source: "agent:codex", state: running)

AgentStatus.waiting with pending permission
  -> LocalPetEvent(source: "agent:codex", level: warning, type: "agent.permission.request")

AgentStatus.completed
  -> LocalPetEvent(source: "agent:codex", level: success)

AgentStatus.failed
  -> LocalPetEvent(source: "agent:codex", level: danger)
```

This projection is one-way. Generic events do not create full `AgentSession`
objects unless an agent provider recognizes them.

## Security Model

Generic events and agent controls have different security levels.

Generic local events:

- Keep the existing local token, body limit, rate limit, and action allowlist.
- Accept unknown sources for state notifications.
- Reject unknown-source actions as today.

Agent controls:

- Require an agent session in `AgentRegistry`.
- Require explicit capability support.
- Require an enabled provider and transport.
- Require user approval or config allowlisting for mutating controls.
- Keep `approve-permission` and `deny-permission` disabled unless the transport
  exposes first-class safe semantics.

Do not implement agent approval as arbitrary text injection into a terminal.

## Compatibility Strategy

Existing `petctl` behavior should continue to work.

Legacy Codex hook events that were previously mapped into `LocalPetEvent` should
continue reaching `EventRouter` only during migration. They must not create or
update `AgentRegistry` entries. New Codex session state must enter through the
agent hook bridge/socket path and then project back into `LocalPetEvent` when the
pet needs to react.

Compatibility rule:

```text
Legacy LocalPetEvent
  -> EventRouter as before during migration
  -> no AgentRegistry mutation
```

No generic event sender should be forced to provide `AgentKind`, transport,
capabilities, pid, tty, or tmux metadata.

## Phased Implementation

For the first implementation slice, see
[Codex Session Listening Refactor Plan](codex-session-listening-refactor-plan.md).

### Phase 1: Models And Registry

- Add agent model files and protocols.
- Implement `AgentRegistry` with upsert, merge, expiry, and snapshot tests.
- Add placeholder providers, transports, and scanners.
- Do not change `EventRouter` routing semantics.

### Phase 2: Hook-Backed Agent Sessions

- Route Codex hook events through `HookEventReceiver` and `CodexProvider`.
- Project `AgentRegistry` updates into `LocalPetEvent` for pet animation
  compatibility.
- Add `AgentThreadProjection` for long-lived agent thread snapshots.
- Keep approval and denial as disabled capabilities.

### Phase 3: UI Split

- Let the thread panel render generic active events and agent thread snapshots
  as distinct data sources.
- Keep flash messages separate from long-lived agent sessions.
- Keep dismiss semantics scoped: dismissing an agent thread hides or archives the
  session view, while clearing generic events still clears `EventRouter`.

### Phase 4: Transports

- Add `TmuxControlTransport` for observe and send-message only. See
  [Tmux Control Transport Plan](tmux-control-transport-plan.md).
- Add `AgentAppServerTransport` after a concrete agent-side app-server protocol
  exists.

### Phase 5: Mutating Controls

- Enable `send-message` for transports with explicit support.
- Enable `approve-permission` and `deny-permission` only for safe provider
  protocols.
- Add audit logs for every mutating control.

## Rejected Designs

- Do not turn `LocalPetEvent` into `AgentSession`.
- Do not make `source` the permanent agent session primary key.
- Do not let `EventRouter` own agent registry behavior.
- Do not overload `LocalEventServer` as an agent control server.
- Do not implement approval by blindly typing into tmux or raw terminals.
- Do not require process or terminal scanning for normal operation.
- Do not support arbitrary raw TUI agents, even when they happen to run inside
  tmux. Tmux support is only for known coding-agent sessions with
  provider-approved identity.
