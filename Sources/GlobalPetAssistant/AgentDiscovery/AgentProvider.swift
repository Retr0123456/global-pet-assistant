import Foundation

protocol AgentProvider {
    var kind: AgentKind { get }

    func sessionUpdate(from candidate: AgentDiscoveryCandidate) -> AgentSessionUpdate?
    func sessionUpdate(from envelope: AgentHookEnvelope) -> AgentSessionUpdate?
}

extension AgentProvider {
    func sessionUpdate(from envelope: AgentHookEnvelope) -> AgentSessionUpdate? {
        nil
    }
}
