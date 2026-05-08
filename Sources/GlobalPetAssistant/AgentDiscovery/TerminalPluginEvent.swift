import Foundation

enum TerminalPluginEventKind: String, Codable, Equatable, Sendable {
    case commandStarted = "command-started"
    case commandCompleted = "command-completed"
    case agentObserved = "agent-observed"
}

struct TerminalPluginEvent: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var kind: TerminalPluginEventKind
    var terminal: TerminalSessionContext
    var command: String?
    var exitCode: Int?
    var durationMs: Int?
    var outputSummary: String?
    var providerHint: AgentKind?
    var occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case terminal
        case command
        case exitCode
        case durationMs
        case outputSummary
        case providerHint
        case occurredAt
    }

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: TerminalPluginEventKind,
        terminal: TerminalSessionContext,
        command: String? = nil,
        exitCode: Int? = nil,
        durationMs: Int? = nil,
        outputSummary: String? = nil,
        providerHint: AgentKind? = nil,
        occurredAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.terminal = terminal
        self.command = command
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.outputSummary = outputSummary
        self.providerHint = providerHint
        self.occurredAt = occurredAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported terminal plugin schema version \(schemaVersion)."
            )
        }

        kind = try container.decode(TerminalPluginEventKind.self, forKey: .kind)
        terminal = try container.decode(TerminalSessionContext.self, forKey: .terminal)
        command = try Self.optionalTrimmed(container.decodeIfPresent(String.self, forKey: .command))
        exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        outputSummary = try Self.optionalTrimmed(container.decodeIfPresent(String.self, forKey: .outputSummary))
        providerHint = try container.decodeIfPresent(AgentKind.self, forKey: .providerHint)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
    }

    private static func optionalTrimmed(_ value: String?) throws -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
