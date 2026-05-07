import Foundation

enum AgentHookSource: String, Codable, Equatable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case opencode
}

struct AgentHookEnvironment: Codable, Equatable, Sendable {
    var cwd: String?
    var parentProcessID: Int?
    var variables: [String: String]

    init(cwd: String? = nil, parentProcessID: Int? = nil, variables: [String: String] = [:]) {
        self.cwd = cwd
        self.parentProcessID = parentProcessID
        self.variables = variables
    }
}

struct AgentTerminalContext: Codable, Equatable, Sendable {
    var tty: String?
    var termProgram: String?
    var bundleIdentifier: String?
    var iTermSessionID: String?
    var termSessionID: String?
    var tmux: String?
    var tmuxPane: String?
    var kittyWindowID: String?
    var kittyListenOn: String?
    var sshConnection: String?
    var sshTTY: String?
    var vscodeIPC: String?
    var cursorIPC: String?

    init(
        tty: String? = nil,
        termProgram: String? = nil,
        bundleIdentifier: String? = nil,
        iTermSessionID: String? = nil,
        termSessionID: String? = nil,
        tmux: String? = nil,
        tmuxPane: String? = nil,
        kittyWindowID: String? = nil,
        kittyListenOn: String? = nil,
        sshConnection: String? = nil,
        sshTTY: String? = nil,
        vscodeIPC: String? = nil,
        cursorIPC: String? = nil
    ) {
        self.tty = tty
        self.termProgram = termProgram
        self.bundleIdentifier = bundleIdentifier
        self.iTermSessionID = iTermSessionID
        self.termSessionID = termSessionID
        self.tmux = tmux
        self.tmuxPane = tmuxPane
        self.kittyWindowID = kittyWindowID
        self.kittyListenOn = kittyListenOn
        self.sshConnection = sshConnection
        self.sshTTY = sshTTY
        self.vscodeIPC = vscodeIPC
        self.cursorIPC = cursorIPC
    }
}

struct AgentHookEnvelope: Codable, Equatable, Sendable {
    var source: AgentHookSource
    var receivedAt: Date
    var rawPayload: JSONValue
    var arguments: [String]
    var environment: AgentHookEnvironment
    var terminal: AgentTerminalContext
    var metadata: [String: JSONValue]

    static let defaultMaxBodyBytes = 64 * 1024
    static let socketEnvironmentKey = "GLOBAL_PET_AGENT_SOCKET"

    static func make(
        source: AgentHookSource,
        arguments: [String],
        stdinData: Data,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        receivedAt: Date = Date(),
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        parentProcessID: Int? = Int(getppid()),
        tty: String? = nil
    ) throws -> AgentHookEnvelope {
        let rawPayload = try decodeRawPayload(stdinData)
        let cwd = firstString(in: rawPayload, keys: ["cwd", "current_working_directory", "workspace"]) ?? environment["PWD"] ?? currentDirectory
        let terminal = AgentTerminalContext(
            tty: firstString(in: rawPayload, keys: ["tty"]) ?? tty ?? environment["TTY"],
            termProgram: environment["TERM_PROGRAM"],
            bundleIdentifier: environment["__CFBundleIdentifier"],
            iTermSessionID: environment["ITERM_SESSION_ID"],
            termSessionID: environment["TERM_SESSION_ID"],
            tmux: environment["TMUX"],
            tmuxPane: environment["TMUX_PANE"],
            kittyWindowID: environment["KITTY_WINDOW_ID"],
            kittyListenOn: environment["KITTY_LISTEN_ON"],
            sshConnection: environment["SSH_CONNECTION"],
            sshTTY: environment["SSH_TTY"],
            vscodeIPC: environment["VSCODE_IPC_HOOK_CLI"],
            cursorIPC: environment["CURSOR_IPC_HOOK_CLI"]
        )
        let selectedEnvironment = selectedEnvironment(from: environment)
        var metadata = metadataFromPayload(rawPayload)
        metadata["cwd"] = .string(cwd)
        metadata["parent_process_id"] = parentProcessID.map { .number(Double($0)) }
        metadata["tty"] = terminal.tty.map { .string($0) }
        metadata["term_program"] = terminal.termProgram.map { .string($0) }
        metadata["bundle_identifier"] = terminal.bundleIdentifier.map { .string($0) }
        metadata["tmux_pane"] = terminal.tmuxPane.map { .string($0) }
        metadata["kitty_window_id"] = terminal.kittyWindowID.map { .string($0) }

        return AgentHookEnvelope(
            source: source,
            receivedAt: receivedAt,
            rawPayload: rawPayload,
            arguments: arguments,
            environment: AgentHookEnvironment(
                cwd: cwd,
                parentProcessID: parentProcessID,
                variables: selectedEnvironment
            ),
            terminal: terminal,
            metadata: metadata
        )
    }

    static func encodeLine(_ envelope: AgentHookEnvelope, encoder: JSONEncoder = newlineEncoder()) throws -> Data {
        var data = try encoder.encode(envelope)
        data.append(0x0A)
        return data
    }

    static func decodeLine(
        _ data: Data,
        maxBodyBytes: Int = defaultMaxBodyBytes,
        decoder: JSONDecoder = newlineDecoder()
    ) throws -> AgentHookEnvelope {
        guard data.count <= maxBodyBytes else {
            throw AgentHookEnvelopeError.payloadTooLarge
        }
        let trimmed = data.trimmingTrailingNewlines()
        guard !trimmed.isEmpty else {
            throw AgentHookEnvelopeError.invalidJSON
        }
        do {
            return try decoder.decode(AgentHookEnvelope.self, from: trimmed)
        } catch {
            throw AgentHookEnvelopeError.invalidJSON
        }
    }

    static func decodeRawPayload(_ data: Data) throws -> JSONValue {
        guard !data.trimmingTrailingNewlines().isEmpty else {
            return .object([:])
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            return JSONValue.fromJSONCompatible(object)
        } catch {
            throw AgentHookEnvelopeError.invalidJSON
        }
    }

    static func newlineEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func newlineDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func selectedEnvironment(from environment: [String: String]) -> [String: String] {
        let keys = [
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
            "CODEX_CONVERSATION_ID"
        ]
        return keys.reduce(into: [:]) { result, key in
            if let value = environment[key], !value.isEmpty {
                result[key] = value
            }
        }
    }

    private static func metadataFromPayload(_ payload: JSONValue) -> [String: JSONValue] {
        let pathKeys = [
            "transcript_path",
            "rollout_path",
            "session_file_path",
            "session_path"
        ]
        return pathKeys.reduce(into: [:]) { result, key in
            if let value = firstString(in: payload, keys: [key]) {
                result[key] = .string(value)
            }
        }
    }

    static func firstString(in value: JSONValue, keys: [String]) -> String? {
        guard let object = value.objectValue else {
            return nil
        }
        for key in keys {
            if let string = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !string.isEmpty {
                return string
            }
        }
        return nil
    }
}

enum AgentHookEnvelopeError: Error, Equatable, CustomStringConvertible {
    case invalidJSON
    case payloadTooLarge

    var description: String {
        switch self {
        case .invalidJSON:
            return "Agent hook envelope is not valid JSON."
        case .payloadTooLarge:
            return "Agent hook envelope exceeds the body size limit."
        }
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
