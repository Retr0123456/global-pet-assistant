import Foundation

final class AgentRegistry {
    private var sessionsByID: [String: AgentSession] = [:]
    private var strengthsByID: [String: [String: AgentSignalStrength]] = [:]
    private var archivedIDs: Set<String> = []

    @discardableResult
    func upsert(_ update: AgentSessionUpdate) -> AgentSession {
        if var existing = sessionsByID[update.id] {
            merge(update, into: &existing)
            sessionsByID[update.id] = existing
            return existing
        }

        let routes = update.controlRoutes ?? [:]
        let capabilities = update.capabilities ?? Set(routes.values.flatMap { $0 })
        let session = AgentSession(
            id: update.id,
            kind: update.kind,
            controlRoutes: routes,
            status: update.status ?? .unknown,
            capabilities: capabilities,
            createdAt: update.observedAt,
            lastSeenAt: update.observedAt,
            pid: update.pid,
            cwd: update.cwd,
            tty: update.tty,
            tmuxPaneId: update.tmuxPaneId,
            title: update.title,
            message: update.message,
            pendingPermissionDescription: update.pendingPermissionDescription,
            metadata: update.metadata
        )
        sessionsByID[update.id] = session
        strengthsByID[update.id] = initialStrengths(for: update)
        return session
    }

    func archive(id: String) {
        archivedIDs.insert(id)
    }

    func session(id: String) -> AgentSession? {
        sessionsByID[id]
    }

    var snapshot: AgentRegistrySnapshot {
        AgentRegistrySnapshot(sessions: visibleSessions)
    }

    @discardableResult
    func expireStale(now: Date, staleAfter interval: TimeInterval, keepCompletedFor completedInterval: TimeInterval) -> [AgentSession] {
        let removed = sessionsByID.values.filter { session in
            if session.status == .completed {
                return now.timeIntervalSince(session.lastSeenAt) >= completedInterval
            }
            return now.timeIntervalSince(session.lastSeenAt) >= interval
        }

        for session in removed {
            sessionsByID.removeValue(forKey: session.id)
            strengthsByID.removeValue(forKey: session.id)
            archivedIDs.remove(session.id)
        }

        return removed
    }

    private var visibleSessions: [AgentSession] {
        sessionsByID.values
            .filter { !archivedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.lastSeenAt == rhs.lastSeenAt {
                    return lhs.id < rhs.id
                }
                return lhs.lastSeenAt > rhs.lastSeenAt
            }
    }

    private func merge(_ update: AgentSessionUpdate, into session: inout AgentSession) {
        var strengths = strengthsByID[update.id] ?? [:]
        session.lastSeenAt = max(session.lastSeenAt, update.observedAt)

        apply(update.status, to: &session.status, key: "status", updateStrength: update.sourceStrength, strengths: &strengths)
        apply(update.pid, to: &session.pid, key: "pid", updateStrength: update.sourceStrength, strengths: &strengths)
        apply(update.cwd, to: &session.cwd, key: "cwd", updateStrength: update.sourceStrength, strengths: &strengths)
        apply(update.tty, to: &session.tty, key: "tty", updateStrength: update.sourceStrength, strengths: &strengths)
        apply(update.tmuxPaneId, to: &session.tmuxPaneId, key: "tmuxPaneId", updateStrength: update.sourceStrength, strengths: &strengths)
        apply(trimmed(update.title), to: &session.title, key: "title", updateStrength: update.sourceStrength, strengths: &strengths)
        apply(trimmed(update.message), to: &session.message, key: "message", updateStrength: update.sourceStrength, strengths: &strengths)
        apply(trimmed(update.pendingPermissionDescription), to: &session.pendingPermissionDescription, key: "pendingPermissionDescription", updateStrength: update.sourceStrength, strengths: &strengths)

        if let routes = update.controlRoutes,
           shouldAccept(key: "controlRoutes", updateStrength: update.sourceStrength, strengths: strengths) {
            session.controlRoutes = routes
            strengths["controlRoutes"] = update.sourceStrength
        }

        if let capabilities = update.capabilities,
           shouldAccept(key: "capabilities", updateStrength: update.sourceStrength, strengths: strengths) {
            session.capabilities = capabilities
            strengths["capabilities"] = update.sourceStrength
        } else if update.controlRoutes != nil {
            session.capabilities = Set(session.controlRoutes.values.flatMap { $0 })
        }

        for (key, value) in update.metadata {
            let strengthKey = "metadata.\(key)"
            if shouldAccept(key: strengthKey, updateStrength: update.sourceStrength, strengths: strengths) {
                session.metadata[key] = value
                strengths[strengthKey] = update.sourceStrength
            }
        }

        strengthsByID[update.id] = strengths
    }

    private func apply<T>(
        _ value: T?,
        to target: inout T?,
        key: String,
        updateStrength: AgentSignalStrength,
        strengths: inout [String: AgentSignalStrength]
    ) {
        guard let value else {
            return
        }

        if shouldAccept(key: key, updateStrength: updateStrength, strengths: strengths) {
            target = value
            strengths[key] = updateStrength
        }
    }

    private func apply<T>(
        _ value: T?,
        to target: inout T,
        key: String,
        updateStrength: AgentSignalStrength,
        strengths: inout [String: AgentSignalStrength]
    ) {
        guard let value else {
            return
        }

        if shouldAccept(key: key, updateStrength: updateStrength, strengths: strengths) {
            target = value
            strengths[key] = updateStrength
        }
    }

    private func shouldAccept(
        key: String,
        updateStrength: AgentSignalStrength,
        strengths: [String: AgentSignalStrength]
    ) -> Bool {
        guard let existingStrength = strengths[key] else {
            return true
        }
        return updateStrength >= existingStrength
    }

    private func initialStrengths(for update: AgentSessionUpdate) -> [String: AgentSignalStrength] {
        var strengths: [String: AgentSignalStrength] = [
            "status": update.sourceStrength,
            "controlRoutes": update.sourceStrength,
            "capabilities": update.sourceStrength
        ]
        let optionalFields: [(String, Any?)] = [
            ("pid", update.pid),
            ("cwd", update.cwd),
            ("tty", update.tty),
            ("tmuxPaneId", update.tmuxPaneId),
            ("title", update.title),
            ("message", update.message),
            ("pendingPermissionDescription", update.pendingPermissionDescription)
        ]
        for (key, value) in optionalFields where value != nil {
            strengths[key] = update.sourceStrength
        }
        for key in update.metadata.keys {
            strengths["metadata.\(key)"] = update.sourceStrength
        }
        return strengths
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
