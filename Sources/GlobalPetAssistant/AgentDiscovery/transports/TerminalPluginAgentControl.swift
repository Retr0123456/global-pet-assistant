import Foundation

struct TerminalPluginAgentControl: AgentControl {
    private let terminalTransport: any TerminalTransport

    init(terminalTransport: any TerminalTransport) {
        self.terminalTransport = terminalTransport
    }

    func sendMessage(_ text: String, to session: AgentSession) async throws {
        guard session.controlRoutes[.terminalPlugin]?.contains(.sendMessage) == true,
              session.capabilities.contains(.sendMessage) else {
            throw AgentControlTransportError.capabilityUnavailable(.sendMessage)
        }

        guard [.codex, .claudeCode, .opencode].contains(session.kind),
              [.started, .running, .waiting].contains(session.status) else {
            throw AgentControlTransportError.unsupported
        }

        let context = try terminalContext(from: session)
        guard context.kind == terminalTransport.integrationKind else {
            throw TerminalTransportError.invalidTarget("Session terminal context does not match transport.")
        }

        try await terminalTransport.sendMessage(text, to: context)
    }

    func approvePermission(for session: AgentSession) async throws {
        throw AgentControlTransportError.unsupported
    }

    func denyPermission(for session: AgentSession) async throws {
        throw AgentControlTransportError.unsupported
    }

    private func terminalContext(from session: AgentSession) throws -> TerminalSessionContext {
        guard let kindValue = session.metadata["terminal_kind"]?.stringValue,
              let kind = TerminalIntegrationKind(rawValue: kindValue),
              let sessionId = session.metadata["terminal_session_id"]?.stringValue else {
            throw TerminalTransportError.invalidTarget("Session has no terminal plugin context.")
        }

        return TerminalSessionContext(
            kind: kind,
            sessionId: sessionId,
            windowId: session.metadata["terminal_window_id"]?.stringValue,
            tabId: session.metadata["terminal_tab_id"]?.stringValue,
            cwd: session.cwd,
            command: nil,
            controlEndpoint: session.metadata["terminal_control_endpoint"]?.stringValue
        )
    }
}
