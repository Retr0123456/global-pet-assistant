import Foundation

protocol AgentControlTransport {
    var kind: AgentControlTransportKind { get }

    func capabilities(for session: AgentSession) -> Set<AgentCapability>
}

enum AgentControlTransportError: Error, Equatable {
    case unsupported
    case sessionMissing
    case capabilityUnavailable(AgentCapability)
}
