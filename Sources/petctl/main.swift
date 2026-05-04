import Foundation

struct PetctlEvent: Encodable {
    var source = "petctl"
    var type: String
    var level: String?
    var title: String?
    var message: String?
    var state: String?
    var ttlMs: Int?
    var dedupeKey: String?
}

struct PetctlRequest {
    var event: PetctlEvent
    var timeoutSeconds: TimeInterval
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
  petctl notify --level success --title "Task complete" [--source codex-cli] [--message "..."] [--timeout 5]
  petctl state running --message "Working..." [--source codex-cli] [--ttl-ms 15000] [--timeout 5]
  petctl clear [--source codex-cli] [--timeout 5]

Commands:
  notify  Send a notification event. Levels: info, running, success, warning, danger.
  state   Switch directly to a pet state: idle, running, waiting, failed, review, jumping, waving, running-left, running-right.
  clear   Clear active events and return the pet to idle.
"""

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    let request = try parse(arguments)
    try send(request)
} catch {
    fputs("\(String(describing: error))\n\n\(usage)\n", stderr)
    exit(1)
}

private func parse(_ arguments: [String]) throws -> PetctlRequest {
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

        let title = options.removeValue(forKey: "title")
        let event = PetctlEvent(
            source: source,
            type: options.removeValue(forKey: "type") ?? "notify",
            level: level,
            title: title,
            message: options.removeValue(forKey: "message"),
            ttlMs: try takeTTL(from: &options),
            dedupeKey: options.removeValue(forKey: "dedupe-key")
        )
        try rejectUnknownOptions(options)
        return PetctlRequest(event: event, timeoutSeconds: timeoutSeconds)
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
        return PetctlRequest(event: event, timeoutSeconds: timeoutSeconds)
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
        return PetctlRequest(event: event, timeoutSeconds: timeoutSeconds)
    case "help", "--help", "-h":
        print(usage)
        exit(0)
    default:
        throw PetctlError.usage("Unknown command: \(command).")
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

private func rejectUnknownOptions(_ options: [String: String]) throws {
    guard let unknownOption = options.keys.sorted().first else {
        return
    }

    throw PetctlError.usage("Unknown option: --\(unknownOption).")
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
