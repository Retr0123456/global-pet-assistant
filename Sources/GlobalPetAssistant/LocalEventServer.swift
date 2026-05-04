import Darwin
import Foundation

final class LocalEventServer {
    static let defaultPort: UInt16 = 17321

    private let port: UInt16
    private let maxBodyBytes: Int
    private let queue = DispatchQueue(label: "global-pet-assistant.local-event-server")
    private let clientQueue = DispatchQueue(
        label: "global-pet-assistant.local-event-server.clients",
        attributes: .concurrent
    )
    private let rateLimiter: SourceRateLimiter
    private let configuration: AppConfiguration
    private let onEvent: @MainActor (LocalPetEvent) -> PetAnimationState
    private let onHealth: @MainActor () -> EventRouterSnapshot?
    private var socketFileDescriptor: Int32 = -1
    private var isRunning = false

    init(
        port: UInt16 = LocalEventServer.defaultPort,
        maxBodyBytes: Int = 16 * 1024,
        rateLimiter: SourceRateLimiter = SourceRateLimiter(),
        configuration: AppConfiguration = .defaultConfiguration,
        onHealth: @escaping @MainActor () -> EventRouterSnapshot? = { nil },
        onEvent: @escaping @MainActor (LocalPetEvent) -> PetAnimationState
    ) {
        self.port = port
        self.maxBodyBytes = maxBodyBytes
        self.rateLimiter = rateLimiter
        self.configuration = configuration
        self.onHealth = onHealth
        self.onEvent = onEvent
    }

    func start() throws {
        guard !isRunning else {
            return
        }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw LocalEventServerError.socket(String(cString: strerror(errno)))
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw LocalEventServerError.bind("127.0.0.1:\(port)", message)
        }

        guard listen(fd, SOMAXCONN) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw LocalEventServerError.listen(message)
        }

        socketFileDescriptor = fd
        isRunning = true
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        guard isRunning else {
            return
        }

        isRunning = false
        if socketFileDescriptor >= 0 {
            close(socketFileDescriptor)
            socketFileDescriptor = -1
        }
    }

    private func acceptLoop() {
        while isRunning {
            let client = accept(socketFileDescriptor, nil, nil)
            guard client >= 0 else {
                continue
            }

            clientQueue.async { [weak self] in
                self?.handle(client: client)
            }
        }
    }

    private func handle(client: Int32) {
        defer {
            close(client)
        }

        do {
            let request = try readRequest(from: client)
            if request.method == "GET", request.path == "/healthz" {
                let snapshot = healthSnapshot()
                var body: [String: Any] = ["ok": true, "status": "ok"]
                if let snapshot {
                    body["state"] = snapshot.currentState.rawValue
                    body["activeEvents"] = snapshot.activeEventCount
                    body["hasAction"] = snapshot.hasAction
                    if let currentSource = snapshot.currentSource {
                        body["currentSource"] = currentSource
                    }
                }

                try writeResponse(
                    to: client,
                    status: 200,
                    reason: "OK",
                    body: body
                )
                return
            }

            guard request.method == "POST", request.path == "/events" else {
                try writeResponse(
                    to: client,
                    status: 404,
                    reason: "Not Found",
                    body: ["ok": false, "error": "not_found"]
                )
                return
            }

            let event = try JSONDecoder().decode(LocalPetEvent.self, from: request.body)
            if !event.clearsRouter, let rejection = rateLimiter.record(source: event.source) {
                try writeResponse(
                    to: client,
                    status: 429,
                    reason: "Too Many Requests",
                    body: [
                        "ok": false,
                        "error": "rate_limited",
                        "retryAfterMs": rejection.retryAfterMs
                    ]
                )
                return
            }

            try ActionHandler.validate(
                event.action,
                source: event.source,
                configuration: configuration
            )
            let selectedState = route(event)

            try writeResponse(
                to: client,
                status: 202,
                reason: "Accepted",
                body: [
                    "ok": true,
                    "state": selectedState.rawValue
                ]
            )
        } catch LocalEventServerError.payloadTooLarge {
            try? writeResponse(
                to: client,
                status: 413,
                reason: "Payload Too Large",
                body: ["ok": false, "error": "payload_too_large"]
            )
        } catch let error as ActionValidationError where error.isActionAuthorizationFailure {
            try? writeResponse(
                to: client,
                status: 403,
                reason: "Forbidden",
                body: [
                    "ok": false,
                    "error": "action_not_allowed",
                    "message": String(describing: error)
                ]
            )
        } catch {
            try? writeResponse(
                to: client,
                status: 400,
                reason: "Bad Request",
                body: ["ok": false, "error": String(describing: error)]
            )
        }
    }

    private func route(_ event: LocalPetEvent) -> PetAnimationState {
        let semaphore = DispatchSemaphore(value: 0)
        let box = RoutedStateBox()

        Task { @MainActor in
            box.state = self.onEvent(event)
            semaphore.signal()
        }

        semaphore.wait()
        return box.state ?? event.resolvedPetState
    }

    private func healthSnapshot() -> EventRouterSnapshot? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = HealthSnapshotBox()

        Task { @MainActor in
            box.snapshot = self.onHealth()
            semaphore.signal()
        }

        semaphore.wait()
        return box.snapshot
    }

    private func readRequest(from client: Int32) throws -> LocalHTTPRequest {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let headerDelimiter = Data("\r\n\r\n".utf8)
        var headerRange: Range<Data.Index>?

        while headerRange == nil {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else {
                throw LocalEventServerError.invalidRequest
            }

            data.append(buffer, count: count)
            if data.count > maxBodyBytes + 8192 {
                throw LocalEventServerError.payloadTooLarge
            }

            headerRange = data.range(of: headerDelimiter)
        }

        guard let headerRange else {
            throw LocalEventServerError.invalidRequest
        }

        let headerEnd = headerRange.upperBound
        guard
            let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8),
            let firstLine = headerText.split(separator: "\r\n", maxSplits: 1).first
        else {
            throw LocalEventServerError.invalidRequest
        }

        let requestParts = firstLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            throw LocalEventServerError.invalidRequest
        }

        var headers: [String: String] = [:]
        for line in headerText.split(separator: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                continue
            }

            headers[String(parts[0]).lowercased()] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength <= maxBodyBytes else {
            throw LocalEventServerError.payloadTooLarge
        }

        while data.count - headerEnd < contentLength {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else {
                throw LocalEventServerError.invalidRequest
            }

            data.append(buffer, count: count)
            if data.count - headerEnd > maxBodyBytes {
                throw LocalEventServerError.payloadTooLarge
            }
        }

        let body = data.subdata(in: headerEnd..<(headerEnd + contentLength))
        return LocalHTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            body: body
        )
    }

    private func writeResponse(
        to client: Int32,
        status: Int,
        reason: String,
        body: [String: Any]
    ) throws {
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: application/json\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(bodyData)
        response.withUnsafeBytes { pointer in
            _ = send(client, pointer.baseAddress, response.count, 0)
        }
    }
}

extension LocalEventServer: @unchecked Sendable {}

private struct LocalHTTPRequest {
    let method: String
    let path: String
    let body: Data
}

private final class RoutedStateBox: @unchecked Sendable {
    var state: PetAnimationState?
}

private final class HealthSnapshotBox: @unchecked Sendable {
    var snapshot: EventRouterSnapshot?
}

enum LocalEventServerError: Error, CustomStringConvertible {
    case socket(String)
    case bind(String, String)
    case listen(String)
    case invalidRequest
    case payloadTooLarge

    var description: String {
        switch self {
        case .socket(let message):
            "Could not create local event socket: \(message)."
        case let .bind(endpoint, message):
            "Could not bind local event server to \(endpoint): \(message)."
        case .listen(let message):
            "Could not listen for local events: \(message)."
        case .invalidRequest:
            "Invalid HTTP request."
        case .payloadTooLarge:
            "Request body exceeds local event size limit."
        }
    }
}
