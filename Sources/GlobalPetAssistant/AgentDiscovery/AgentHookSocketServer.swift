import Darwin
import Foundation

final class AgentHookSocketServer {
    private let socketURL: URL
    private let maxBodyBytes: Int
    private let queue = DispatchQueue(label: "global-pet-assistant.agent-hook-socket")
    private let clientQueue = DispatchQueue(
        label: "global-pet-assistant.agent-hook-socket.clients",
        attributes: .concurrent
    )
    private let onEnvelope: @Sendable (AgentHookEnvelope) -> Void
    private var socketFileDescriptor: Int32 = -1
    private var isRunning = false

    init(
        socketURL: URL = AppStorage.agentHookSocketURL,
        maxBodyBytes: Int = AgentHookEnvelope.defaultMaxBodyBytes,
        onEnvelope: @escaping @Sendable (AgentHookEnvelope) -> Void
    ) {
        self.socketURL = socketURL
        self.maxBodyBytes = maxBodyBytes
        self.onEnvelope = onEnvelope
    }

    func start() throws {
        guard !isRunning else {
            return
        }

        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try removeStaleSocketIfSafe()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw AgentHookSocketServerError.socket(String(cString: strerror(errno)))
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw AgentHookSocketServerError.bind(socketURL.path, "socket path too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { pointer in
            for (index, byte) in pathBytes.enumerated() {
                pointer[index] = byte
            }
            pointer[pathBytes.count] = 0
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count + 1))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw AgentHookSocketServerError.bind(socketURL.path, message)
        }

        guard listen(fd, SOMAXCONN) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw AgentHookSocketServerError.listen(message)
        }

        socketFileDescriptor = fd
        isRunning = true
        AuditLogger.appendRuntime(status: "agent_hook_socket_started", message: socketURL.path)
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
        try? FileManager.default.removeItem(at: socketURL)
        AuditLogger.appendRuntime(status: "agent_hook_socket_stopped", message: socketURL.path)
    }

    static func decodeEnvelopeData(_ data: Data, maxBodyBytes: Int = AgentHookEnvelope.defaultMaxBodyBytes) throws -> AgentHookEnvelope {
        try AgentHookEnvelope.decodeLine(data, maxBodyBytes: maxBodyBytes)
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
            let data = try readEnvelopeData(from: client)
            let envelope = try Self.decodeEnvelopeData(data, maxBodyBytes: maxBodyBytes)
            AuditLogger.appendRuntime(status: "agent_hook_socket_received", message: envelope.source.rawValue)
            onEnvelope(envelope)
        } catch AgentHookEnvelopeError.payloadTooLarge {
            AuditLogger.appendRuntime(status: "agent_hook_socket_payload_too_large", message: socketURL.path)
        } catch {
            AuditLogger.appendRuntime(status: "agent_hook_socket_decode_failed", message: String(describing: error))
        }
    }

    private func readEnvelopeData(from client: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
            if data.count > maxBodyBytes {
                throw AgentHookEnvelopeError.payloadTooLarge
            }
            if data.last == 0x0A {
                break
            }
        }

        return data
    }

    private func removeStaleSocketIfSafe() throws {
        guard FileManager.default.fileExists(atPath: socketURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: socketURL)
    }
}

extension AgentHookSocketServer: @unchecked Sendable {}

enum AgentHookSocketServerError: Error, CustomStringConvertible {
    case socket(String)
    case bind(String, String)
    case listen(String)

    var description: String {
        switch self {
        case .socket(let message):
            return "Could not create agent hook socket: \(message)."
        case let .bind(path, message):
            return "Could not bind agent hook socket to \(path): \(message)."
        case .listen(let message):
            return "Could not listen for agent hook events: \(message)."
        }
    }
}
