import Foundation
import Testing
@testable import GlobalPetAssistant

struct CodexProviderTests {
    private let provider = CodexProvider()

    @Test
    func mapsSessionStart() throws {
        let update = try providerUpdate(payload: #"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/tmp/project"}"#)

        #expect(update?.id == "s1")
        #expect(update?.status == .started)
        #expect(update?.kind == .codex)
        #expect(update?.capabilities == [.observe])
        #expect(update?.cwd == "/tmp/project")
        #expect(update?.metadata["hook_event_name"] == .string("SessionStart"))
    }

    @Test
    func userPromptUpdatesSameSessionTitleAndMessage() throws {
        let registry = AgentRegistry()
        let start = try #require(try providerUpdate(payload: #"{"hook_event_name":"SessionStart","session_id":"s1"}"#))
        let prompt = try #require(try providerUpdate(payload: #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"Implement the Codex provider"}"#))

        registry.upsert(start)
        registry.upsert(prompt)

        let sessions = registry.snapshot.sessions
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == "s1")
        #expect(sessions.first?.status == .running)
        #expect(sessions.first?.title == "Implement the Codex provider")
    }

    @Test
    func mapsPreToolUseAndPostToolUse() throws {
        let pre = try providerUpdate(payload: #"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash","tool_input":{"command":"swift test"}}"#)
        let post = try providerUpdate(payload: #"{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"Bash","result":"tests passed" }"#)

        #expect(pre?.status == .running)
        #expect(pre?.title == "Using Bash")
        #expect(pre?.message == "swift test")
        #expect(pre?.metadata["tool_name"] == .string("Bash"))
        #expect(post?.status == .running)
        #expect(post?.title == "Finished Bash")
        #expect(post?.message == "tests passed")
    }

    @Test
    func permissionRequestProjectsWaitingAndPendingDescription() throws {
        let update = try providerUpdate(payload: #"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"git push"}}"#)

        #expect(update?.status == .waiting)
        #expect(update?.pendingPermissionDescription == "Bash wants to run git push")
        let session = AgentRegistry().upsert(try #require(update))
        #expect(AgentThreadProjection.snapshot(for: session).status == .approvalRequired)
    }

    @Test
    func stopCompletesWithoutDeletingSession() throws {
        let registry = AgentRegistry()
        registry.upsert(try #require(try providerUpdate(payload: #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"work"}"#)))
        registry.upsert(try #require(try providerUpdate(payload: #"{"hook_event_name":"Stop","session_id":"s1"}"#)))

        #expect(registry.snapshot.sessions.count == 1)
        #expect(registry.snapshot.sessions.first?.status == .completed)
    }

    @Test
    func canonicalizesSubagentToParentThread() throws {
        let update = try providerUpdate(payload: #"{"hook_event_name":"UserPromptSubmit","session_id":"child-1","session_meta":{"parent_thread_id":"parent-1"},"prompt":"subagent work"}"#)

        #expect(update?.id == "parent-1")
        #expect(update?.metadata["subagent_session_id"] == .string("child-1"))
        #expect(update?.metadata["parent_thread_id"] == .string("parent-1"))
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

    @Test
    func preservesTranscriptAndRolloutPaths() throws {
        let update = try providerUpdate(payload: #"{"hook_event_name":"SessionStart","session_id":"s1","transcript_path":"/tmp/transcript.jsonl","rollout_path":"/tmp/rollout.jsonl","session_file_path":"/tmp/session.jsonl"}"#)

        #expect(update?.metadata["transcript_path"] == .string("/tmp/transcript.jsonl"))
        #expect(update?.metadata["rollout_path"] == .string("/tmp/rollout.jsonl"))
        #expect(update?.metadata["session_file_path"] == .string("/tmp/session.jsonl"))
    }

    private func providerUpdate(
        payload: String,
        environment: [String: String] = ["PWD": "/tmp/project"],
        tty: String? = nil
    ) throws -> AgentSessionUpdate? {
        let envelope = try AgentHookEnvelope.make(
            source: .codex,
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
