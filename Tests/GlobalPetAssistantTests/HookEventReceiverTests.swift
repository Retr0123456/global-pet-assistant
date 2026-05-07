import Foundation
import Testing
@testable import GlobalPetAssistant

struct HookEventReceiverTests {
    @Test
    func unsupportedSourceIsIgnoredWithoutCreatingUpdate() throws {
        var updates: [AgentSessionUpdate] = []
        let receiver = HookEventReceiver(providers: [.codex: EmptyProvider(kind: .codex)]) { update in
            updates.append(update)
        }

        receiver.receive(try envelope(source: .opencode))

        #expect(updates.isEmpty)
    }

    @Test
    func codexEnvelopeReachesCodexProvider() throws {
        let provider = RecordingProvider()
        var updates: [AgentSessionUpdate] = []
        let receiver = HookEventReceiver(providers: [.codex: provider]) { update in
            updates.append(update)
        }

        receiver.receive(try envelope(source: .codex))

        #expect(provider.receivedSources == [.codex])
        #expect(updates.map(\.id) == ["codex-session-from-provider"])
    }

    @Test
    func socketDecoderRejectsInvalidEnvelopeWithoutNeedingServerRuntime() {
        #expect(throws: AgentHookEnvelopeError.invalidJSON) {
            try AgentHookSocketServer.decodeEnvelopeData(Data("{".utf8))
        }
    }

    private func envelope(source: AgentHookSource) throws -> AgentHookEnvelope {
        try AgentHookEnvelope.make(
            source: source,
            arguments: [],
            stdinData: Data(#"{"hook_event_name":"SessionStart","session_id":"s1"}"#.utf8),
            environment: [:],
            receivedAt: Date(timeIntervalSince1970: 1_000),
            currentDirectory: "/tmp/project",
            parentProcessID: nil
        )
    }
}

private struct EmptyProvider: AgentProvider {
    let kind: AgentKind

    func sessionUpdate(from candidate: AgentDiscoveryCandidate) -> AgentSessionUpdate? {
        nil
    }

    func sessionUpdate(from envelope: AgentHookEnvelope) -> AgentSessionUpdate? {
        nil
    }
}

private final class RecordingProvider: AgentProvider {
    let kind: AgentKind = .codex
    var receivedSources: [AgentHookSource] = []

    func sessionUpdate(from candidate: AgentDiscoveryCandidate) -> AgentSessionUpdate? {
        nil
    }

    func sessionUpdate(from envelope: AgentHookEnvelope) -> AgentSessionUpdate? {
        receivedSources.append(envelope.source)
        return AgentSessionUpdate(
            id: "codex-session-from-provider",
            kind: .codex,
            status: .started,
            observedAt: envelope.receivedAt,
            sourceStrength: .hookEvent
        )
    }
}
