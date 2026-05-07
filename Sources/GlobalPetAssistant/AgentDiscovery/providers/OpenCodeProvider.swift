import Foundation

struct OpenCodeProvider: AgentProvider {
    let kind: AgentKind = .opencode

    func sessionUpdate(from candidate: AgentDiscoveryCandidate) -> AgentSessionUpdate? {
        nil
    }
}
