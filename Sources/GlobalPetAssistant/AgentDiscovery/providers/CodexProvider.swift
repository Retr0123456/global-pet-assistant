import Foundation

struct CodexProvider: AgentProvider {
    let kind: AgentKind = .codex

    func sessionUpdate(from candidate: AgentDiscoveryCandidate) -> AgentSessionUpdate? {
        nil
    }
}
