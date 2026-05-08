import Foundation
import Testing
@testable import GlobalPetAssistant

@MainActor
struct TerminalPluginProviderIntegrationTests {
    @Test
    func codexTerminalEventCanCreateRecognizedSessionWithSendMessageRoute() {
        let service = AgentDiscoveryService()

        service.receiveTerminalPluginEvent(codexTerminalEvent(exitCode: nil))

        let session = service.snapshot.sessions.first
        #expect(session?.kind == .codex)
        #expect(session?.status == .running)
        #expect(session?.controlRoutes[.terminalPlugin] == [.observe, .sendMessage])
        #expect(session?.capabilities.contains(.sendMessage) == true)
        #expect(session?.metadata["terminal_kind"] == .string("kitty"))
    }

    @Test
    func terminalEventWithoutProviderRecognitionDoesNotCreateSession() {
        let service = AgentDiscoveryService()
        var event = codexTerminalEvent(exitCode: nil)
        event.providerHint = nil

        service.receiveTerminalPluginEvent(event)

        #expect(service.snapshot.sessions.isEmpty)
    }

    @Test
    func codexTerminalEventCanMarkSessionCompleted() {
        let service = AgentDiscoveryService()

        service.receiveTerminalPluginEvent(codexTerminalEvent(exitCode: 0))

        #expect(service.snapshot.sessions.first?.status == .completed)
    }

    @Test
    func hookBackedIdentityIsNotOverwrittenByTerminalPluginMetadata() throws {
        let service = AgentDiscoveryService()
        service.receiveHookEnvelope(try AgentHookEnvelope.make(
            source: .codex,
            arguments: [],
            stdinData: Data(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/tmp/hook"}"#.utf8),
            environment: [:],
            receivedAt: Date(timeIntervalSince1970: 2_000),
            currentDirectory: "/tmp/hook",
            parentProcessID: nil
        ))

        service.receiveTerminalPluginEvent(codexTerminalEvent(exitCode: nil))

        let hookSession = service.snapshot.sessions.first { $0.id == "s1" }
        #expect(hookSession?.metadata["identity_source"] == .string("session_id"))
        #expect(hookSession?.cwd == "/tmp/hook")
    }

    private func codexTerminalEvent(exitCode: Int?) -> TerminalPluginEvent {
        TerminalPluginEvent(
            kind: .agentObserved,
            terminal: TerminalSessionContext(
                kind: .kitty,
                sessionId: "kitty-42",
                windowId: "42",
                cwd: "/tmp/project",
                command: "codex",
                controlEndpoint: "unix:/tmp/kitty"
            ),
            command: "codex",
            exitCode: exitCode,
            providerHint: .codex,
            occurredAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
