import Foundation

enum AgentThreadProjection {
    static func snapshots(from registrySnapshot: AgentRegistrySnapshot) -> [AgentThreadSnapshot] {
        registrySnapshot.sessions.map(snapshot(for:))
    }

    static func snapshot(for session: AgentSession) -> AgentThreadSnapshot {
        AgentThreadSnapshot(
            id: session.id,
            kind: session.kind,
            capabilityRoutes: session.capabilityRoutes,
            status: threadStatus(for: session),
            title: title(for: session),
            context: context(for: session),
            directoryName: directoryName(for: session),
            messagePreview: messagePreview(for: session),
            capabilities: session.capabilities,
            lastSeenAt: session.lastSeenAt
        )
    }

    static func threadStatus(for session: AgentSession) -> PetThreadStatus {
        switch session.status {
        case .started, .running:
            return .running
        case .waiting where session.pendingPermissionDescription != nil:
            return .approvalRequired
        case .waiting:
            return .waiting
        case .completed:
            return .success
        case .failed:
            return .failed
        case .unknown:
            return .info
        }
    }

    private static func title(for session: AgentSession) -> String {
        let fallback = "\(session.kind.rawValue) session"
        return firstNonEmpty([session.title, fallback])
    }

    private static func context(for session: AgentSession) -> String {
        firstNonEmpty([
            session.pendingPermissionDescription,
            session.message,
            session.status.rawValue
        ])
    }

    private static func directoryName(for session: AgentSession) -> String {
        guard let cwd = session.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty
        else {
            return session.kind.rawValue
        }
        let component = URL(fileURLWithPath: cwd).lastPathComponent
        return component.isEmpty ? cwd : component
    }

    private static func messagePreview(for session: AgentSession) -> String {
        let normalized = context(for: session)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return truncate(normalized, limit: 120)
    }

    private static func firstNonEmpty(_ values: [String?]) -> String {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Agent session"
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit - 1)) + "..."
    }
}
