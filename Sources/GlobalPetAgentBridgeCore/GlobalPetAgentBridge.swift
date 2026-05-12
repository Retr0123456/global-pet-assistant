import Darwin
import Foundation

public enum GlobalPetAgentBridgeError: Error, Equatable, CustomStringConvertible {
    case unsupportedSource(String)
    case missingSource
    case invalidJSON
    case socketUnavailable(String)

    public var description: String {
        switch self {
        case .unsupportedSource(let source):
            return "Unsupported agent hook source: \(source)."
        case .missingSource:
            return "Missing --source argument."
        case .invalidJSON:
            return "Hook stdin was not valid JSON."
        case .socketUnavailable(let message):
            return "Agent hook socket unavailable: \(message)."
        }
    }
}

public enum GlobalPetAgentBridge {
    public static let socketEnvironmentKey = "GLOBAL_PET_AGENT_SOCKET"
    public static let disableEnvironmentKey = "GLOBAL_PET_ASSISTANT_DISABLE_CODEX_HOOKS"
    public static let disableAgentHooksEnvironmentKey = "GLOBAL_PET_ASSISTANT_DISABLE_AGENT_HOOKS"
    public static let defaultSocketPath = "\(NSHomeDirectory())/.global-pet-assistant/run/agent-hooks.sock"
    public static let auditLogPath = "\(NSHomeDirectory())/.global-pet-assistant/logs/agent-hooks.jsonl"

    private static let selectedEnvironmentKeys = [
        "PWD",
        "TTY",
        "TERM_PROGRAM",
        "__CFBundleIdentifier",
        "ITERM_SESSION_ID",
        "TERM_SESSION_ID",
        "TMUX",
        "TMUX_PANE",
        "KITTY_WINDOW_ID",
        "KITTY_LISTEN_ON",
        "SSH_CONNECTION",
        "SSH_TTY",
        "VSCODE_IPC_HOOK_CLI",
        "CURSOR_IPC_HOOK_CLI",
        "CODEX_SESSION_ID",
        "CODEX_THREAD_ID",
        "CODEX_CONVERSATION_ID",
        "CLAUDE_SESSION_ID",
        "CLAUDE_CONVERSATION_ID"
    ]

    public static func parseSource(arguments: [String]) throws -> String {
        for (index, argument) in arguments.enumerated() {
            if argument == "--source", index + 1 < arguments.count {
                return try normalizedSource(arguments[index + 1])
            }
            if argument.hasPrefix("--source=") {
                return try normalizedSource(String(argument.dropFirst("--source=".count)))
            }
        }
        throw GlobalPetAgentBridgeError.missingSource
    }

    public static func makeEnvelopeLine(
        source: String,
        arguments: [String],
        stdinData: Data,
        environment: [String: String],
        receivedAt: Date = Date(),
        currentDirectory: String,
        parentProcessID: Int?,
        tty: String?
    ) throws -> Data {
        let rawPayload: Any
        if stdinData.trimmingTrailingNewlines().isEmpty {
            rawPayload = [String: Any]()
        } else {
            do {
                rawPayload = try JSONSerialization.jsonObject(with: stdinData, options: [])
            } catch {
                throw GlobalPetAgentBridgeError.invalidJSON
            }
        }

        let rawObject = rawPayload as? [String: Any] ?? [:]
        let cwd = firstString(rawObject, keys: ["cwd", "current_working_directory", "workspace"])
            ?? environment["PWD"]
            ?? currentDirectory
        let terminal: [String: Any?] = [
            "tty": firstString(rawObject, keys: ["tty"]) ?? tty ?? environment["TTY"],
            "termProgram": environment["TERM_PROGRAM"],
            "bundleIdentifier": environment["__CFBundleIdentifier"],
            "iTermSessionID": environment["ITERM_SESSION_ID"],
            "termSessionID": environment["TERM_SESSION_ID"],
            "tmux": environment["TMUX"],
            "tmuxPane": environment["TMUX_PANE"],
            "kittyWindowID": environment["KITTY_WINDOW_ID"],
            "kittyListenOn": environment["KITTY_LISTEN_ON"],
            "sshConnection": environment["SSH_CONNECTION"],
            "sshTTY": environment["SSH_TTY"],
            "vscodeIPC": environment["VSCODE_IPC_HOOK_CLI"],
            "cursorIPC": environment["CURSOR_IPC_HOOK_CLI"]
        ]
        var metadata: [String: Any] = [
            "cwd": cwd
        ]
        if let parentProcessID {
            metadata["parent_process_id"] = parentProcessID
        }
        if let tty = terminal["tty"] as? String {
            metadata["tty"] = tty
        }
        for key in ["transcript_path", "rollout_path", "session_file_path", "session_path"] {
            if let value = firstString(rawObject, keys: [key]) {
                metadata[key] = value
            }
        }

        let envelope: [String: Any] = [
            "source": source,
            "receivedAt": bridgeTimestamp(receivedAt),
            "rawPayload": rawPayload,
            "arguments": arguments,
            "environment": [
                "cwd": cwd,
                "parentProcessID": parentProcessID as Any,
                "variables": selectedEnvironment(from: environment)
            ].compactMapValues { $0 },
            "terminal": terminal.compactMapValues { $0 },
            "metadata": metadata
        ]

        var data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }

    public static func run(
        arguments: [String],
        stdinData: Data,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        parentProcessID: Int? = Int(getppid()),
        tty: String? = detectTTY(),
        send: (Data, String) throws -> Void = sendEnvelope,
        appendAudit: (Data) -> Void = appendAuditLine
    ) -> Int32 {
        do {
            let source = try parseSource(arguments: arguments)
            if environment[disableAgentHooksEnvironmentKey] == "1" || (source == "codex" && environment[disableEnvironmentKey] == "1") {
                return 0
            }
            let line = try makeEnvelopeLine(
                source: source,
                arguments: arguments,
                stdinData: stdinData,
                environment: environment,
                currentDirectory: currentDirectory,
                parentProcessID: parentProcessID,
                tty: tty
            )
            appendAudit(line)
            do {
                try send(line, environment[socketEnvironmentKey] ?? defaultSocketPath)
            } catch {
                return 0
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data((String(describing: error) + "\n").utf8))
            return 2
        }
    }

    public static func sendEnvelope(_ data: Data, socketPath: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw GlobalPetAgentBridgeError.socketUnavailable(String(cString: strerror(errno)))
        }
        defer {
            close(fd)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw GlobalPetAgentBridgeError.socketUnavailable("socket path too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { pointer in
            for (index, byte) in pathBytes.enumerated() {
                pointer[index] = byte
            }
            pointer[pathBytes.count] = 0
        }

        let length = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count + 1)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, length)
            }
        }
        guard connectResult == 0 else {
            throw GlobalPetAgentBridgeError.socketUnavailable(String(cString: strerror(errno)))
        }

        try data.withUnsafeBytes { pointer in
            guard let baseAddress = pointer.baseAddress else {
                return
            }
            let sent = Darwin.send(fd, baseAddress, data.count, 0)
            guard sent == data.count else {
                throw GlobalPetAgentBridgeError.socketUnavailable(String(cString: strerror(errno)))
            }
        }
    }

    public static func appendAuditLine(_ line: Data) {
        do {
            let logURL = URL(fileURLWithPath: auditLogPath)
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: logURL, options: [.atomic])
            }
        } catch {
            return
        }
    }

    public static func detectTTY() -> String? {
        guard let pointer = ttyname(STDIN_FILENO) else {
            return nil
        }
        return String(cString: pointer)
    }

    private static func normalizedSource(_ source: String) throws -> String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "codex":
            return "codex"
        case "claude-code", "claude_code":
            return "claude-code"
        default:
            throw GlobalPetAgentBridgeError.unsupportedSource(source)
        }
    }

    private static func selectedEnvironment(from environment: [String: String]) -> [String: String] {
        selectedEnvironmentKeys.reduce(into: [:]) { result, key in
            if let value = environment[key], !value.isEmpty {
                result[key] = value
            }
        }
    }

    private static func firstString(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func bridgeTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private extension Data {
    func trimmingTrailingNewlines() -> Data {
        var end = count
        while end > 0, self[end - 1] == 0x0A || self[end - 1] == 0x0D {
            end -= 1
        }
        return subdata(in: 0..<end)
    }
}
