import Foundation

protocol TerminalTransport {
    var integrationKind: TerminalIntegrationKind { get }

    func observe(_ context: TerminalSessionContext) async throws -> TerminalObservation
    func focus(_ context: TerminalSessionContext) async throws
}

enum TerminalTransportError: Error, Equatable {
    case unsupported
    case unavailable(String)
    case invalidTarget(String)
    case staleTarget(String)
    case missingEndpoint
    case commandFailed(exitCode: Int32, stderr: String)
}
