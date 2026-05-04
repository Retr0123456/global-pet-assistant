import Foundation

struct PetctlAction: Encodable {
    var type: String
    var url: String? = nil
    var path: String? = nil
    var bundleId: String? = nil
}

struct PetctlEvent: Encodable {
    var source = "petctl"
    var type: String
    var level: String? = nil
    var title: String? = nil
    var message: String? = nil
    var state: String? = nil
    var ttlMs: Int? = nil
    var dedupeKey: String? = nil
    var action: PetctlAction? = nil
}

struct PetctlRequest {
    var event: PetctlEvent
    var timeoutSeconds: TimeInterval
}

enum PetctlCommand {
    case send(PetctlRequest)
    case openFolder
    case openLogs
    case importCodexPet(String)
}

enum PetctlError: Error, CustomStringConvertible {
    case usage(String)
    case requestFailed(String)

    var description: String {
        switch self {
        case .usage(let message):
            message
        case .requestFailed(let message):
            message
        }
    }
}

private let allowedLevels: Set<String> = [
    "info",
    "running",
    "success",
    "warning",
    "danger"
]

private let allowedStates: Set<String> = [
    "idle",
    "running",
    "waiting",
    "failed",
    "review",
    "jumping",
    "waving",
    "running-left",
    "running-right"
]

private let usage = """
Usage:
  petctl notify --level success --title "Task complete" [--source codex-cli] [--message "..."] [--action-url https://github.com/example/global-pet-assistant] [--action-file ~/.global-pet-assistant/logs/local-build-latest.log] [--action-app com.openai.codex] [--timeout 5]
  petctl state running --message "Working..." [--source codex-cli] [--ttl-ms 15000] [--timeout 5]
  petctl clear [--source codex-cli] [--timeout 5]
  petctl open-folder
  petctl open-logs
  petctl import-codex-pet <name>

Commands:
  notify            Send a notification event. Levels: info, running, success, warning, danger.
  state             Switch directly to a pet state: idle, running, waiting, failed, review, jumping, waving, running-left, running-right.
  clear             Clear active events and return the pet to idle.
  open-folder       Open ~/.global-pet-assistant/pets in Finder.
  open-logs         Open ~/.global-pet-assistant/logs in Finder.
  import-codex-pet  Copy pet.json and the referenced spritesheet from ~/.codex/pets/<name>.
"""

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    let command = try parse(arguments)
    try run(command)
} catch {
    fputs("\(String(describing: error))\n\n\(usage)\n", stderr)
    exit(1)
}

private func parse(_ arguments: [String]) throws -> PetctlCommand {
    guard let command = arguments.first else {
        throw PetctlError.usage("Missing command.")
    }

    switch command {
    case "notify":
        var options = try parseOptions(Array(arguments.dropFirst()))
        let timeoutSeconds = try takeTimeout(from: &options)
        let source = options.removeValue(forKey: "source") ?? "petctl"
        let level = options.removeValue(forKey: "level") ?? "info"
        guard allowedLevels.contains(level) else {
            throw PetctlError.usage("Invalid level: \(level).")
        }
        let action = try takeAction(from: &options)

        let title = options.removeValue(forKey: "title")
        let event = PetctlEvent(
            source: source,
            type: options.removeValue(forKey: "type") ?? "notify",
            level: level,
            title: title,
            message: options.removeValue(forKey: "message"),
            ttlMs: try takeTTL(from: &options),
            dedupeKey: options.removeValue(forKey: "dedupe-key"),
            action: action
        )
        try rejectUnknownOptions(options)
        return .send(PetctlRequest(event: event, timeoutSeconds: timeoutSeconds))
    case "state":
        guard arguments.count >= 2 else {
            throw PetctlError.usage("Missing state name.")
        }

        let state = arguments[1]
        guard allowedStates.contains(state) else {
            throw PetctlError.usage("Invalid state: \(state).")
        }

        var options = try parseOptions(Array(arguments.dropFirst(2)))
        let timeoutSeconds = try takeTimeout(from: &options)
        let source = options.removeValue(forKey: "source") ?? "petctl"
        let event = PetctlEvent(
            source: source,
            type: options.removeValue(forKey: "type") ?? "state",
            message: options.removeValue(forKey: "message"),
            state: state,
            ttlMs: try takeTTL(from: &options),
            dedupeKey: options.removeValue(forKey: "dedupe-key")
        )
        try rejectUnknownOptions(options)
        return .send(PetctlRequest(event: event, timeoutSeconds: timeoutSeconds))
    case "clear":
        var options = try parseOptions(Array(arguments.dropFirst()))
        let timeoutSeconds = try takeTimeout(from: &options)
        let source = options.removeValue(forKey: "source") ?? "petctl"
        let event = PetctlEvent(
            source: source,
            type: "clear",
            state: "idle"
        )
        try rejectUnknownOptions(options)
        return .send(PetctlRequest(event: event, timeoutSeconds: timeoutSeconds))
    case "open-folder":
        guard arguments.count == 1 else {
            throw PetctlError.usage("open-folder does not accept arguments.")
        }

        return .openFolder
    case "open-logs":
        guard arguments.count == 1 else {
            throw PetctlError.usage("open-logs does not accept arguments.")
        }

        return .openLogs
    case "import-codex-pet":
        guard arguments.count == 2 else {
            throw PetctlError.usage("Usage: petctl import-codex-pet <name>.")
        }

        return .importCodexPet(arguments[1])
    case "help", "--help", "-h":
        print(usage)
        exit(0)
    default:
        throw PetctlError.usage("Unknown command: \(command).")
    }
}

private func run(_ command: PetctlCommand) throws {
    switch command {
    case .send(let request):
        try send(request)
    case .openFolder:
        try openPetFolder()
    case .openLogs:
        try openLogsFolder()
    case .importCodexPet(let name):
        try importCodexPet(named: name)
    }
}

private func parseOptions(_ arguments: [String]) throws -> [String: String] {
    var options: [String: String] = [:]
    var index = 0

    while index < arguments.count {
        let rawKey = arguments[index]
        guard rawKey.hasPrefix("--") else {
            throw PetctlError.usage("Unexpected argument: \(rawKey).")
        }

        let key = String(rawKey.dropFirst(2))
        guard index + 1 < arguments.count else {
            throw PetctlError.usage("Missing value for \(rawKey).")
        }

        options[key] = arguments[index + 1]
        index += 2
    }

    return options
}

private func takeTTL(from options: inout [String: String]) throws -> Int? {
    guard let rawTTL = options.removeValue(forKey: "ttl-ms") else {
        return nil
    }

    guard let ttlMs = Int(rawTTL), ttlMs >= 0 else {
        throw PetctlError.usage("Invalid --ttl-ms value: \(rawTTL).")
    }

    return ttlMs
}

private func takeTimeout(from options: inout [String: String]) throws -> TimeInterval {
    guard let rawTimeout = options.removeValue(forKey: "timeout") else {
        return 5
    }

    guard let timeout = TimeInterval(rawTimeout), timeout > 0 else {
        throw PetctlError.usage("Invalid --timeout value: \(rawTimeout).")
    }

    return timeout
}

private func takeAction(from options: inout [String: String]) throws -> PetctlAction? {
    let actionURL = options.removeValue(forKey: "action-url")
    let actionFolder = options.removeValue(forKey: "action-folder")
    let actionFile = options.removeValue(forKey: "action-file")
    let actionApp = options.removeValue(forKey: "action-app")
    let actionCount = [actionURL, actionFolder, actionFile, actionApp].compactMap { $0 }.count
    guard actionCount <= 1 else {
        throw PetctlError.usage("Use only one action option: --action-url, --action-folder, --action-file, or --action-app.")
    }

    if let actionURL {
        return PetctlAction(type: "open_url", url: actionURL)
    }

    if let actionFolder {
        return PetctlAction(type: "open_folder", path: actionFolder)
    }

    if let actionFile {
        return PetctlAction(type: "open_file", path: actionFile)
    }

    if let actionApp {
        return PetctlAction(type: "open_app", bundleId: actionApp)
    }

    return nil
}

private func rejectUnknownOptions(_ options: [String: String]) throws {
    guard let unknownOption = options.keys.sorted().first else {
        return
    }

    throw PetctlError.usage("Unknown option: --\(unknownOption).")
}

private func openPetFolder() throws {
    let appPetsDirectory = appPetsDirectoryURL()
    try FileManager.default.createDirectory(
        at: appPetsDirectory,
        withIntermediateDirectories: true
    )

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [appPetsDirectory.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw PetctlError.requestFailed("Could not open \(appPetsDirectory.path).")
    }
}

private func openLogsFolder() throws {
    let logsDirectory = logsDirectoryURL()
    try FileManager.default.createDirectory(
        at: logsDirectory,
        withIntermediateDirectories: true
    )

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [logsDirectory.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw PetctlError.requestFailed("Could not open \(logsDirectory.path).")
    }
}

private func importCodexPet(named name: String) throws {
    let safeName = try validatedPetName(name)
    let sourceDirectory = codexPetsDirectoryURL().appendingPathComponent(safeName, isDirectory: true)
    let destinationDirectory = appPetsDirectoryURL().appendingPathComponent(safeName, isDirectory: true)
    let sourceManifestURL = sourceDirectory.appendingPathComponent("pet.json")
    let manifestData = try Data(contentsOf: sourceManifestURL)
    let spritesheetPath = try spritesheetPath(fromManifestData: manifestData)
    let sourceSpritesheetURL = sourceDirectory.appendingPathComponent(spritesheetPath)

    guard FileManager.default.fileExists(atPath: sourceSpritesheetURL.path) else {
        throw PetctlError.requestFailed("Missing source spritesheet: \(sourceSpritesheetURL.path).")
    }

    try FileManager.default.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: true
    )
    try replaceCopy(
        from: sourceManifestURL,
        to: destinationDirectory.appendingPathComponent("pet.json")
    )
    try replaceCopy(
        from: sourceSpritesheetURL,
        to: destinationDirectory.appendingPathComponent(spritesheetPath)
    )

    print("Imported \(safeName) to \(destinationDirectory.path)")
}

private func validatedPetName(_ name: String) throws -> String {
    guard
        !name.isEmpty,
        !name.contains("/"),
        !name.contains(".."),
        name == URL(fileURLWithPath: name).lastPathComponent
    else {
        throw PetctlError.usage("Invalid pet name: \(name).")
    }

    return name
}

private func spritesheetPath(fromManifestData data: Data) throws -> String {
    guard
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let path = object["spritesheetPath"] as? String,
        !path.isEmpty,
        !path.hasPrefix("/"),
        !path.contains(".."),
        path == URL(fileURLWithPath: path).lastPathComponent
    else {
        throw PetctlError.requestFailed("pet.json must contain a safe spritesheetPath filename.")
    }

    return path
}

private func replaceCopy(from sourceURL: URL, to destinationURL: URL) throws {
    if FileManager.default.fileExists(atPath: destinationURL.path) {
        try FileManager.default.removeItem(at: destinationURL)
    }

    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
}

private func send(_ requestEnvelope: PetctlRequest) throws {
    let url = URL(string: "http://127.0.0.1:17321/events")!
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestEnvelope.timeoutSeconds
    configuration.timeoutIntervalForResource = requestEnvelope.timeoutSeconds

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(requestEnvelope.event)

    let semaphore = DispatchSemaphore(value: 0)
    let responseBox = ResponseBox()

    let task = URLSession(configuration: configuration).dataTask(with: request) { data, response, error in
        defer {
            semaphore.signal()
        }

        if let error {
            responseBox.result = .failure(error)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            responseBox.result = .failure(PetctlError.requestFailed("No HTTP response from local app."))
            return
        }

        responseBox.result = .success((data ?? Data(), httpResponse))
    }
    task.resume()

    let waitResult = semaphore.wait(timeout: .now() + requestEnvelope.timeoutSeconds)
    guard waitResult == .success else {
        task.cancel()
        throw PetctlError.requestFailed("Timed out after \(requestEnvelope.timeoutSeconds) seconds waiting for local app.")
    }

    let (data, response) = try responseBox.result!.get()
    guard (200..<300).contains(response.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw PetctlError.requestFailed("Local app returned HTTP \(response.statusCode): \(body)")
    }

    if let body = String(data: data, encoding: .utf8), !body.isEmpty {
        print(body)
    }
}

private final class ResponseBox: @unchecked Sendable {
    var result: Result<(Data, HTTPURLResponse), Error>?
}

private func appPetsDirectoryURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".global-pet-assistant", isDirectory: true)
        .appendingPathComponent("pets", isDirectory: true)
}

private func logsDirectoryURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".global-pet-assistant", isDirectory: true)
        .appendingPathComponent("logs", isDirectory: true)
}

private func codexPetsDirectoryURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex", isDirectory: true)
        .appendingPathComponent("pets", isDirectory: true)
}
