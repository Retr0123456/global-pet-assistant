import Foundation

enum AgentEventProjection {
    static func localEvent(for session: AgentSession) -> LocalPetEvent {
        LocalPetEvent(
            source: "agent:\(session.kind.rawValue):\(shortKey(for: session.id))",
            type: eventType(for: session),
            level: level(for: session),
            title: session.title ?? "\(session.kind.rawValue) session",
            message: session.pendingPermissionDescription ?? session.message,
            state: state(for: session),
            ttlMs: ttl(for: session),
            dedupeKey: "agent-session:\(session.id)",
            cwd: session.cwd
        )
    }

    private static func eventType(for session: AgentSession) -> String {
        if session.status == .waiting, session.pendingPermissionDescription != nil {
            return "agent.permission.request"
        }
        return "agent.session.\(session.status.rawValue)"
    }

    private static func level(for session: AgentSession) -> PetEventLevel {
        switch session.status {
        case .started, .running:
            return .running
        case .waiting:
            return .warning
        case .completed:
            return .success
        case .failed:
            return .danger
        case .unknown:
            return .info
        }
    }

    private static func state(for session: AgentSession) -> PetAnimationState {
        switch session.status {
        case .started, .running:
            return .running
        case .waiting:
            return .waiting
        case .completed:
            return .review
        case .failed:
            return .failed
        case .unknown:
            return .idle
        }
    }

    private static func ttl(for session: AgentSession) -> Int {
        switch session.status {
        case .waiting:
            return 120_000
        case .completed:
            return 45_000
        case .failed:
            return 120_000
        case .started, .running:
            return 15_000
        case .unknown:
            return 5_000
        }
    }

    private static func shortKey(for sessionID: String) -> String {
        let scalars = sessionID.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { hash, scalar in
            (hash ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return String(scalars, radix: 16)
    }
}
