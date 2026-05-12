import Foundation
import Testing
@testable import GlobalPetAssistant

struct AgentProjectionTests {
    @Test
    func projectsPermissionWaitingThreadAsApprovalRequired() {
        let session = AgentSession(
            id: "codex-session-1",
            kind: .codex,
            status: .waiting,
            capabilities: [.observe],
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_010),
            cwd: "/tmp/global-pet-assistant",
            title: "Needs permission",
            message: "Bash wants to run",
            pendingPermissionDescription: "Bash wants to run"
        )

        let snapshot = AgentThreadProjection.snapshot(for: session)

        #expect(snapshot.status == .approvalRequired)
        #expect(snapshot.directoryName == "global-pet-assistant")
        #expect(snapshot.capabilities == [.observe])
        #expect(snapshot.messagePreview == "Bash wants to run")
    }

    @Test
    func projectsAgentStateToGenericPetEventWithoutUsingCanonicalIDAsSource() {
        let session = AgentSession(
            id: "very-long-codex-session-id",
            kind: .codex,
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_010),
            title: "Done",
            message: "Task completed"
        )

        let event = AgentEventProjection.localEvent(for: session)

        #expect(event.source.hasPrefix("agent:codex:"))
        #expect(event.source != "very-long-codex-session-id")
        #expect(event.dedupeKey == "agent-session:very-long-codex-session-id")
        #expect(event.level == .success)
        #expect(event.state == .waving)
        #expect(event.ttlMs == nil)
    }
}
