import Foundation

protocol AgentControl {
    func sendMessage(_ text: String, to session: AgentSession) async throws
    func approvePermission(for session: AgentSession) async throws
    func denyPermission(for session: AgentSession) async throws
}

struct UnsupportedAgentControl: AgentControl {
    func sendMessage(_ text: String, to session: AgentSession) async throws {
        throw AgentControlTransportError.unsupported
    }

    func approvePermission(for session: AgentSession) async throws {
        throw AgentControlTransportError.unsupported
    }

    func denyPermission(for session: AgentSession) async throws {
        throw AgentControlTransportError.unsupported
    }
}
