# Terminal Plugin Transport Architecture

## Purpose

Terminal support means support for terminals with a trusted plugin or extension
protocol. It does not mean raw TUI support, process scraping, screen scraping, or
best-effort keyboard injection.

The first concrete integration should be `KittyTerminalTransport`.

For the implementation plan, see
[Kitty Terminal Transport Implementation Plan](kitty-terminal-transport-implementation-plan.md).

## Product Boundary

Global Pet Assistant remains a general local event runtime. Terminal plugins add
two clean capabilities:

- Send short command lifecycle results to the existing flash layer.
- Provide a structured control route for known coding-agent sessions.

Coding agents are still identified by providers such as `CodexProvider` and
`ClaudeCodeProvider`. Kitty identifies the terminal surface, not the agent.

## Architecture

```text
Kitty watcher / plugin
  -> TerminalPluginEventReceiver
  -> TerminalCommandFlashProjection
  -> LocalPetEvent
  -> EventRouter
  -> pet flash

Kitty watcher / plugin
  -> TerminalPluginEventReceiver
  -> AgentDiscoveryService
  -> AgentProvider
  -> AgentRegistry
  -> AgentThreadProjection
  -> long-lived agent thread panel

ThreadPanel / notification action
  -> AgentCapabilityRouteKind.terminalPlugin
  -> TerminalTransport.focus
  -> KittyTerminalTransport
  -> Kitty plugin / remote-control endpoint
```

The two input paths must stay separate. A command flash is a generic event. A
coding-agent session update is an agent event only after a provider recognizes
it.

## Core Types

```swift
enum TerminalIntegrationKind: String, Codable, Equatable {
    case kitty
}

struct TerminalSessionContext: Codable, Equatable {
    var kind: TerminalIntegrationKind
    var sessionId: String
    var windowId: String?
    var tabId: String?
    var cwd: String?
    var command: String?
}

struct TerminalObservation: Codable, Equatable {
    var terminal: TerminalSessionContext
    var isReachable: Bool
    var cwd: String?
    var command: String?
    var observedAt: Date
}

enum TerminalPluginEventKind: String, Codable, Equatable {
    case commandStarted = "command-started"
    case commandCompleted = "command-completed"
    case agentObserved = "agent-observed"
}

struct TerminalPluginEvent: Codable, Equatable {
    var kind: TerminalPluginEventKind
    var terminal: TerminalSessionContext
    var command: String?
    var exitCode: Int?
    var outputSummary: String?
    var providerHint: AgentKind?
    var occurredAt: Date
}
```

`TerminalSessionContext` is the only place for terminal-specific identity. Do
not add kitty window ids, tab ids, or control socket details directly to
`AgentSession` or `LocalPetEvent`.

## TerminalTransport

`TerminalTransport` is the terminal observation and focus abstraction:

```swift
protocol TerminalTransport {
    var integrationKind: TerminalIntegrationKind { get }

    func observe(_ context: TerminalSessionContext) async throws -> TerminalObservation
    func focus(_ context: TerminalSessionContext) async throws
}
```

It is used as terminal integration metadata for notification and focus.
Agent-facing capabilities are derived from the combination of:

- Provider-approved session identity.
- Terminal plugin availability.
- Transport support.
- Trusted terminal focus metadata.

## KittyTerminalTransport

`KittyTerminalTransport` is the first `TerminalTransport` implementation.

Responsibilities:

- Validate that a target kitty session still exists.
- Observe structured kitty session metadata.
- Focus a known kitty window when trusted target metadata is present.
- Return explicit unsupported errors for reverse input and permission control.
- Log focus attempts without logging terminal content.

Non-responsibilities:

- It does not identify Codex, Claude Code, or OpenCode.
- It does not parse full terminal history.
- It does not scan arbitrary terminals.
- It does not approve or deny permissions by typing `y`, `n`, or similar text.
- It does not create `AgentSession` entries by itself.

## Command Flash

Kitty command lifecycle events should project to the existing flash layer:

```text
command-completed + exitCode == 0
  -> LocalPetEvent(type: "terminal.command.completed", level: success)

command-completed + exitCode != 0
  -> LocalPetEvent(type: "terminal.command.failed", level: danger)
```

Flash payload rules:

- Keep text short.
- Prefer command name, cwd basename, exit code, and a short summary.
- Do not store terminal history.
- Do not enter `AgentRegistry` unless a provider recognizes the event as a
  coding-agent session update.

## Capability Policy

Terminal plugin transport may expose:

```text
observe
focus
```

Terminal plugin transport must not expose:

```text
read-history
send-message
approve-permission
deny-permission
```

Permission approval is a structured security decision. It belongs to a provider
or app-server protocol with first-class approval semantics, not to terminal text
injection.

## Security Rules

- Require local authentication for terminal plugin event writes.
- Require a schema version on terminal plugin events.
- Rate limit command flash events.
- Gate terminal focus behind trusted target metadata.
- Never fall back to raw terminal typing when kitty control fails.
- Log target metadata and result status; do not log terminal content.

## Implementation Order

1. Add type placeholders: `TerminalSessionContext`, `TerminalPluginEvent`,
   `TerminalTransport`, and `KittyTerminalTransport`.
2. Add `TerminalPluginEventReceiver` with schema validation and local auth.
3. Add command flash projection for kitty command completion events.
4. Let providers consume terminal plugin events as optional session evidence.
5. Add `KittyTerminalTransport.observe`.
6. Add `KittyTerminalTransport.focus` for trusted kitty targets.

## Acceptance Criteria

- A kitty command completion can produce a flash without touching
  `AgentRegistry`.
- A kitty event cannot create a coding-agent session unless an `AgentProvider`
  recognizes it.
- A known Codex or Claude Code session can advertise `focus` through
  terminal plugin metadata only when a valid
  `TerminalSessionContext` exists.
- No approval or denial control is exposed through kitty.
- No raw terminal scanning or tmux fallback exists.

## Rejected Designs

- Treating kitty as `CodexProvider`.
- Adding kitty-specific ids to `LocalPetEvent`.
- Adding kitty-specific ids directly to `AgentSession` outside
  `TerminalSessionContext`.
- Inferring agents from terminal screen text.
- Using terminal injection for approval or denial.
- Reintroducing tmux as a fallback transport.
