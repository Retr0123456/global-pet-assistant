import Foundation

enum AuditLogger {
    private static let queue = DispatchQueue(label: "global-pet-assistant.audit-logger")

    static func appendEvent(
        status: String,
        event: LocalPetEvent? = nil,
        state: PetAnimationState? = nil,
        httpStatus: Int? = nil,
        error: String? = nil
    ) {
        var record: [String: Any] = [
            "timestamp": auditTimestamp(),
            "status": status
        ]

        if let httpStatus {
            record["httpStatus"] = httpStatus
        }
        if let state {
            record["state"] = state.rawValue
        }
        if let error {
            record["error"] = error
        }
        if let event {
            record["source"] = event.source
            record["type"] = event.type
            record["level"] = event.level?.rawValue
            record["title"] = event.title
            record["message"] = event.message
            record["eventState"] = event.state?.rawValue
            record["ttlMs"] = event.ttlMs
            record["dedupeKey"] = event.dedupeKey
            if let action = event.action {
                record["actionType"] = action.type
            }
        }

        append(record, to: AppStorage.eventsLogURL)
    }

    static func appendRuntime(status: String, message: String) {
        append([
            "timestamp": auditTimestamp(),
            "status": status,
            "message": message
        ], to: AppStorage.runtimeLogURL)
    }

    private static func append(_ record: [String: Any], to url: URL) {
        let line: Data
        do {
            let data = try JSONSerialization.data(
                withJSONObject: record.compactMapValues { $0 },
                options: [.sortedKeys]
            )
            var mutableLine = data
            mutableLine.append(0x0A)
            line = mutableLine
        } catch {
            NSLog("GlobalPetAssistant audit log encode failed: \(String(describing: error))")
            return
        }

        queue.async {
            do {
                try AppStorage.ensureLayout()

                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                    try handle.close()
                } else {
                    try line.write(to: url, options: [.atomic])
                }
            } catch {
                NSLog("GlobalPetAssistant audit log write failed: \(String(describing: error))")
            }
        }
    }

    private static func auditTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
