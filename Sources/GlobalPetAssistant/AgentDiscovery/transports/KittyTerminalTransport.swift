import Foundation

struct KittyTerminalTransport: TerminalTransport {
    let integrationKind: TerminalIntegrationKind = .kitty

    private let resolver: KittyTargetResolver
    private let runner: any KittyCommandRunning
    private let maximumMessageLength: Int

    init(
        resolver: KittyTargetResolver = KittyTargetResolver(),
        runner: any KittyCommandRunning,
        maximumMessageLength: Int = 4_000
    ) {
        self.resolver = resolver
        self.runner = runner
        self.maximumMessageLength = maximumMessageLength
    }

    init(maximumMessageLength: Int = 4_000) throws {
        self.resolver = KittyTargetResolver()
        self.runner = try KittyCommandRunner()
        self.maximumMessageLength = maximumMessageLength
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
            capabilities: [.observe, .sendMessage]
        )
    }

    func sendMessage(_ text: String, to context: TerminalSessionContext) async throws {
        let normalized = try normalizedMessage(text)
        let target = try resolver.resolve(context)
        let textResult = try await runner.run(arguments: [
            "@",
            "--to",
            target.endpoint,
            "send-text",
            "--match",
            "id:\(target.windowId)",
            normalized
        ])

        guard textResult.exitCode == 0 else {
            throw TerminalTransportError.commandFailed(exitCode: textResult.exitCode, stderr: textResult.stderr)
        }

        let keyResult = try await runner.run(arguments: [
            "@",
            "--to",
            target.endpoint,
            "send-key",
            "--match",
            "id:\(target.windowId)",
            "ENTER"
        ])

        guard keyResult.exitCode == 0 else {
            throw TerminalTransportError.commandFailed(exitCode: keyResult.exitCode, stderr: keyResult.stderr)
        }
    }

    private func normalizedMessage(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TerminalTransportError.invalidMessage("Message is empty.")
        }
        guard trimmed.count <= maximumMessageLength else {
            throw TerminalTransportError.invalidMessage("Message is too long.")
        }
        return trimmed
    }
}
