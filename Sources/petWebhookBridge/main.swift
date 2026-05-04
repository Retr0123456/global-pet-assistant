import Darwin
import Foundation
import PetWebhookBridgeCore

struct BridgeConfiguration {
    var port: UInt16 = 17_322
    var targetEventsURL = URL(string: "http://127.0.0.1:17321/events")!
    var maxBodyBytes = 16 * 1024
    var timeoutSeconds: TimeInterval = 5
}

enum BridgeCommandError: Error, CustomStringConvertible {
    case usage(String)
    case runtime(String)

    var description: String {
        switch self {
        case .usage(let message):
            message
        case .runtime(let message):
            message
        }
    }
}

private let usage = """
Usage:
  pet-webhook-bridge [--port 17322] [--target-url http://127.0.0.1:17321/events]

Endpoints:
  GET  /healthz
  POST /github-actions

POST /github-actions requires:
  Authorization: Bearer <token from ~/.global-pet-assistant/token>

The bridge always binds to 127.0.0.1 and forwards normalized events to the app's
local event API with the same bearer token.
"""

do {
    let configuration = try parse(Array(CommandLine.arguments.dropFirst()))
    let token = try loadToken()
    let server = WebhookBridgeServer(configuration: configuration, token: token)
    try server.run()
} catch {
    fputs("\(String(describing: error))\n\n\(usage)\n", stderr)
    exit(1)
}

private func parse(_ arguments: [String]) throws -> BridgeConfiguration {
    var configuration = BridgeConfiguration()
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--help", "-h", "help":
            print(usage)
            exit(0)
        case "--port":
            guard index + 1 < arguments.count,
                  let port = UInt16(arguments[index + 1]),
                  port > 0
            else {
                throw BridgeCommandError.usage("Invalid --port value.")
            }

            configuration.port = port
            index += 2
        case "--target-url":
            guard index + 1 < arguments.count,
                  let url = URL(string: arguments[index + 1]),
                  url.scheme == "http",
                  ["127.0.0.1", "localhost"].contains(url.host ?? "")
            else {
                throw BridgeCommandError.usage("--target-url must be an http URL on 127.0.0.1 or localhost.")
            }

            configuration.targetEventsURL = url
            index += 2
        default:
            throw BridgeCommandError.usage("Unknown argument: \(argument).")
        }
    }

    return configuration
}

private final class WebhookBridgeServer {
    private let configuration: BridgeConfiguration
    private let token: String

    init(configuration: BridgeConfiguration, token: String) {
        self.configuration = configuration
        self.token = token
    }

    func run() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw BridgeCommandError.runtime("Could not create bridge socket: \(String(cString: strerror(errno))).")
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = configuration.port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw BridgeCommandError.runtime("Could not bind bridge to 127.0.0.1:\(configuration.port): \(String(cString: strerror(errno))).")
        }

        guard listen(fd, SOMAXCONN) == 0 else {
            close(fd)
            throw BridgeCommandError.runtime("Could not listen for webhook bridge requests: \(String(cString: strerror(errno))).")
        }

        print("pet-webhook-bridge listening on http://127.0.0.1:\(configuration.port)")
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else {
                continue
            }

            handle(client: client)
        }
    }

    private func handle(client: Int32) {
        defer {
            close(client)
        }

        do {
            let request = try readRequest(from: client)
            if request.method == "GET", request.path == "/healthz" {
                try writeResponse(to: client, status: 200, reason: "OK", body: [
                    "ok": true,
                    "status": "ok"
                ])
                return
            }

            guard request.method == "POST",
                  request.path == "/github-actions" || request.path == "/webhooks/github-actions"
            else {
                try writeResponse(to: client, status: 404, reason: "Not Found", body: [
                    "ok": false,
                    "error": "not_found"
                ])
                return
            }

            guard isAuthorized(request) else {
                try writeResponse(to: client, status: 401, reason: "Unauthorized", body: [
                    "ok": false,
                    "error": "unauthorized"
                ])
                return
            }

            let event = try GitHubActionsMapper.event(from: request.body)
            let result = try forward(event: event)
            try writeResponse(to: client, status: result.status, reason: result.reason, body: result.body)
        } catch PayloadMappingError.invalidJSON {
            try? writeResponse(to: client, status: 400, reason: "Bad Request", body: [
                "ok": false,
                "error": "invalid_json"
            ])
        } catch BridgeHTTPError.payloadTooLarge {
            try? writeResponse(to: client, status: 413, reason: "Payload Too Large", body: [
                "ok": false,
                "error": "payload_too_large"
            ])
        } catch {
            try? writeResponse(to: client, status: 502, reason: "Bad Gateway", body: [
                "ok": false,
                "error": String(describing: error)
            ])
        }
    }

    private func isAuthorized(_ request: BridgeHTTPRequest) -> Bool {
        guard let header = request.headers["authorization"],
              let requestToken = bearerToken(from: header)
        else {
            return false
        }

        return constantTimeEquals(requestToken, token)
    }

    private func forward(event: BridgeEvent) throws -> BridgeForwardResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = self.configuration.timeoutSeconds
        configuration.timeoutIntervalForResource = self.configuration.timeoutSeconds

        var request = URLRequest(url: self.configuration.targetEventsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(event)

        let semaphore = DispatchSemaphore(value: 0)
        let box = BridgeResponseBox()
        let task = URLSession(configuration: configuration).dataTask(with: request) { data, response, error in
            defer {
                semaphore.signal()
            }

            if let error {
                box.result = .failure(error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                box.result = .failure(BridgeCommandError.runtime("No HTTP response from local app."))
                return
            }

            box.result = .success((data ?? Data(), httpResponse))
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + self.configuration.timeoutSeconds)
        guard waitResult == .success else {
            task.cancel()
            throw BridgeCommandError.runtime("Timed out waiting for local app.")
        }

        let (data, response) = try box.result!.get()
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(response.statusCode) else {
            return BridgeForwardResult(status: 502, reason: "Bad Gateway", body: [
                "ok": false,
                "appStatus": response.statusCode,
                "appResponse": bodyText
            ])
        }

        return BridgeForwardResult(status: 202, reason: "Accepted", body: [
            "ok": true,
            "appStatus": response.statusCode,
            "appResponse": bodyText
        ])
    }

    private func readRequest(from client: Int32) throws -> BridgeHTTPRequest {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let headerDelimiter = Data("\r\n\r\n".utf8)
        var headerRange: Range<Data.Index>?

        while headerRange == nil {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else {
                throw BridgeHTTPError.invalidRequest
            }

            data.append(buffer, count: count)
            if data.count > configuration.maxBodyBytes + 8192 {
                throw BridgeHTTPError.payloadTooLarge
            }

            headerRange = data.range(of: headerDelimiter)
        }

        guard let headerRange else {
            throw BridgeHTTPError.invalidRequest
        }

        let headerEnd = headerRange.upperBound
        guard
            let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8),
            let firstLine = headerText.split(separator: "\r\n", maxSplits: 1).first
        else {
            throw BridgeHTTPError.invalidRequest
        }

        let requestParts = firstLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            throw BridgeHTTPError.invalidRequest
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
        guard contentLength <= configuration.maxBodyBytes else {
            throw BridgeHTTPError.payloadTooLarge
        }

        while data.count - headerEnd < contentLength {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else {
                throw BridgeHTTPError.invalidRequest
            }

            data.append(buffer, count: count)
            if data.count - headerEnd > configuration.maxBodyBytes {
                throw BridgeHTTPError.payloadTooLarge
            }
        }

        let body = data.subdata(in: headerEnd..<(headerEnd + contentLength))
        return BridgeHTTPRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
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

private struct BridgeHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

private struct BridgeForwardResult {
    let status: Int
    let reason: String
    let body: [String: Any]
}

private enum BridgeHTTPError: Error {
    case invalidRequest
    case payloadTooLarge
}

private final class BridgeResponseBox: @unchecked Sendable {
    var result: Result<(Data, HTTPURLResponse), Error>?
}

private func appTokenURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".global-pet-assistant", isDirectory: true)
        .appendingPathComponent("token")
}

private func loadToken() throws -> String {
    let tokenURL = appTokenURL()
    guard let token = try? String(contentsOf: tokenURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !token.isEmpty
    else {
        throw BridgeCommandError.runtime("Missing local auth token at \(tokenURL.path). Start Global Pet Assistant once to create it.")
    }

    return token
}

private func bearerToken(from header: String) -> String? {
    let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2, parts[0].lowercased() == "bearer" else {
        return nil
    }

    let token = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
    return token.isEmpty ? nil : token
}

private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let lhsBytes = Array(lhs.utf8)
    let rhsBytes = Array(rhs.utf8)
    var difference = lhsBytes.count ^ rhsBytes.count
    for index in 0..<max(lhsBytes.count, rhsBytes.count) {
        let lhsByte = index < lhsBytes.count ? lhsBytes[index] : 0
        let rhsByte = index < rhsBytes.count ? rhsBytes[index] : 0
        difference |= Int(lhsByte ^ rhsByte)
    }

    return difference == 0
}
