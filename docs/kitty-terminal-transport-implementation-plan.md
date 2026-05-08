# Kitty Terminal Transport Implementation Plan

## Purpose

This document is the implementation plan for trusted terminal plugin support,
using kitty as the first concrete terminal integration.

The goal is to add:

- A clean terminal transport abstraction.
- `KittyTerminalTransport` as the first implementation.
- A kitty plugin/kitten integration path for structured terminal events.
- Command completion flash events.
- Provider-approved message injection for known coding-agent sessions.

This is not raw terminal support. It is not tmux replacement code. It is not a
screen parser.

## Plan Check

No blocking product or architecture questions remain for writing this plan.

Implementation should proceed with these assumptions:

- `TerminalTransport` is a Swift protocol, not an inheritance-heavy base class.
- If shared validation or logging becomes useful, add `BaseTerminalTransport`
  later as a small helper class. Do not force all transports through inheritance.
- `KittyTerminalTransport` is the first implementation of `TerminalTransport`.
- The kitty side should provide structured events through a plugin/kitten path,
  not through terminal screen scraping.
- Existing zsh-based kitty command flash remains a compatibility path until the
  plugin path is real.

Questions to verify before coding, but not blockers for this plan:

- Which kitty extension surface is best for the first plugin: a kitten, a shell
  integration wrapper, or a remote-control companion process?
- Whether kitty remote-control should be addressed through `KITTY_LISTEN_ON`,
  a configured socket path, or a plugin-owned local socket.
- Whether the first command flash event should include only metadata or a short
  output summary.

## Architectural Boundary

Keep three separate responsibilities:

```text
Terminal plugin
  -> structured terminal events
  -> command flash projection
  -> EventRouter

Terminal plugin
  -> structured terminal events
  -> AgentProvider
  -> AgentRegistry

AgentControl
  -> TerminalTransport
  -> KittyTerminalTransport
  -> kitty control endpoint
```

Rules:

- Terminal plugins provide terminal facts and control surfaces.
- Providers identify Codex, Claude Code, OpenCode, or future agents.
- `KittyTerminalTransport` never decides agent identity.
- Command flash events never create `AgentSession` entries by themselves.
- Permission approval and denial never use terminal text injection.

## Proposed Files

```text
Sources/GlobalPetAssistant/AgentDiscovery/
  TerminalSessionContext.swift
  TerminalPluginEvent.swift
  TerminalPluginEventReceiver.swift
  TerminalCommandFlashProjection.swift

Sources/GlobalPetAssistant/AgentDiscovery/transports/
  TerminalTransport.swift
  KittyTerminalTransport.swift
  KittyCommandRunner.swift
  KittyTargetResolver.swift
  TerminalTransportError.swift

Sources/GlobalPetAssistant/AgentDiscovery/sources/
  TerminalPluginSource.swift

examples/kitty-plugin/
  README.md
  global_pet_assistant.py
  install.sh

Tests/GlobalPetAssistantTests/
  TerminalPluginEventTests.swift
  TerminalCommandFlashProjectionTests.swift
  KittyTerminalTransportTests.swift
  KittyTargetResolverTests.swift
```

Avoid adding terminal-specific fields to `LocalPetEvent`. Avoid adding
kitty-specific fields directly to `AgentSession`; keep them inside
`TerminalSessionContext`.

## Core Types

### TerminalSessionContext

`TerminalSessionContext` is the normalized terminal identity.

```swift
enum TerminalIntegrationKind: String, Codable, Equatable, Sendable {
    case kitty
}

struct TerminalSessionContext: Codable, Equatable, Sendable {
    var kind: TerminalIntegrationKind
    var sessionId: String
    var windowId: String?
    var tabId: String?
    var cwd: String?
    var command: String?
    var controlEndpoint: String?
}
```

Notes:

- `sessionId` is the app's normalized terminal session key.
- `windowId` and `tabId` are terminal-specific hints, not global identity.
- `controlEndpoint` must stay local and should be redacted from user-facing UI.

### TerminalPluginEvent

`TerminalPluginEvent` is the structured event from a terminal plugin.

```swift
enum TerminalPluginEventKind: String, Codable, Equatable, Sendable {
    case commandStarted = "command-started"
    case commandCompleted = "command-completed"
    case agentObserved = "agent-observed"
}

struct TerminalPluginEvent: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var kind: TerminalPluginEventKind
    var terminal: TerminalSessionContext
    var command: String?
    var exitCode: Int?
    var durationMs: Int?
    var outputSummary: String?
    var providerHint: AgentKind?
    var occurredAt: Date
}
```

The first schema version should be `1`. Unknown future versions should be
rejected or explicitly downgraded, never silently accepted.

### TerminalTransport

`TerminalTransport` is the Swift abstraction for structured terminal control.

```swift
protocol TerminalTransport {
    var integrationKind: TerminalIntegrationKind { get }

    func observe(_ context: TerminalSessionContext) async throws -> TerminalObservation
    func sendMessage(_ text: String, to context: TerminalSessionContext) async throws
}
```

`TerminalTransport` should stay small. Approval, denial, history reads, and
agent-specific commands do not belong in this abstraction.

### KittyTerminalTransport

`KittyTerminalTransport` implements `TerminalTransport` for kitty.

Responsibilities:

- Validate the target terminal context.
- Check that the kitty target is still reachable.
- Send follow-up text only to a known provider-approved session.
- Use argument arrays or structured IPC; never build shell command strings.
- Return typed errors for stale target, missing endpoint, unsupported action,
  invalid message, and command failure.

Non-responsibilities:

- Identifying Codex or Claude Code.
- Reading full terminal history.
- Scraping screen contents.
- Approving or denying permissions.
- Falling back to tmux or raw terminal typing.

## Kitty Plugin Plan

The kitty plugin should become the structured terminal-side source of truth.

### Plugin Responsibilities

- Emit command lifecycle events:
  - `command-started`
  - `command-completed`
- Include terminal context:
  - kitty window id
  - tab id if available
  - cwd
  - command
  - local control endpoint
- Optionally include a short output summary.
- Accept provider-scoped message injection requests from the app.
- Avoid exposing broad shell execution.

### Plugin Non-Responsibilities

- It should not classify agents beyond optional hints.
- It should not store long terminal history.
- It should not send every keystroke to the app.
- It should not approve or deny coding-agent permissions.
- It should not require tmux.

### Plugin Event Delivery

Preferred delivery:

```text
kitty plugin
  -> local Unix socket or localhost endpoint
  -> TerminalPluginEventReceiver
```

Fallback during migration:

```text
existing zsh hook
  -> petctl flash
  -> EventRouter
```

The fallback is only for command flash compatibility. It must not grow into the
agent session or control path.

### Message Injection

Message injection should be provider-approved and terminal-scoped:

```text
AgentControl.sendMessage
  -> session capability check
  -> provider status check
  -> KittyTerminalTransport.sendMessage
  -> kitty plugin control endpoint
  -> target terminal input
```

Rules:

- Reject empty or oversized messages.
- Normalize newline behavior so one intentional submit happens.
- Do not send messages to sessions without `send-message`.
- Do not send messages when the terminal target is stale.
- Do not log full message text by default.

## Implementation Phases

### Phase 0: Documentation And Guardrails

Tasks:

- Add this implementation plan.
- Link it from `terminal-plugin-transport-architecture.md`.
- Keep tmux explicitly out of scope.
- Mark the existing zsh command flash hook as compatibility, not the target
  architecture.

Acceptance criteria:

- No runtime code changes are required.
- The plan states that kitty is a terminal transport, not an agent provider.
- The plan states that command flash and agent sessions remain separate.

### Phase 1: Shared Terminal Models

Tasks:

- Add `TerminalSessionContext`.
- Add `TerminalObservation`.
- Add `TerminalPluginEvent`.
- Add `TerminalPluginEventKind`.
- Add `TerminalTransportError`.
- Add tests for event decoding and schema validation.

Acceptance criteria:

- Unknown schema versions are rejected.
- Missing terminal session id is rejected.
- Unknown terminal integration kind is rejected.
- No model change is required in `LocalPetEvent`.

### Phase 2: TerminalPluginEventReceiver

Tasks:

- Add a local receiver for terminal plugin events.
- Use local authentication compatible with existing app token rules, or a
  dedicated terminal-plugin token stored under `~/.global-pet-assistant`.
- Validate body size.
- Validate schema version.
- Rate limit command events.
- Route command lifecycle events to `TerminalCommandFlashProjection`.
- Route agent-observed events through `AgentDiscoveryService`.

Acceptance criteria:

- Invalid token is rejected.
- Oversized payload is rejected.
- Malformed event is rejected.
- Command events can produce flash events.
- Command events do not mutate `AgentRegistry`.

### Phase 3: Command Flash Projection

Tasks:

- Implement `TerminalCommandFlashProjection`.
- Map successful long-running commands to success flash.
- Map failed commands to danger flash.
- Preserve the existing high-noise command ignore list from the zsh hook.
- Keep flash TTL short.

Acceptance criteria:

- `command-completed` with `exitCode == 0` can create a success flash.
- `command-completed` with non-zero exit code can create a danger flash.
- Ignored commands such as `cd`, `ls`, `pwd`, and `git status` do not flash.
- No command flash creates an agent thread row.

### Phase 4: TerminalTransport Base Contract

Tasks:

- Add `TerminalTransport` protocol.
- Add `TerminalTransportError`.
- Add optional `BaseTerminalTransport` only if shared validation would remove
  real duplication.
- Add `AgentControlTransportKind.terminalPlugin`.
- Add capability mapping from terminal plugin availability to
  `observe` / `send-message`.

Acceptance criteria:

- `TerminalTransport` has only `observe` and `sendMessage`.
- There are no approval or denial methods.
- Missing capability prevents send.
- Unit tests cover unsupported and stale-target errors.

### Phase 5: KittyTerminalTransport Observe

Tasks:

- Add `KittyCommandRunner` with explicit executable path resolution.
- Reuse the existing `kitten` candidate paths only through a dedicated runner.
- Add `KittyTargetResolver`.
- Validate `TerminalSessionContext.kind == .kitty`.
- Validate local control endpoint format.
- Observe whether the target session is reachable.

Acceptance criteria:

- Missing `kitten` or plugin endpoint returns a typed unavailable error.
- Invalid kitty target is rejected.
- A reachable kitty context returns `TerminalObservation`.
- No shell command string construction exists.

### Phase 6: KittyTerminalTransport Send Message

Tasks:

- Implement `sendMessage`.
- Gate by `AgentRegistry` session existence.
- Gate by `send-message` capability.
- Gate by provider-approved session kind and status.
- Gate by user/config allowlisting.
- Send through kitty plugin control endpoint or structured remote-control path.
- Normalize text submission.

Acceptance criteria:

- Known provider-approved session can receive a message.
- Unknown terminal session cannot receive a message.
- Session without `send-message` cannot receive a message.
- Approval and denial remain unsupported.
- Failed send does not mutate agent status to completed or failed.

### Phase 7: Kitty Plugin Prototype

Tasks:

- Add `examples/kitty-plugin/README.md`.
- Add a minimal plugin/kitten prototype.
- Emit `command-started` and `command-completed` events.
- Include kitty window id and cwd.
- Include a local control endpoint if available.
- Add an installer script that is separate from the legacy zsh hook installer.

Acceptance criteria:

- Plugin can be installed without modifying unrelated shell config.
- Plugin can emit a command completion event to the app.
- Plugin can be disabled cleanly.
- Plugin does not require tmux.

### Phase 8: Provider Integration

Tasks:

- Let `CodexProvider` consume terminal plugin events as supporting evidence.
- Add `ClaudeCodeProvider` support only after Codex behavior is clean.
- Use provider recognition before adding terminal `send-message` capability.
- Preserve hook-backed identity as stronger than terminal plugin evidence.

Acceptance criteria:

- Kitty terminal event alone cannot create a high-confidence Codex session unless
  `CodexProvider` recognizes provider-specific evidence.
- Hook-backed Codex identity is not overwritten by terminal plugin metadata.
- Terminal context can enrich a known agent session.

### Phase 9: Migration From Existing Kitty Flash Hook

Tasks:

- Keep `Tools/install-kitty-command-hook.sh` working during migration.
- Document the plugin path as the preferred future path.
- Avoid adding agent behavior to `examples/hooks/kitty-command-flash.zsh`.
- Add a deprecation or compatibility note only after the plugin installer works.

Acceptance criteria:

- Existing command flash users do not lose behavior.
- New plugin path can be tested independently.
- The zsh hook remains generic flash-only.

## Verification Plan

Unit tests:

- `TerminalPluginEvent` decoding rejects bad schema.
- `TerminalCommandFlashProjection` maps success and failure correctly.
- Ignored command list suppresses noisy events.
- `KittyTargetResolver` rejects missing session id or invalid endpoint.
- `KittyTerminalTransport` rejects non-kitty contexts.
- `KittyTerminalTransport.sendMessage` rejects empty and oversized messages.
- Approval and denial remain unsupported through terminal plugin transport.

Integration tests:

- Terminal plugin receiver accepts a valid local event.
- Command completion event creates one flash message.
- Command flash does not create `AgentSession`.
- Known agent session can gain `send-message` only with valid terminal context.

Manual tests:

```bash
swift test
swift run petctl flash --source terminal --level success --message "terminal flash smoke"
```

After the plugin prototype exists:

```bash
examples/kitty-plugin/install.sh
```

Then verify:

- A successful long command flashes.
- A failed command flashes.
- A known Codex terminal session can receive a follow-up message only when the
  UI/session exposes `send-message`.
- Permission approval controls remain absent.

## Rejected Shortcuts

- Reintroducing tmux as a fallback.
- Treating kitty as an agent provider.
- Inferring agent identity from terminal screen text.
- Adding kitty ids to `LocalPetEvent`.
- Adding raw command output history to `AgentRegistry`.
- Sending approval or denial by typing text into kitty.
- Using shell string interpolation to run kitty control commands.
- Making the legacy zsh hook the long-term control architecture.
