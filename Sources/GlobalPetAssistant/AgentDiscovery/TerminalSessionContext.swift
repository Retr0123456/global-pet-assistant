import Foundation

enum TerminalIntegrationKind: String, Codable, Equatable, Sendable {
    case kitty
}

struct TerminalSessionContext: Codable, Equatable, Sendable {
    var kind: TerminalIntegrationKind
    var sessionId: String
    var windowId: String?
    var tabId: String?
    var cwd: String?
    var command: String?
    var controlEndpoint: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case sessionId
        case windowId
        case tabId
        case cwd
        case command
        case controlEndpoint
    }

    init(
        kind: TerminalIntegrationKind,
        sessionId: String,
        windowId: String? = nil,
        tabId: String? = nil,
        cwd: String? = nil,
        command: String? = nil,
        controlEndpoint: String? = nil
    ) {
        self.kind = kind
        self.sessionId = sessionId
        self.windowId = windowId
        self.tabId = tabId
        self.cwd = cwd
        self.command = command
        self.controlEndpoint = controlEndpoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(TerminalIntegrationKind.self, forKey: .kind)
        sessionId = try Self.trimmed(container.decode(String.self, forKey: .sessionId), field: "sessionId")
        windowId = try Self.optionalTrimmed(container.decodeIfPresent(String.self, forKey: .windowId), field: "windowId")
        tabId = try Self.optionalTrimmed(container.decodeIfPresent(String.self, forKey: .tabId), field: "tabId")
        cwd = try Self.optionalTrimmed(container.decodeIfPresent(String.self, forKey: .cwd), field: "cwd")
        command = try Self.optionalTrimmed(container.decodeIfPresent(String.self, forKey: .command), field: "command")
        controlEndpoint = try Self.optionalTrimmed(
            container.decodeIfPresent(String.self, forKey: .controlEndpoint),
            field: "controlEndpoint"
        )
    }

    private static func trimmed(_ value: String, field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Missing terminal \(field)."
            ))
        }
        return trimmed
    }

    private static func optionalTrimmed(_ value: String?, field: String) throws -> String? {
        guard let value else {
            return nil
        }
        return try trimmed(value, field: field)
    }
}

struct TerminalObservation: Equatable, Sendable {
    var context: TerminalSessionContext
    var isReachable: Bool
    var capabilities: Set<AgentCapability>
}
