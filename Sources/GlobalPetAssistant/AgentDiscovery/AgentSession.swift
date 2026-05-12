import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    static func fromJSONCompatible(_ value: Any) -> JSONValue {
        switch value {
        case let value as String:
            return .string(value)
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .number(Double(value))
        case let value as Double:
            return .number(value)
        case let value as [Any]:
            return .array(value.map(JSONValue.fromJSONCompatible))
        case let value as [String: Any]:
            return .object(value.mapValues(JSONValue.fromJSONCompatible))
        default:
            return .null
        }
    }
}

enum AgentKind: String, Codable, Equatable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case opencode
}

enum AgentCapabilityRouteKind: String, Codable, Equatable, Hashable, Sendable {
    case agentAppServer = "agent-app-server"
    case terminalPlugin = "terminal-plugin"
}

enum AgentStatus: String, Codable, Equatable, Sendable {
    case started
    case running
    case waiting
    case completed
    case failed
    case unknown
}

enum AgentCapability: String, Codable, Equatable, Hashable, Sendable {
    case observe
    case focus
    case readHistory = "read-history"
    case sendMessage = "send-message"
    case approvePermission = "approve-permission"
    case denyPermission = "deny-permission"
}

enum AgentSignalStrength: Int, Codable, Comparable, Sendable {
    case workspaceMarker = 10
    case terminalScan = 20
    case terminalPlugin = 25
    case processScan = 30
    case tmuxScan = 40
    case rolloutJSONL = 50
    case appServerSnapshot = 60
    case hookEvent = 70

    static func < (lhs: AgentSignalStrength, rhs: AgentSignalStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AgentSession: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: AgentKind
    var capabilityRoutes: [AgentCapabilityRouteKind: Set<AgentCapability>]
    var status: AgentStatus
    var capabilities: Set<AgentCapability>
    var createdAt: Date
    var lastSeenAt: Date
    var pid: Int?
    var cwd: String?
    var tty: String?
    var tmuxPaneId: String?
    var title: String?
    var message: String?
    var pendingPermissionDescription: String?
    var metadata: [String: JSONValue]

    init(
        id: String,
        kind: AgentKind,
        capabilityRoutes: [AgentCapabilityRouteKind: Set<AgentCapability>] = [:],
        status: AgentStatus = .unknown,
        capabilities: Set<AgentCapability> = [],
        createdAt: Date,
        lastSeenAt: Date,
        pid: Int? = nil,
        cwd: String? = nil,
        tty: String? = nil,
        tmuxPaneId: String? = nil,
        title: String? = nil,
        message: String? = nil,
        pendingPermissionDescription: String? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.capabilityRoutes = capabilityRoutes
        self.status = status
        self.capabilities = capabilities.isEmpty
            ? Set(capabilityRoutes.values.flatMap { $0 })
            : capabilities
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.pid = pid
        self.cwd = cwd
        self.tty = tty
        self.tmuxPaneId = tmuxPaneId
        self.title = title
        self.message = message
        self.pendingPermissionDescription = pendingPermissionDescription
        self.metadata = metadata
    }
}

struct AgentSessionUpdate: Equatable, Sendable {
    var id: String
    var kind: AgentKind
    var status: AgentStatus?
    var capabilityRoutes: [AgentCapabilityRouteKind: Set<AgentCapability>]?
    var capabilities: Set<AgentCapability>?
    var observedAt: Date
    var sourceStrength: AgentSignalStrength
    var pid: Int?
    var cwd: String?
    var tty: String?
    var tmuxPaneId: String?
    var title: String?
    var message: String?
    var pendingPermissionDescription: String?
    var metadata: [String: JSONValue]

    init(
        id: String,
        kind: AgentKind,
        status: AgentStatus? = nil,
        capabilityRoutes: [AgentCapabilityRouteKind: Set<AgentCapability>]? = nil,
        capabilities: Set<AgentCapability>? = nil,
        observedAt: Date,
        sourceStrength: AgentSignalStrength,
        pid: Int? = nil,
        cwd: String? = nil,
        tty: String? = nil,
        tmuxPaneId: String? = nil,
        title: String? = nil,
        message: String? = nil,
        pendingPermissionDescription: String? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.capabilityRoutes = capabilityRoutes
        self.capabilities = capabilities
        self.observedAt = observedAt
        self.sourceStrength = sourceStrength
        self.pid = pid
        self.cwd = cwd
        self.tty = tty
        self.tmuxPaneId = tmuxPaneId
        self.title = title
        self.message = message
        self.pendingPermissionDescription = pendingPermissionDescription
        self.metadata = metadata
    }
}

struct AgentDiscoveryCandidate: Equatable, Sendable {
    var kind: AgentKind?
    var confidence: Double
    var sourceStrength: AgentSignalStrength
    var observedAt: Date
    var metadata: [String: JSONValue]

    init(
        kind: AgentKind? = nil,
        confidence: Double = 0,
        sourceStrength: AgentSignalStrength,
        observedAt: Date,
        metadata: [String: JSONValue] = [:]
    ) {
        self.kind = kind
        self.confidence = confidence
        self.sourceStrength = sourceStrength
        self.observedAt = observedAt
        self.metadata = metadata
    }
}

struct AgentRegistrySnapshot: Equatable, Sendable {
    var sessions: [AgentSession]

    var activeCount: Int {
        sessions.filter { ![AgentStatus.completed, .failed].contains($0.status) }.count
    }
}

struct AgentThreadSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var kind: AgentKind
    var capabilityRoutes: [AgentCapabilityRouteKind: Set<AgentCapability>]
    var status: PetThreadStatus
    var title: String
    var context: String
    var directoryName: String
    var messagePreview: String
    var capabilities: Set<AgentCapability>
    var lastSeenAt: Date
}
