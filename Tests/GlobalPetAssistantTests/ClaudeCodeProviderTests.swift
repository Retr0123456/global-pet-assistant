import Foundation
import Testing
@testable import GlobalPetAssistant

struct ClaudeCodeProviderTests {
    private let provider = ClaudeCodeProvider()

    @Test
    func mapsSessionStart() throws {
        let update = try providerUpdate(payload: #"{"hook_event_name":"SessionStart","session_id":"c1","cwd":"/tmp/project"}"#)

        #expect(update?.id == "c1")
        #expect(update?.status == .started)
        #expect(update?.kind == .claudeCode)
        #expect(update?.capabilities == [.observe])
        #expect(update?.cwd == "/tmp/project")
        #expect(update?.metadata["hook_event_name"] == .string("SessionStart"))
    }

    @Test
    func userPromptUpdatesSameSessionTitleAndMessage() throws {
        let registry = AgentRegistry()
        let start = try #require(try providerUpdate(payload: #"{"hook_event_name":"SessionStart","session_id":"c1"}"#))
        let prompt = try #require(try providerUpdate(payload: #"{"hook_event_name":"UserPromptSubmit","session_id":"c1","prompt":"Implement hook setup"}"#))

        registry.upsert(start)
        registry.upsert(prompt)

        let sessions = registry.snapshot.sessions
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == "c1")
        #expect(sessions.first?.status == .running)
        #expect(sessions.first?.title == "Implement hook setup")
    }

    @Test
    func mapsToolAndPermissionEvents() throws {
        let pre = try providerUpdate(payload: #"{"hook_event_name":"PreToolUse","session_id":"c1","tool_name":"Bash","tool_input":{"command":"swift test"}}"#)
        let permission = try providerUpdate(payload: #"{"hook_event_name":"PermissionRequest","session_id":"c1","tool_name":"Bash","tool_input":{"command":"git push"}}"#)

        #expect(pre?.status == .running)
        #expect(pre?.title == "Using Bash")
        #expect(pre?.message == "swift test")
        #expect(permission?.status == .waiting)
        #expect(permission?.pendingPermissionDescription == "Bash wants to run git push")
    }

    @Test
    func stopFailureMarksSessionFailed() throws {
        let update = try providerUpdate(payload: #"{"hook_event_name":"StopFailure","session_id":"c1","reason":"hook failed"}"#)

        #expect(update?.status == .failed)
        #expect(update?.title == "Claude Code failed")
        #expect(update?.message == "hook failed")
    }

    @Test
    func terminalFallbackIDIsStableAndHashed() throws {
        let first = try providerUpdate(
            payload: #"{"hook_event_name":"SessionStart"}"#,
            environment: ["PWD": "/tmp/project", "TERM_SESSION_ID": "term-1"],
            tty: "/dev/ttys001"
        )
        let second = try providerUpdate(
            payload: #"{"hook_event_name":"UserPromptSubmit","prompt":"continue"}"#,
            environment: ["PWD": "/tmp/project", "TERM_SESSION_ID": "term-1"],
            tty: "/dev/ttys001"
        )

        #expect(first?.id == second?.id)
        #expect(first?.id.hasPrefix("terminal-") == true)
        #expect(first?.id.contains("/dev/ttys001") == false)
    }

    private func providerUpdate(
        payload: String,
        environment: [String: String] = ["PWD": "/tmp/project"],
        tty: String? = nil
    ) throws -> AgentSessionUpdate? {
        let envelope = try AgentHookEnvelope.make(
            source: .claudeCode,
            arguments: [],
            stdinData: Data(payload.utf8),
            environment: environment,
            receivedAt: Date(timeIntervalSince1970: 1_000),
            currentDirectory: "/tmp/project",
            parentProcessID: nil,
            tty: tty
        )
        return provider.sessionUpdate(from: envelope)
    }
}
