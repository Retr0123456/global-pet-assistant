import Foundation

protocol AgentProvider {
    var kind: AgentKind { get }

    func sessionUpdate(from candidate: AgentDiscoveryCandidate) -> AgentSessionUpdate?
    func sessionUpdate(from envelope: AgentHookEnvelope) -> AgentSessionUpdate?
    func sessionUpdate(from terminalEvent: TerminalPluginEvent) -> AgentSessionUpdate?
}

extension AgentProvider {
    func sessionUpdate(from envelope: AgentHookEnvelope) -> AgentSessionUpdate? {
        nil
    }

    func sessionUpdate(from terminalEvent: TerminalPluginEvent) -> AgentSessionUpdate? {
        nil
    }
}
