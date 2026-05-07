import Foundation

protocol AgentProvider {
    var kind: AgentKind { get }

    func sessionUpdate(from candidate: AgentDiscoveryCandidate) -> AgentSessionUpdate?
}
