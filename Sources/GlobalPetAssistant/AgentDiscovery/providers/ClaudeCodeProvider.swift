import Foundation

struct ClaudeCodeProvider: AgentProvider {
    let kind: AgentKind = .claudeCode

    func sessionUpdate(from candidate: AgentDiscoveryCandidate) -> AgentSessionUpdate? {
        nil
    }

    func sessionUpdate(from envelope: AgentHookEnvelope) -> AgentSessionUpdate? {
        guard envelope.source == .claudeCode else {
            return nil
        }

        let hookName = Self.string(in: envelope.rawPayload, keys: ["hook_event_name", "hookEventName"]) ?? "Unknown"
        let sessionID = canonicalSessionID(envelope: envelope)
        let status = status(for: hookName)
        let title = title(for: hookName, envelope: envelope)
        let message = message(for: hookName, envelope: envelope)
        let pendingPermission = pendingPermissionDescription(for: hookName, envelope: envelope)
        var metadata = envelope.metadata
        metadata["hook_event_name"] = .string(hookName)
        metadata["identity_source"] = .string(identitySource(envelope: envelope))
        metadata["terminal_context"] = terminalMetadata(envelope.terminal)

        if let toolName = toolName(envelope.rawPayload) {
            metadata["tool_name"] = .string(toolName)
        }
        if let toolPreview = toolInputPreview(envelope.rawPayload) {
            metadata["tool_input_preview"] = .string(toolPreview)
        }

        return AgentSessionUpdate(
            id: sessionID,
            kind: .claudeCode,
            status: status,
            capabilities: [.observe],
            observedAt: envelope.receivedAt,
            sourceStrength: .hookEvent,
            cwd: cwd(envelope: envelope),
            tty: envelope.terminal.tty,
            tmuxPaneId: envelope.terminal.tmuxPane,
            title: title,
            message: message,
            pendingPermissionDescription: pendingPermission,
            metadata: metadata
        )
    }

    private func canonicalSessionID(envelope: AgentHookEnvelope) -> String {
        if let payloadID = Self.string(
            in: envelope.rawPayload,
            keys: [
                "session_id",
                "sessionId",
                "conversation_id",
                "conversationId"
            ]
        ) {
            return payloadID
        }

        for key in ["CLAUDE_SESSION_ID", "CLAUDE_CONVERSATION_ID"] {
            if let value = envelope.environment.variables[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        let terminalParts = [
            envelope.terminal.tmuxPane,
            envelope.terminal.termSessionID,
            envelope.terminal.iTermSessionID,
            envelope.terminal.kittyWindowID,
            envelope.terminal.tty
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !terminalParts.isEmpty {
            return "terminal-\(Self.stableHash(terminalParts.joined(separator: "|")))"
        }

        return "cwd-\(Self.stableHash(cwd(envelope: envelope) ?? "claude-code"))"
    }

    private func identitySource(envelope: AgentHookEnvelope) -> String {
        if Self.string(in: envelope.rawPayload, keys: ["session_id", "sessionId"]) != nil {
            return "session_id"
        }
        if Self.string(in: envelope.rawPayload, keys: ["conversation_id", "conversationId"]) != nil {
            return "conversation_id"
        }
        if ["CLAUDE_SESSION_ID", "CLAUDE_CONVERSATION_ID"].contains(where: { envelope.environment.variables[$0] != nil }) {
            return "environment"
        }
        if envelope.terminal.tty != nil || envelope.terminal.tmuxPane != nil || envelope.terminal.termSessionID != nil {
            return "terminal"
        }
        return "cwd"
    }

    private func status(for hookName: String) -> AgentStatus {
        switch hookName {
        case "SessionStart":
            return .started
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolBatch", "Notification", "SubagentStart", "TaskCreated":
            return .running
        case "PermissionRequest":
            return .waiting
        case "Stop", "SubagentStop", "TaskCompleted", "SessionEnd":
            return .completed
        case "PermissionDenied", "PostToolUseFailure", "StopFailure":
            return .failed
        default:
            return .unknown
        }
    }

    private func title(for hookName: String, envelope: AgentHookEnvelope) -> String? {
        switch hookName {
        case "SessionStart":
            return "Claude Code session"
        case "UserPromptSubmit":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["prompt", "message"]), limit: 80)
        case "PreToolUse":
            return toolName(envelope.rawPayload).map { "Using \($0)" }
        case "PostToolUse":
            return toolName(envelope.rawPayload).map { "Finished \($0)" }
        case "PostToolUseFailure":
            return toolName(envelope.rawPayload).map { "Failed \($0)" }
        case "PostToolBatch":
            return "Claude Code tools completed"
        case "PermissionRequest":
            return "Needs approval"
        case "PermissionDenied":
            return "Permission denied"
        case "Notification":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["message", "notification"]), limit: 80) ?? "Claude Code notification"
        case "SubagentStart":
            return "Claude Code subagent"
        case "SubagentStop":
            return "Claude Code subagent completed"
        case "Stop":
            return "Claude Code completed"
        case "StopFailure":
            return "Claude Code failed"
        case "SessionEnd":
            return "Claude Code session ended"
        default:
            return nil
        }
    }

    private func message(for hookName: String, envelope: AgentHookEnvelope) -> String? {
        switch hookName {
        case "UserPromptSubmit":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["prompt", "message"]), limit: 160)
        case "PreToolUse":
            return toolInputPreview(envelope.rawPayload)
        case "PostToolUse":
            return toolResultPreview(envelope.rawPayload) ?? toolInputPreview(envelope.rawPayload)
        case "PostToolUseFailure":
            return toolResultPreview(envelope.rawPayload) ?? toolInputPreview(envelope.rawPayload)
        case "PostToolBatch":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["summary", "message"]), limit: 160)
        case "PermissionRequest":
            return pendingPermissionDescription(for: hookName, envelope: envelope)
        case "PermissionDenied":
            return pendingPermissionDescription(for: hookName, envelope: envelope)
        case "Notification":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["message", "notification"]), limit: 160)
        case "SubagentStart":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["agent_name", "agentName", "agent_type", "agentType"]), limit: 160)
        case "SubagentStop":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["agent_name", "agentName", "agent_type", "agentType"]), limit: 160)
        case "Stop":
            return "Claude Code session completed"
        case "StopFailure":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["reason", "message", "error"]), limit: 160) ?? "Claude Code session failed"
        case "SessionEnd":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["reason", "message"]), limit: 160)
        default:
            return nil
        }
    }

    private func pendingPermissionDescription(for hookName: String, envelope: AgentHookEnvelope) -> String? {
        guard hookName == "PermissionRequest" || hookName == "PermissionDenied" else {
            return nil
        }

        let tool = toolName(envelope.rawPayload) ?? "Tool"
        if let command = nestedString(envelope.rawPayload, path: ["tool_input", "command"]) {
            return "\(tool) wants to run \(Self.truncate(command, limit: 120) ?? command)"
        }
        if let description = nestedString(envelope.rawPayload, path: ["tool_input", "description"]) {
            return "\(tool) needs approval: \(Self.truncate(description, limit: 120) ?? description)"
        }
        return "\(tool) needs approval"
    }

    private func cwd(envelope: AgentHookEnvelope) -> String? {
        Self.string(in: envelope.rawPayload, keys: ["cwd", "current_working_directory", "workspace"])
            ?? envelope.environment.cwd
            ?? envelope.environment.variables["PWD"]
    }

    private func toolName(_ payload: JSONValue) -> String? {
        Self.string(in: payload, keys: ["tool_name", "toolName", "tool"])
    }

    private func toolInputPreview(_ payload: JSONValue) -> String? {
        if let command = nestedString(payload, path: ["tool_input", "command"]) {
            return Self.truncate(command, limit: 160)
        }
        if let description = nestedString(payload, path: ["tool_input", "description"]) {
            return Self.truncate(description, limit: 160)
        }
        if let input = nestedObject(payload, path: ["tool_input"]) {
            return Self.truncate(Self.renderJSON(input), limit: 160)
        }
        return nil
    }

    private func toolResultPreview(_ payload: JSONValue) -> String? {
        Self.truncate(Self.string(in: payload, keys: ["result", "output", "tool_output", "summary"]), limit: 160)
    }

    private func terminalMetadata(_ terminal: AgentTerminalContext) -> JSONValue {
        var object: [String: JSONValue] = [:]
        object["tty"] = terminal.tty.map { .string($0) }
        object["termProgram"] = terminal.termProgram.map { .string($0) }
        object["tmuxPane"] = terminal.tmuxPane.map { .string($0) }
        object["kittyWindowID"] = terminal.kittyWindowID.map { .string($0) }
        object["kittyListenOn"] = terminal.kittyListenOn.map { .string($0) }
        return .object(object)
    }

    private static func string(in payload: JSONValue, keys: [String]) -> String? {
        guard case .object(let object) = payload else {
            return nil
        }
        let normalized = object.reduce(into: [String: JSONValue]()) { result, pair in
            result[normalize(pair.key)] = pair.value
        }
        for key in keys {
            guard let value = normalized[normalize(key)] else {
                continue
            }
            if case .string(let string) = value {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func nestedString(_ payload: JSONValue, path: [String]) -> String? {
        if case .string(let value) = nestedValue(payload, path: path) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func nestedObject(_ payload: JSONValue, path: [String]) -> JSONValue? {
        let value = nestedValue(payload, path: path)
        if case .object = value {
            return value
        }
        return nil
    }

    private func nestedValue(_ payload: JSONValue, path: [String]) -> JSONValue? {
        var current: JSONValue? = payload
        for key in path {
            guard case .object(let object) = current else {
                return nil
            }
            let normalized = object.reduce(into: [String: JSONValue]()) { result, pair in
                result[Self.normalize(pair.key)] = pair.value
            }
            current = normalized[Self.normalize(key)]
        }
        return current
    }

    private static func renderJSON(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "\(value)"
    }

    private static func truncate(_ value: String?, limit: Int) -> String? {
        guard let value else {
            return nil
        }
        if value.count <= limit {
            return value
        }
        return String(value.prefix(max(0, limit - 1))) + "..."
    }

    private static func stableHash(_ input: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func normalize(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "").lowercased()
    }
}
