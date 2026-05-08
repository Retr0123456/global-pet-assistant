import Foundation

@MainActor
final class AgentDiscoveryService {
    typealias RegistrySnapshotHandler = @MainActor (AgentRegistrySnapshot) -> Void
    typealias ProjectedEventHandler = @MainActor (LocalPetEvent) -> Void

    private let registry: AgentRegistry
    private let hookReceiver: HookEventReceiver
    private let providers: [AgentKind: any AgentProvider]
    private var hookSocketServer: AgentHookSocketServer?
    private let onSnapshotChange: RegistrySnapshotHandler?
    private let onProjectedEvent: ProjectedEventHandler?

    init(
        registry: AgentRegistry = AgentRegistry(),
        providers: [AgentKind: any AgentProvider] = [
            .codex: CodexProvider(),
            .claudeCode: ClaudeCodeProvider(),
            .opencode: OpenCodeProvider()
        ],
        onSnapshotChange: RegistrySnapshotHandler? = nil,
        onProjectedEvent: ProjectedEventHandler? = nil
    ) {
        self.registry = registry
        self.providers = providers
        self.onSnapshotChange = onSnapshotChange
        self.onProjectedEvent = onProjectedEvent
        self.hookReceiver = HookEventReceiver(providers: providers) { [registry] update in
            registry.upsert(update)
        }
    }

    var snapshot: AgentRegistrySnapshot {
        registry.snapshot
    }

    func session(id: String) -> AgentSession? {
        registry.session(id: id)
    }

    func archiveSession(id: String) {
        registry.archive(id: id)
        onSnapshotChange?(registry.snapshot)
    }

    func startHookSocket() {
        guard hookSocketServer == nil else {
            return
        }

        let server = AgentHookSocketServer(socketURL: AppStorage.agentHookSocketURL) { [weak self] envelope in
            Task { @MainActor in
                self?.receiveHookEnvelope(envelope)
            }
        }

        do {
            try server.start()
            hookSocketServer = server
        } catch {
            AuditLogger.appendRuntime(status: "agent_hook_socket_failed", message: String(describing: error))
        }
    }

    func stop() {
        hookSocketServer?.stop()
        hookSocketServer = nil
    }

    func receiveHookEnvelope(_ envelope: AgentHookEnvelope) {
        hookReceiver.receive(envelope)
        let snapshot = registry.snapshot
        onSnapshotChange?(snapshot)
        for session in snapshot.sessions {
            onProjectedEvent?(AgentEventProjection.localEvent(for: session))
        }
    }

    func receiveTerminalPluginEvent(_ event: TerminalPluginEvent) {
        guard event.kind == .agentObserved,
              let providerHint = event.providerHint,
              let provider = providers[providerHint],
              let update = provider.sessionUpdate(from: event) else {
            return
        }

        registry.upsert(update)
        let snapshot = registry.snapshot
        onSnapshotChange?(snapshot)
        for session in snapshot.sessions {
            onProjectedEvent?(AgentEventProjection.localEvent(for: session))
        }
    }
}
