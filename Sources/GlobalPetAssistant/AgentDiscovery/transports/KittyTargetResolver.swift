import Foundation

struct KittyTarget: Equatable, Sendable {
    var sessionId: String
    var windowId: String
    var endpoint: String
}

struct KittyTargetResolver {
    func resolve(_ context: TerminalSessionContext) throws -> KittyTarget {
        guard context.kind == .kitty else {
            throw TerminalTransportError.invalidTarget("Terminal context is not kitty.")
        }

        let sessionId = context.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionId.isEmpty else {
            throw TerminalTransportError.invalidTarget("Missing terminal session id.")
        }

        guard let windowId = context.windowId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !windowId.isEmpty,
              windowId.allSatisfy(\.isNumber) else {
            throw TerminalTransportError.invalidTarget("Missing or invalid kitty window id.")
        }

        guard let endpoint = context.controlEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !endpoint.isEmpty else {
            throw TerminalTransportError.missingEndpoint
        }

        guard endpoint.hasPrefix("unix:") || endpoint.hasPrefix("tcp:127.0.0.1:") || endpoint.hasPrefix("tcp:localhost:") else {
            throw TerminalTransportError.invalidTarget("Kitty control endpoint must be local.")
        }

        return KittyTarget(sessionId: sessionId, windowId: windowId, endpoint: endpoint)
    }
}
