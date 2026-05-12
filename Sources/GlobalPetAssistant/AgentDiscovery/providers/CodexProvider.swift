import Foundation

struct CodexProvider: AgentProvider {
    let kind: AgentKind = .codex

    func sessionUpdate(from candidate: AgentDiscoveryCandidate) -> AgentSessionUpdate? {
        nil
    }

    func sessionUpdate(from envelope: AgentHookEnvelope) -> AgentSessionUpdate? {
        guard envelope.source == .codex else {
            return nil
        }

        let hookName = Self.string(in: envelope.rawPayload, keys: ["hook_event_name", "hookEventName"])
            ?? envelope.metadata["hook_event_name"]?.stringValue
            ?? "Unknown"
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
        if let subagentSessionID = subagentSessionID(envelope.rawPayload, canonicalID: sessionID) {
            metadata["subagent_session_id"] = .string(subagentSessionID)
        }
        if let parentThreadID = parentThreadID(envelope.rawPayload) {
            metadata["parent_thread_id"] = .string(parentThreadID)
        }

        return AgentSessionUpdate(
            id: sessionID,
            kind: .codex,
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

    func sessionUpdate(from terminalEvent: TerminalPluginEvent) -> AgentSessionUpdate? {
        guard terminalEvent.providerHint == .codex else {
            return nil
        }

        let sessionKey = [
            terminalEvent.terminal.sessionId,
            terminalEvent.terminal.windowId ?? "",
            terminalEvent.terminal.cwd ?? ""
        ].joined(separator: "|")
        let sessionID = "terminal-\(Self.stableHash(sessionKey))"
        var metadata: [String: JSONValue] = [
            "identity_source": .string("terminal_plugin"),
            "terminal_kind": .string(terminalEvent.terminal.kind.rawValue),
            "terminal_session_id": .string(terminalEvent.terminal.sessionId)
        ]
        metadata["terminal_window_id"] = terminalEvent.terminal.windowId.map { .string($0) }
        metadata["terminal_tab_id"] = terminalEvent.terminal.tabId.map { .string($0) }
        metadata["terminal_control_endpoint"] = terminalEvent.terminal.controlEndpoint.map { .string($0) }

        let status: AgentStatus = terminalEvent.exitCode.map { $0 == 0 ? .completed : .failed } ?? .running
        let terminalCapabilities = terminalPluginCapabilities(for: terminalEvent.terminal)
        return AgentSessionUpdate(
            id: sessionID,
            kind: .codex,
            status: status,
            capabilityRoutes: [.terminalPlugin: terminalCapabilities],
            observedAt: terminalEvent.occurredAt,
            sourceStrength: .terminalPlugin,
            cwd: terminalEvent.terminal.cwd,
            title: status == .completed ? "Codex completed" : "Codex session",
            message: terminalEvent.command,
            metadata: metadata
        )
    }

    private func terminalPluginCapabilities(for context: TerminalSessionContext) -> Set<AgentCapability> {
        do {
            _ = try KittyTargetResolver().resolve(context)
            return [.observe, .focus]
        } catch {
            return [.observe]
        }
    }

    private func canonicalSessionID(envelope: AgentHookEnvelope) -> String {
        if let parentThreadID = parentThreadID(envelope.rawPayload) {
            return parentThreadID
        }

        if let payloadID = Self.string(
            in: envelope.rawPayload,
            keys: [
                "session_id",
                "sessionId",
                "thread_id",
                "threadId",
                "conversation_id",
                "conversationId"
            ]
        ) {
            return payloadID
        }

        for key in ["CODEX_SESSION_ID", "CODEX_THREAD_ID", "CODEX_CONVERSATION_ID"] {
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

        return "cwd-\(Self.stableHash(cwd(envelope: envelope) ?? "codex"))"
    }

    private func identitySource(envelope: AgentHookEnvelope) -> String {
        if parentThreadID(envelope.rawPayload) != nil {
            return "parent_thread_id"
        }
        if Self.string(in: envelope.rawPayload, keys: ["session_id", "sessionId"]) != nil {
            return "session_id"
        }
        if Self.string(in: envelope.rawPayload, keys: ["thread_id", "threadId"]) != nil {
            return "thread_id"
        }
        if Self.string(in: envelope.rawPayload, keys: ["conversation_id", "conversationId"]) != nil {
            return "conversation_id"
        }
        if ["CODEX_SESSION_ID", "CODEX_THREAD_ID", "CODEX_CONVERSATION_ID"].contains(where: { envelope.environment.variables[$0] != nil }) {
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
        case "UserPromptSubmit", "PreToolUse", "PostToolUse":
            return .running
        case "PermissionRequest":
            return .waiting
        case "Stop":
            return .completed
        default:
            return .unknown
        }
    }

    private func title(for hookName: String, envelope: AgentHookEnvelope) -> String? {
        switch hookName {
        case "SessionStart":
            return "Codex session"
        case "UserPromptSubmit":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["prompt", "user_prompt", "message"]), limit: 80)
        case "PreToolUse":
            return toolName(envelope.rawPayload).map { "Using \($0)" }
        case "PostToolUse":
            return toolName(envelope.rawPayload).map { "Finished \($0)" }
        case "PermissionRequest":
            return "Needs approval"
        case "Stop":
            return "Codex completed"
        default:
            return nil
        }
    }

    private func message(for hookName: String, envelope: AgentHookEnvelope) -> String? {
        switch hookName {
        case "UserPromptSubmit":
            return Self.truncate(Self.string(in: envelope.rawPayload, keys: ["prompt", "user_prompt", "message"]), limit: 160)
        case "PreToolUse":
            return toolInputPreview(envelope.rawPayload)
        case "PostToolUse":
            return toolResultPreview(envelope.rawPayload) ?? toolInputPreview(envelope.rawPayload)
        case "PermissionRequest":
            return pendingPermissionDescription(for: hookName, envelope: envelope)
        case "Stop":
            return "Codex session completed"
        default:
            return nil
        }
    }

    private func pendingPermissionDescription(for hookName: String, envelope: AgentHookEnvelope) -> String? {
        guard hookName == "PermissionRequest" else {
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

    private func parentThreadID(_ payload: JSONValue) -> String? {
        nestedString(payload, path: ["session_meta", "parent_thread_id"])
            ?? nestedString(payload, path: ["session_meta", "payload", "parent_thread_id"])
            ?? nestedString(payload, path: ["metadata", "parent_thread_id"])
    }

    private func subagentSessionID(_ payload: JSONValue, canonicalID: String) -> String? {
        let payloadID = Self.string(in: payload, keys: ["session_id", "sessionId", "thread_id", "threadId"])
        guard let payloadID, payloadID != canonicalID else {
            return nil
        }
        return payloadID
    }

    private func terminalMetadata(_ terminal: AgentTerminalContext) -> JSONValue {
        var object: [String: JSONValue] = [:]
        object["tty"] = terminal.tty.map { .string($0) }
        object["term_program"] = terminal.termProgram.map { .string($0) }
        object["bundle_identifier"] = terminal.bundleIdentifier.map { .string($0) }
        object["iterm_session_id"] = terminal.iTermSessionID.map { .string($0) }
        object["term_session_id"] = terminal.termSessionID.map { .string($0) }
        object["tmux"] = terminal.tmux.map { .string($0) }
        object["tmux_pane"] = terminal.tmuxPane.map { .string($0) }
        object["kitty_window_id"] = terminal.kittyWindowID.map { .string($0) }
        object["kitty_listen_on"] = terminal.kittyListenOn.map { .string($0) }
        object["ssh_connection"] = terminal.sshConnection.map { .string($0) }
        object["ssh_tty"] = terminal.sshTTY.map { .string($0) }
        return .object(object)
    }

    private func nestedString(_ value: JSONValue, path: [String]) -> String? {
        guard let finalValue = nestedValue(value, path: path) else {
            return nil
        }
        return finalValue.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nestedObject(_ value: JSONValue, path: [String]) -> JSONValue? {
        nestedValue(value, path: path)
    }

    private func nestedValue(_ value: JSONValue, path: [String]) -> JSONValue? {
        var current = value
        for key in path {
            guard let next = current.objectValue?[key] else {
                return nil
            }
            current = next
        }
        return current
    }

    private static func string(in value: JSONValue, keys: [String]) -> String? {
        AgentHookEnvelope.firstString(in: value, keys: keys)
    }

    private static func truncate(_ value: String?, limit: Int) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard normalized.count > limit else {
            return normalized
        }
        return String(normalized.prefix(limit - 3)) + "..."
    }

    private static func stableHash(_ value: String) -> String {
        let hash = value.unicodeScalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
            (partial ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func renderJSON(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }
}
