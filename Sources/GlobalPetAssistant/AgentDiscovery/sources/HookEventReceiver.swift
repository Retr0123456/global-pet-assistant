import Foundation

struct AgentHookEvent: Equatable, Sendable {
    var source: AgentHookSource
    var envelope: AgentHookEnvelope
}

struct HookEventReceiver {
    private let providers: [AgentKind: any AgentProvider]
    private let onSessionUpdate: (AgentSessionUpdate) -> Void

    init(
        providers: [AgentKind: any AgentProvider],
        onSessionUpdate: @escaping (AgentSessionUpdate) -> Void
    ) {
        self.providers = providers
        self.onSessionUpdate = onSessionUpdate
    }

    func receive(_ envelope: AgentHookEnvelope) {
        guard let kind = agentKind(for: envelope.source) else {
            AuditLogger.appendRuntime(status: "agent_hook_ignored", message: "Unsupported source \(envelope.source.rawValue)")
            return
        }

        guard let provider = providers[kind] else {
            AuditLogger.appendRuntime(status: "agent_hook_ignored", message: "No provider for \(kind.rawValue)")
            return
        }

        guard let update = provider.sessionUpdate(from: envelope) else {
            AuditLogger.appendRuntime(status: "agent_hook_no_update", message: "\(kind.rawValue) provider produced no update")
            return
        }

        onSessionUpdate(update)
        AuditLogger.appendRuntime(status: "agent_hook_accepted", message: "\(kind.rawValue) \(update.id)")
    }

    private func agentKind(for source: AgentHookSource) -> AgentKind? {
        switch source {
        case .codex:
            return .codex
        case .claudeCode:
            return .claudeCode
        case .opencode:
            return .opencode
        }
    }
}
