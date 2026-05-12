import Foundation

struct AgentAppServerTransport: AgentControlTransport {
    let kind: AgentCapabilityRouteKind = .agentAppServer

    func capabilities(for session: AgentSession) -> Set<AgentCapability> {
        []
    }
}
