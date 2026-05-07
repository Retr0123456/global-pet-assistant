import Foundation

struct AgentAppServerTransport: AgentControlTransport {
    let kind: AgentControlTransportKind = .agentAppServer

    func capabilities(for session: AgentSession) -> Set<AgentCapability> {
        []
    }
}
