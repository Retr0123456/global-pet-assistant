import Foundation

struct KittyTerminalTransport: TerminalTransport {
    let integrationKind: TerminalIntegrationKind = .kitty

    private let resolver: KittyTargetResolver
    private let runner: any KittyCommandRunning

    init(
        resolver: KittyTargetResolver = KittyTargetResolver(),
        runner: any KittyCommandRunning
    ) {
        self.resolver = resolver
        self.runner = runner
    }

    init() throws {
        self.resolver = KittyTargetResolver()
        self.runner = try KittyCommandRunner()
    }

    func observe(_ context: TerminalSessionContext) async throws -> TerminalObservation {
        let target = try resolver.resolve(context)
        let result = try await runner.run(arguments: [
            "@",
            "--to",
            target.endpoint,
            "ls",
            "--match",
            "id:\(target.windowId)"
        ])

        guard result.exitCode == 0 else {
            throw TerminalTransportError.staleTarget(result.stderr)
        }

        return TerminalObservation(
            context: context,
            isReachable: true,
            capabilities: [.observe, .focus]
        )
    }

    func focus(_ context: TerminalSessionContext) async throws {
        let target = try resolver.resolve(context)
        let result = try await runner.run(arguments: [
            "@",
            "--to",
            target.endpoint,
            "focus-window",
            "--match",
            "id:\(target.windowId)"
        ])

        guard result.exitCode == 0 else {
            throw TerminalTransportError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
    }
}
