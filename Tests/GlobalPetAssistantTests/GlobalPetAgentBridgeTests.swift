import Foundation
import GlobalPetAgentBridgeCore
import Testing
@testable import GlobalPetAssistant

struct GlobalPetAgentBridgeTests {
    @Test
    func parsesCodexSource() throws {
        #expect(try GlobalPetAgentBridge.parseSource(arguments: ["--source", "codex"]) == "codex")
        #expect(try GlobalPetAgentBridge.parseSource(arguments: ["--source=codex"]) == "codex")
    }

    @Test
    func rejectsUnsupportedSource() {
        #expect(throws: GlobalPetAgentBridgeError.unsupportedSource("claude")) {
            try GlobalPetAgentBridge.parseSource(arguments: ["--source", "claude"])
        }
    }

    @Test
    func bridgeJSONCanDecodeAsAppEnvelope() throws {
        let line = try GlobalPetAgentBridge.makeEnvelopeLine(
            source: "codex",
            arguments: ["--source", "codex"],
            stdinData: Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"hello"}"#.utf8),
            environment: [
                "PWD": "/tmp/project",
                "TERM_PROGRAM": "Apple_Terminal",
                "TMUX_PANE": "%1",
                "CODEX_SESSION_ID": "s1"
            ],
            receivedAt: Date(timeIntervalSince1970: 1_000),
            currentDirectory: "/fallback",
            parentProcessID: 456,
            tty: "/dev/ttys001"
        )

        let envelope = try AgentHookEnvelope.decodeLine(line)
        #expect(envelope.source == .codex)
        #expect(envelope.environment.cwd == "/tmp/project")
        #expect(envelope.terminal.tmuxPane == "%1")
        #expect(envelope.metadata["cwd"] == .string("/tmp/project"))
    }

    @Test
    func missingAppSocketStillExitsSuccessfully() {
        let exitCode = GlobalPetAgentBridge.run(
            arguments: ["--source", "codex"],
            stdinData: Data(#"{"hook_event_name":"SessionStart"}"#.utf8),
            environment: [:],
            currentDirectory: "/tmp/project",
            parentProcessID: nil,
            tty: nil,
            send: { _, _ in throw GlobalPetAgentBridgeError.socketUnavailable("missing") },
            appendAudit: { _ in }
        )

        #expect(exitCode == 0)
    }

    @Test
    func invalidJSONExitsWithUsageFailure() {
        let exitCode = GlobalPetAgentBridge.run(
            arguments: ["--source", "codex"],
            stdinData: Data("not-json".utf8),
            environment: [:],
            currentDirectory: "/tmp/project",
            parentProcessID: nil,
            tty: nil,
            send: { _, _ in },
            appendAudit: { _ in }
        )

        #expect(exitCode == 2)
    }
}
