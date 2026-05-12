import Foundation
import Testing
@testable import GlobalPetAssistant

struct KittyTargetResolverTests {
    @Test
    func rejectsMissingSessionID() {
        #expect(throws: TerminalTransportError.invalidTarget("Missing terminal session id.")) {
            try KittyTargetResolver().resolve(TerminalSessionContext(
                kind: .kitty,
                sessionId: "",
                windowId: "42",
                controlEndpoint: "unix:/tmp/kitty"
            ))
        }
    }

    @Test
    func rejectsInvalidEndpoint() {
        #expect(throws: TerminalTransportError.invalidTarget("Kitty control endpoint must be local.")) {
            try KittyTargetResolver().resolve(TerminalSessionContext(
                kind: .kitty,
                sessionId: "s1",
                windowId: "42",
                controlEndpoint: "tcp:192.168.1.2:5000"
            ))
        }
    }
}

struct KittyTerminalTransportTests {
    @Test
    func observeRejectsInvalidKittyTarget() async {
        let transport = KittyTerminalTransport(runner: RecordingKittyRunner(result: RecordingKittyRunner.success))

        await #expect(throws: TerminalTransportError.missingEndpoint) {
            try await transport.observe(TerminalSessionContext(kind: .kitty, sessionId: "s1", windowId: "42"))
        }
    }

    @Test
    func reachableKittyContextReturnsObservation() async throws {
        let runner = RecordingKittyRunner(result: RecordingKittyRunner.success)
        let context = kittyContext()
        let observation = try await KittyTerminalTransport(runner: runner).observe(context)

        #expect(observation.isReachable == true)
        #expect(observation.capabilities == Set<AgentCapability>([.observe, .focus]))
        #expect(await runner.arguments == [["@", "--to", "unix:/tmp/kitty", "ls", "--match", "id:42"]])
    }

    @Test
    func staleTargetProducesTypedError() async {
        let runner = RecordingKittyRunner(result: KittyCommandResult(exitCode: 1, stdout: "", stderr: "no match"))

        await #expect(throws: TerminalTransportError.staleTarget("no match")) {
            try await KittyTerminalTransport(runner: runner).observe(kittyContext())
        }
    }

    @Test
    func focusUsesStructuredArguments() async throws {
        let runner = RecordingKittyRunner(result: RecordingKittyRunner.success)
        try await KittyTerminalTransport(runner: runner).focus(kittyContext())

        #expect(await runner.arguments == [
            [
                "@",
                "--to",
                "unix:/tmp/kitty",
                "focus-window",
                "--match",
                "id:42",
            ]
        ])
    }

    private func kittyContext() -> TerminalSessionContext {
        TerminalSessionContext(
            kind: .kitty,
            sessionId: "s1",
            windowId: "42",
            controlEndpoint: "unix:/tmp/kitty"
        )
    }
}

private actor RecordingKittyRunner: KittyCommandRunning {
    static let success = KittyCommandResult(exitCode: 0, stdout: "[]", stderr: "")

    private let result: KittyCommandResult
    private(set) var arguments: [[String]] = []

    init(result: KittyCommandResult) {
        self.result = result
    }

    func run(arguments: [String]) async throws -> KittyCommandResult {
        self.arguments.append(arguments)
        return result
    }
}
