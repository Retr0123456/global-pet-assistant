import Foundation
import Testing
@testable import GlobalPetAssistant

struct AgentHookEnvelopeTests {
    @Test
    func bridgeEnvelopeEncodingCapturesCodexPayloadAndTerminalEnvironment() throws {
        let payload = Data("""
        {
          "hook_event_name": "UserPromptSubmit",
          "session_id": "session-123",
          "prompt": "Implement the refactor",
          "transcript_path": "/Users/ryan/.codex/sessions/rollout.jsonl"
        }
        """.utf8)

        let envelope = try AgentHookEnvelope.make(
            source: .codex,
            arguments: ["global-pet-agent-bridge", "--source", "codex"],
            stdinData: payload,
            environment: [
                "PWD": "/tmp/global-pet-assistant",
                "TERM_PROGRAM": "Apple_Terminal",
                "TERM_SESSION_ID": "term-1",
                "TMUX_PANE": "%7",
                "KITTY_WINDOW_ID": "42",
                "CODEX_SESSION_ID": "session-123"
            ],
            receivedAt: Date(timeIntervalSince1970: 1_000),
            currentDirectory: "/fallback",
            parentProcessID: 321,
            tty: "/dev/ttys003"
        )

        #expect(envelope.source == .codex)
        #expect(envelope.environment.cwd == "/tmp/global-pet-assistant")
        #expect(envelope.environment.parentProcessID == 321)
        #expect(envelope.terminal.tty == "/dev/ttys003")
        #expect(envelope.terminal.termProgram == "Apple_Terminal")
        #expect(envelope.terminal.termSessionID == "term-1")
        #expect(envelope.terminal.tmuxPane == "%7")
        #expect(envelope.metadata["transcript_path"] == .string("/Users/ryan/.codex/sessions/rollout.jsonl"))

        let encoded = try AgentHookEnvelope.encodeLine(envelope)
        let decoded = try AgentHookEnvelope.decodeLine(encoded)
        #expect(decoded == envelope)
    }

    @Test
    func socketDecoderAcceptsValidEnvelope() throws {
        let envelope = try AgentHookEnvelope.make(
            source: .codex,
            arguments: [],
            stdinData: Data(#"{"hook_event_name":"SessionStart"}"#.utf8),
            environment: [:],
            receivedAt: Date(timeIntervalSince1970: 1_000),
            currentDirectory: "/tmp/project",
            parentProcessID: nil
        )
        let line = try AgentHookEnvelope.encodeLine(envelope)

        #expect(try AgentHookEnvelope.decodeLine(line) == envelope)
    }

    @Test
    func socketDecoderRejectsInvalidPayload() {
        #expect(throws: AgentHookEnvelopeError.invalidJSON) {
            try AgentHookEnvelope.decodeLine(Data("not-json\n".utf8))
        }
    }

    @Test
    func socketDecoderRejectsOversizedPayload() {
        #expect(throws: AgentHookEnvelopeError.payloadTooLarge) {
            try AgentHookEnvelope.decodeLine(Data(repeating: 0x20, count: 12), maxBodyBytes: 8)
        }
    }

    @Test
    func missingTerminalFieldsAreOptional() throws {
        let envelope = try AgentHookEnvelope.make(
            source: .codex,
            arguments: [],
            stdinData: Data(#"{"hook_event_name":"SessionStart"}"#.utf8),
            environment: [:],
            receivedAt: Date(timeIntervalSince1970: 1_000),
            currentDirectory: "/tmp/project",
            parentProcessID: nil
        )

        #expect(envelope.terminal.tty == nil)
        #expect(envelope.terminal.tmuxPane == nil)
        #expect(envelope.environment.cwd == "/tmp/project")
    }
}
