# Tmux Control Transport Plan

## Purpose

This document plans `TmuxControlTransport` as a separate implementation slice.
It belongs after Codex hook-backed session identity is clean and before any
Codex app-server control work, if CLI follow-up messaging becomes the next
priority.

The goal is narrow:

```text
Known AgentSession + tmux pane evidence
  -> observe pane metadata
  -> send follow-up text to the correct pane
```

It is not an approval system. It is not raw terminal support. It is not a
replacement for hook-backed session listening.

## Product Boundary

Global Pet Assistant remains a general local event runtime. Tmux support is a
first-class control transport for coding-agent sessions that are already known
through reliable discovery, usually hooks.

Do not discover arbitrary raw terminal agents by scanning and guessing. Tmux pane
evidence is necessary for tmux control, but it is not sufficient for session
identity. A session must already be known through a hook, app-server snapshot, or
another provider-approved identity source before tmux can control it.

## Scope

In scope:

- `TmuxControlTransport` module.
- Read-only tmux pane validation.
- Pane-targeted follow-up message sending.
- Codex CLI sessions discovered by hook and enriched with `TMUX` / `TMUX_PANE`.
- Capability gating for `send-message`.
- Audit logs for every tmux send attempt.
- Unit tests around target resolution and command construction.

Out of scope:

- Permission approve or deny.
- Blind text injection without a known `AgentSession`.
- Raw TUI support.
- Terminal.app/iTerm/kitty direct control without tmux.
- Creating tmux sessions.
- Managing tmux lifecycle.
- App-server fallback.
- Claude Code or OpenCode behavior.

## Architecture Position

Tmux is a control transport, not a source of truth.

```text
Codex hook
  -> AgentHookEnvelope
  -> CodexProvider
  -> AgentRegistry
  -> AgentSession(id, kind: codex, tmuxPaneId, tty, cwd)
  -> TmuxControlTransport
  -> send-message
```

`TmuxScanner` may later validate panes or enrich known sessions, but it must not
create high-confidence sessions by itself in the first tmux slice.

## Capability Policy

Transport capabilities:

```text
observe
send-message
```

Explicitly not supported:

```text
approve-permission
deny-permission
read-history
```

Reasoning:

- `send-message` is normal user text entry.
- `approve-permission` and `deny-permission` are structured security decisions.
- Tmux cannot safely guarantee approval semantics unless a provider-specific
  protocol is implemented later.

## Session Requirements

A session is eligible for tmux send only when all are true:

- It exists in `AgentRegistry`.
- `session.kind == .codex` for the first implementation.
- `session.capabilities` contains `send-message`.
- `session.tmuxPaneId` is present.
- The pane still exists at send time.
- The pane command still looks compatible with the expected provider.
- The user has enabled tmux sends in app configuration or via an explicit UI
  action.

If any check fails, return an unsupported or stale-target error. Do not fall back
to raw terminal typing.

## Target Resolution

Preferred target:

```text
TMUX_PANE from hook environment
```

Validation aids, in order:

```text
tty -> tmux pane lookup
cwd + provider command match -> tmux pane lookup
```

These aids are not identity sources and do not select a target by themselves in
the first tmux slice. They can confirm that the stored pane still matches the
known session. They should never override `session.tmuxPaneId` unless a later
provider-specific reattachment protocol is designed.

## Send Semantics

The transport should send user text through explicit tmux argument arrays, not
shell strings. Use literal mode for single-line text and paste-buffer semantics
for multiline text:

```text
tmux send-keys -t <pane> -l <single-line text>
tmux send-keys -t <pane> Enter
```

For multiline text, use a temporary tmux buffer or stdin-backed buffer strategy,
then `paste-buffer` into the target pane followed by one explicit `Enter`.

Rules:

- Preserve multiline text intentionally.
- Normalize trailing newline so one submit happens.
- Reject empty or whitespace-only messages.
- Apply a max message size.
- Do not send passwords or secret-looking content without an explicit higher
  level prompt, if secret detection is added later.
- Log command metadata, not full message text, unless debug logging is explicitly
  enabled.

## Observation Semantics

`observe` means:

- Check that tmux is installed.
- Check that a pane exists.
- Read pane metadata such as pane id, tty, current command, and current path if
  tmux exposes it.
- Optionally capture a small pane preview only for diagnostics and only if the
  user enables it.

Observation does not mean:

- Parsing full terminal history.
- Inferring complete agent state from screen text.
- Reading secrets from the pane.

## Proposed Files

```text
Sources/GlobalPetAssistant/AgentDiscovery/transports/
  TmuxControlTransport.swift
  TmuxCommandRunner.swift
  TmuxTargetResolver.swift
  TmuxSendMessageRequest.swift

Tests/GlobalPetAssistantTests/
  TmuxControlTransportTests.swift
  TmuxTargetResolverTests.swift
```

## Integration Points

`AgentRegistry`:

- Stores `tmuxPaneId`.
- Stores optional `tty`.
- Stores a tmux control route for `send-message` when tmux is available. It must
  not overwrite richer app-server routes when those exist later.

`CodexProvider`:

- Extracts `TMUX` and `TMUX_PANE` from hook environment.
- Adds `send-message` only when tmux pane evidence is present and tmux control is
  enabled.

`AgentControl`:

- Routes `sendMessage` to `TmuxControlTransport` when the session has a tmux
  control route for `send-message`.

UI:

- Shows a follow-up composer only when `send-message` is present.
- Shows no approve/deny controls for tmux-only sessions.

## Phased Implementation

### Phase 1: Placeholder

- Add `TmuxControlTransport` shell.
- Return explicit unsupported errors.
- Add doc link from Codex session listening plan.

Acceptance criteria:

- Placeholder compiles.
- No code sends text to tmux.
- Codex session listening remains hook-only.

### Phase 2: Target Validation

- Add `TmuxCommandRunner`.
- Add target existence check.
- Add pane metadata read.
- Add tests with a fake command runner.

Acceptance criteria:

- Valid pane target returns observed metadata.
- Missing pane returns stale target.
- No shell string command construction exists.

### Phase 3: Send Message

- Implement `sendMessage`.
- Gate by capability and user setting.
- Reject empty and oversized messages.
- Log send attempts and failures.

Acceptance criteria:

- A known Codex session with valid tmux pane can receive a follow-up message.
- A known Codex session without tmux pane cannot receive a follow-up message.
- Approval and denial still return unsupported.
- No raw terminal fallback exists.

### Phase 4: UI Composer

- Enable composer only for `send-message`.
- Disable composer when target is stale.
- Surface send failures without changing agent session identity.

Acceptance criteria:

- UI cannot send to sessions without `send-message`.
- UI cannot approve or deny through tmux.
- Failed send does not mutate the session into a fake completed/failed state.

## Verification

Unit tests:

- Target resolver prefers hook `TMUX_PANE`.
- Target resolver rejects missing pane.
- Command runner receives argument arrays, not shell strings.
- Send rejects empty text.
- Send rejects sessions without capability.
- Send rejects stale panes.
- Approval and denial remain unsupported.

Manual test:

```bash
tmux new -s global-pet-test
codex
```

Then verify:

- Codex hook creates a session with tmux pane metadata.
- Follow-up composer appears only for that session.
- Sending a message types into the correct pane.
- Closing the pane marks the target stale on the next send.

## Rejected Shortcuts

- Treating raw TUI as tmux.
- Inferring a target only from cwd and process name.
- Sending approval or denial by typing `y`, `n`, or similar into a pane.
- Building tmux commands through shell strings.
- Adding tmux fields to `LocalPetEvent`.
- Creating sessions from tmux scan alone.
