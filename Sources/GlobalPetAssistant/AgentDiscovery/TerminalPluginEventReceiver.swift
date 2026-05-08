import Foundation

enum TerminalPluginEventReceiverError: Error, Equatable {
    case unauthorized
    case payloadTooLarge
    case malformedEvent
    case rateLimited(retryAfterMs: Int)
}

final class TerminalPluginEventReceiver {
    static let maxBodyBytes = 64 * 1024

    private let authorizationToken: String
    private let decoder: JSONDecoder
    private let rateLimiter: SourceRateLimiter
    private let flashProjection: TerminalCommandFlashProjection
    private let onFlashEvent: (LocalPetEvent) -> Void
    private let onAgentObserved: (TerminalPluginEvent) -> Void

    init(
        authorizationToken: String,
        rateLimiter: SourceRateLimiter = SourceRateLimiter(
            policies: [
                "terminal-plugin:kitty:agent-observed": SourceRateLimiter.Policy(maxEvents: 120, windowMs: 60_000),
                "terminal-plugin:kitty:command-completed": SourceRateLimiter.Policy(maxEvents: 40, windowMs: 60_000),
                "terminal-plugin:kitty:command-started": SourceRateLimiter.Policy(maxEvents: 40, windowMs: 60_000)
            ]
        ),
        flashProjection: TerminalCommandFlashProjection = TerminalCommandFlashProjection(),
        onFlashEvent: @escaping (LocalPetEvent) -> Void,
        onAgentObserved: @escaping (TerminalPluginEvent) -> Void = { _ in }
    ) {
        self.authorizationToken = authorizationToken
        self.rateLimiter = rateLimiter
        self.flashProjection = flashProjection
        self.onFlashEvent = onFlashEvent
        self.onAgentObserved = onAgentObserved
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .secondsSince1970
    }

    @discardableResult
    func receive(data: Data, authorizationHeader: String?) throws -> TerminalPluginEvent {
        guard isAuthorized(authorizationHeader) else {
            throw TerminalPluginEventReceiverError.unauthorized
        }

        guard data.count <= Self.maxBodyBytes else {
            throw TerminalPluginEventReceiverError.payloadTooLarge
        }

        let event: TerminalPluginEvent
        do {
            event = try decoder.decode(TerminalPluginEvent.self, from: data)
        } catch {
            throw TerminalPluginEventReceiverError.malformedEvent
        }

        let source = "terminal-plugin:\(event.terminal.kind.rawValue):\(event.kind.rawValue)"
        if let rejection = rateLimiter.record(source: source) {
            throw TerminalPluginEventReceiverError.rateLimited(retryAfterMs: rejection.retryAfterMs)
        }

        switch event.kind {
        case .commandStarted:
            break
        case .commandCompleted:
            if let flashEvent = flashProjection.localEvent(for: event) {
                onFlashEvent(flashEvent)
            }
        case .agentObserved:
            onAgentObserved(event)
        }

        return event
    }

    private func isAuthorized(_ authorizationHeader: String?) -> Bool {
        guard let token = LocalAuthToken.bearerToken(from: authorizationHeader) else {
            return false
        }
        return LocalAuthToken.constantTimeEquals(token, authorizationToken)
    }
}
