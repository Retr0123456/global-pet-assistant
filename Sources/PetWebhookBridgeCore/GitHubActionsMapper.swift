import Foundation

public struct BridgeAction: Codable, Equatable {
    public var type: String
    public var url: String?

    public init(type: String, url: String? = nil) {
        self.type = type
        self.url = url
    }
}

public struct BridgeEvent: Codable, Equatable {
    public var source: String
    public var type: String
    public var level: String
    public var title: String
    public var message: String?
    public var ttlMs: Int
    public var dedupeKey: String?
    public var action: BridgeAction?

    public init(
        source: String,
        type: String,
        level: String,
        title: String,
        message: String? = nil,
        ttlMs: Int,
        dedupeKey: String? = nil,
        action: BridgeAction? = nil
    ) {
        self.source = source
        self.type = type
        self.level = level
        self.title = title
        self.message = message
        self.ttlMs = ttlMs
        self.dedupeKey = dedupeKey
        self.action = action
    }
}

public enum PayloadMappingError: Error, CustomStringConvertible {
    case invalidJSON

    public var description: String {
        switch self {
        case .invalidJSON:
            "Webhook payload must be a JSON object."
        }
    }
}

public enum GitHubActionsMapper {
    public static func event(from data: Data) throws -> BridgeEvent {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PayloadMappingError.invalidJSON
        }

        guard let object = jsonObject as? [String: Any] else {
            throw PayloadMappingError.invalidJSON
        }

        let repository = firstString(in: object, paths: [
            ["repository", "full_name"],
            ["repository"],
            ["repo"],
            ["project"]
        ]) ?? "GitHub Actions"

        let workflow = firstString(in: object, paths: [
            ["workflow_run", "name"],
            ["workflow", "name"],
            ["workflow"],
            ["name"],
            ["job"],
            ["check_run", "name"]
        ]) ?? "Workflow"

        let status = firstString(in: object, paths: [
            ["workflow_run", "conclusion"],
            ["workflow_run", "status"],
            ["check_suite", "conclusion"],
            ["check_run", "conclusion"],
            ["conclusion"],
            ["status"],
            ["state"]
        ])?.lowercased() ?? "unknown"

        let level = levelForStatus(status)
        let result = resultLabel(level: level, status: status)
        let url = firstString(in: object, paths: [
            ["workflow_run", "html_url"],
            ["run", "html_url"],
            ["check_run", "html_url"],
            ["html_url"],
            ["action_url"],
            ["url"]
        ]) ?? actionsURL(for: repository)
        let runID = firstString(in: object, paths: [
            ["workflow_run", "id"],
            ["run", "id"],
            ["check_run", "id"],
            ["id"]
        ])

        return BridgeEvent(
            source: "ci",
            type: "ci.workflow",
            level: level,
            title: "\(workflow) \(result)",
            message: repository,
            ttlMs: level == "success" ? 45_000 : 120_000,
            dedupeKey: runID.map { "github-actions:\($0)" } ?? "github-actions:\(repository):\(workflow)",
            action: url.map { BridgeAction(type: "open_url", url: $0) }
        )
    }

    private static func levelForStatus(_ status: String) -> String {
        if ["success", "succeeded", "passed", "completed"].contains(status) {
            return "success"
        }
        if ["failure", "failed", "timed_out", "cancelled", "action_required"].contains(status) {
            return "danger"
        }
        if ["queued", "requested", "waiting", "pending"].contains(status) {
            return "warning"
        }
        return "running"
    }

    private static func resultLabel(level: String, status: String) -> String {
        switch level {
        case "success":
            "succeeded"
        case "danger":
            "failed"
        case "warning":
            status
        default:
            "running"
        }
    }

    private static func actionsURL(for repository: String) -> String? {
        let parts = repository.split(separator: "/")
        guard parts.count == 2 else {
            return nil
        }

        return "https://github.com/\(repository)/actions"
    }

    private static func firstString(in object: [String: Any], paths: [[String]]) -> String? {
        for path in paths {
            if let value = string(in: object, path: path) {
                return value
            }
        }

        return nil
    }

    private static func string(in object: [String: Any], path: [String]) -> String? {
        var current: Any = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key]
            else {
                return nil
            }

            current = next
        }

        switch current {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }
}
