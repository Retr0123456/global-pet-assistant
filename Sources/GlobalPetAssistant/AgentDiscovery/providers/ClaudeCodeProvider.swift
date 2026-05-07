import Foundation

struct ClaudeCodeProvider: AgentProvider {
    let kind: AgentKind = .claudeCode

    func sessionUpdate(from candidate: AgentDiscoveryCandidate) -> AgentSessionUpdate? {
        nil
    }
}
