import Foundation
import Testing
@testable import GlobalPetAssistant

struct TerminalPluginEventTests {
    @Test
    func decodesCurrentSchema() throws {
        let event = try decode("""
        {
          "schemaVersion": 1,
          "kind": "command-completed",
          "terminal": {
            "kind": "kitty",
            "sessionId": "kitty-42",
            "windowId": "42",
            "cwd": "/tmp/project"
          },
          "command": "swift test",
          "exitCode": 0,
          "durationMs": 2500,
          "providerHint": "codex",
          "occurredAt": 1000
        }
        """)

        #expect(event.kind == .commandCompleted)
        #expect(event.terminal.kind == .kitty)
        #expect(event.terminal.sessionId == "kitty-42")
        #expect(event.command == "swift test")
        #expect(event.providerHint == .codex)
    }

    @Test
    func rejectsUnknownSchemaVersion() {
        #expect(throws: DecodingError.self) {
            try decode("""
            {
              "schemaVersion": 2,
              "kind": "command-completed",
              "terminal": { "kind": "kitty", "sessionId": "kitty-42" },
              "occurredAt": 1000
            }
            """)
        }
    }

    @Test
    func rejectsMissingTerminalSessionID() {
        #expect(throws: DecodingError.self) {
            try decode("""
            {
              "schemaVersion": 1,
              "kind": "command-completed",
              "terminal": { "kind": "kitty", "sessionId": " " },
              "occurredAt": 1000
            }
            """)
        }
    }

    @Test
    func rejectsUnknownTerminalIntegrationKind() {
        #expect(throws: DecodingError.self) {
            try decode("""
            {
              "schemaVersion": 1,
              "kind": "command-completed",
              "terminal": { "kind": "tmux", "sessionId": "pane-1" },
              "occurredAt": 1000
            }
            """)
        }
    }

    private func decode(_ json: String) throws -> TerminalPluginEvent {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(TerminalPluginEvent.self, from: Data(json.utf8))
    }
}
