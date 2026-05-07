import Foundation

struct CodexHookProfile: Equatable {
    struct Event: Equatable {
        var name: String
        var matcher: String?
        var statusMessage: String
    }

    var command: String
    var timeoutSeconds: Int
    var managedCommandNeedle: String
    var events: [Event]

    init(command: String, timeoutSeconds: Int = 5) {
        self.command = command
        self.timeoutSeconds = timeoutSeconds
        self.managedCommandNeedle = "global-pet-agent-bridge"
        self.events = [
            Event(name: "SessionStart", matcher: "startup|resume", statusMessage: "Updating pet Codex session state"),
            Event(name: "UserPromptSubmit", matcher: nil, statusMessage: "Updating pet Codex running state"),
            Event(name: "PreToolUse", matcher: nil, statusMessage: "Updating pet Codex tool state"),
            Event(name: "PostToolUse", matcher: nil, statusMessage: "Updating pet Codex tool result"),
            Event(name: "PermissionRequest", matcher: "*", statusMessage: "Updating pet Codex approval state"),
            Event(name: "Stop", matcher: nil, statusMessage: "Updating pet Codex completion state")
        ]
    }
}
