import Foundation
import Testing
@testable import GlobalPetAssistant

struct TerminalPluginAgentControlTests {
    @Test
    func knownProviderApprovedSessionCanReceiveMessage() async throws {
        let transport = RecordingTerminalTransport()
        let control = TerminalPluginAgentControl(terminalTransport: transport)

        try await control.sendMessage("continue", to: session(capabilities: [.sendMessage]))

        #expect(await transport.sentMessages == ["continue"])
    }

    @Test
    func sessionWithoutSendMessageCapabilityIsRejected() async {
        let control = TerminalPluginAgentControl(terminalTransport: RecordingTerminalTransport())

        await #expect(throws: AgentControlTransportError.capabilityUnavailable(.sendMessage)) {
            try await control.sendMessage("continue", to: session(capabilities: []))
        }
    }

    @Test
    func unknownTerminalSessionIsRejected() async {
        let control = TerminalPluginAgentControl(terminalTransport: RecordingTerminalTransport())
        var agent = session(capabilities: [.sendMessage])
        agent.metadata.removeValue(forKey: "terminal_session_id")

        await #expect(throws: TerminalTransportError.invalidTarget("Session has no terminal plugin context.")) {
            try await control.sendMessage("continue", to: agent)
        }
    }

    @Test
    func approvalAndDenialRemainUnsupported() async {
        let control = TerminalPluginAgentControl(terminalTransport: RecordingTerminalTransport())
        let agent = session(capabilities: [.sendMessage])

        await #expect(throws: AgentControlTransportError.unsupported) {
            try await control.approvePermission(for: agent)
        }
        await #expect(throws: AgentControlTransportError.unsupported) {
            try await control.denyPermission(for: agent)
        }
    }

    @Test
    func failedSendDoesNotMutateAgentStatus() async {
        let control = TerminalPluginAgentControl(terminalTransport: FailingTerminalTransport())
        let agent = session(capabilities: [.sendMessage])

        await #expect(throws: TerminalTransportError.staleTarget("gone")) {
            try await control.sendMessage("continue", to: agent)
        }

        #expect(agent.status == .running)
    }

    private func session(capabilities: Set<AgentCapability>) -> AgentSession {
        AgentSession(
            id: "codex-session",
            kind: .codex,
            controlRoutes: [.terminalPlugin: capabilities],
            status: .running,
            capabilities: capabilities,
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_000),
            cwd: "/tmp/project",
            metadata: [
                "terminal_kind": .string("kitty"),
                "terminal_session_id": .string("kitty-42"),
                "terminal_window_id": .string("42"),
                "terminal_control_endpoint": .string("unix:/tmp/kitty")
            ]
        )
    }
}

private actor RecordingTerminalTransport: TerminalTransport {
    let integrationKind: TerminalIntegrationKind = .kitty
    private(set) var sentMessages: [String] = []

    func observe(_ context: TerminalSessionContext) async throws -> TerminalObservation {
        TerminalObservation(context: context, isReachable: true, capabilities: [.observe, .sendMessage])
    }

    func sendMessage(_ text: String, to context: TerminalSessionContext) async throws {
        sentMessages.append(text)
    }
}

private struct FailingTerminalTransport: TerminalTransport {
    let integrationKind: TerminalIntegrationKind = .kitty

    func observe(_ context: TerminalSessionContext) async throws -> TerminalObservation {
        throw TerminalTransportError.staleTarget("gone")
    }

    func sendMessage(_ text: String, to context: TerminalSessionContext) async throws {
        throw TerminalTransportError.staleTarget("gone")
    }
}
