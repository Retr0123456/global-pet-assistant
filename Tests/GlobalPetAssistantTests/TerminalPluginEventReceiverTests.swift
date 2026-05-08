import Foundation
import Testing
@testable import GlobalPetAssistant

struct TerminalPluginEventReceiverTests {
    @Test
    func invalidTokenIsRejected() {
        let receiver = TerminalPluginEventReceiver(authorizationToken: "secret", onFlashEvent: { _ in })

        #expect(throws: TerminalPluginEventReceiverError.unauthorized) {
            try receiver.receive(data: validEventData(), authorizationHeader: "Bearer wrong")
        }
    }

    @Test
    func oversizedPayloadIsRejected() {
        let receiver = TerminalPluginEventReceiver(authorizationToken: "secret", onFlashEvent: { _ in })
        let oversized = Data(repeating: 0, count: TerminalPluginEventReceiver.maxBodyBytes + 1)

        #expect(throws: TerminalPluginEventReceiverError.payloadTooLarge) {
            try receiver.receive(data: oversized, authorizationHeader: "Bearer secret")
        }
    }

    @Test
    func malformedEventIsRejected() {
        let receiver = TerminalPluginEventReceiver(authorizationToken: "secret", onFlashEvent: { _ in })

        #expect(throws: TerminalPluginEventReceiverError.malformedEvent) {
            try receiver.receive(data: Data("{".utf8), authorizationHeader: "Bearer secret")
        }
    }

    @Test
    func commandCompletionProducesFlash() throws {
        var flashes: [LocalPetEvent] = []
        let receiver = TerminalPluginEventReceiver(authorizationToken: "secret") { event in
            flashes.append(event)
        }

        let event = try receiver.receive(data: validEventData(), authorizationHeader: "Bearer secret")

        #expect(event.kind == .commandCompleted)
        #expect(flashes.count == 1)
        #expect(flashes.first?.message == "swift test passed")
    }

    @Test
    func commandEventDoesNotMutateAgentRegistry() throws {
        let registry = AgentRegistry()
        let receiver = TerminalPluginEventReceiver(authorizationToken: "secret", onFlashEvent: { _ in })

        try receiver.receive(data: validEventData(), authorizationHeader: "Bearer secret")

        #expect(registry.snapshot.sessions.isEmpty)
    }

    @Test
    func rateLimitedCommandEventsAreRejected() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let limiter = SourceRateLimiter(
            policies: ["terminal-plugin:kitty:command-completed": SourceRateLimiter.Policy(maxEvents: 1, windowMs: 1_000)],
            defaultPolicy: SourceRateLimiter.Policy(maxEvents: 10, windowMs: 1_000),
            now: { now }
        )
        let receiver = TerminalPluginEventReceiver(
            authorizationToken: "secret",
            rateLimiter: limiter,
            onFlashEvent: { _ in }
        )

        try receiver.receive(data: validEventData(), authorizationHeader: "Bearer secret")

        #expect(throws: TerminalPluginEventReceiverError.rateLimited(retryAfterMs: 1_000)) {
            try receiver.receive(data: validEventData(), authorizationHeader: "Bearer secret")
        }

        now = now.addingTimeInterval(1)
        try receiver.receive(data: validEventData(), authorizationHeader: "Bearer secret")
    }

    @Test
    func commandQuotaDoesNotStarveAgentObservationQuota() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let limiter = SourceRateLimiter(
            policies: [
                "terminal-plugin:kitty:command-completed": SourceRateLimiter.Policy(maxEvents: 1, windowMs: 1_000),
                "terminal-plugin:kitty:agent-observed": SourceRateLimiter.Policy(maxEvents: 1, windowMs: 1_000)
            ],
            defaultPolicy: SourceRateLimiter.Policy(maxEvents: 10, windowMs: 1_000),
            now: { now }
        )
        var observed: [TerminalPluginEvent] = []
        let receiver = TerminalPluginEventReceiver(
            authorizationToken: "secret",
            rateLimiter: limiter,
            onFlashEvent: { _ in },
            onAgentObserved: { observed.append($0) }
        )

        try receiver.receive(data: validEventData(), authorizationHeader: "Bearer secret")
        #expect(throws: TerminalPluginEventReceiverError.rateLimited(retryAfterMs: 1_000)) {
            try receiver.receive(data: validEventData(), authorizationHeader: "Bearer secret")
        }

        try receiver.receive(data: agentObservedEventData(), authorizationHeader: "Bearer secret")
        #expect(observed.count == 1)

        now = now.addingTimeInterval(1)
        try receiver.receive(data: validEventData(), authorizationHeader: "Bearer secret")
    }

    private func validEventData() -> Data {
        Data("""
        {
          "schemaVersion": 1,
          "kind": "command-completed",
          "terminal": {
            "kind": "kitty",
            "sessionId": "kitty-42",
            "windowId": "42",
            "cwd": "/tmp/project"
          },
          "command": "swift test",
          "exitCode": 0,
          "durationMs": 2500,
          "occurredAt": 1000
        }
        """.utf8)
    }

    private func agentObservedEventData() -> Data {
        Data("""
        {
          "schemaVersion": 1,
          "kind": "agent-observed",
          "terminal": {
            "kind": "kitty",
            "sessionId": "kitty-42",
            "windowId": "42",
            "cwd": "/tmp/project",
            "controlEndpoint": "unix:/tmp/kitty"
          },
          "command": "codex",
          "providerHint": "codex",
          "occurredAt": 1000
        }
        """.utf8)
    }
}
