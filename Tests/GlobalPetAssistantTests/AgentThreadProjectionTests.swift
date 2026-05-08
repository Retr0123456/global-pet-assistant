import Foundation
import Testing
@testable import GlobalPetAssistant

struct AgentThreadProjectionTests {
    @Test
    func codexRunningWaitingApprovalAndCompletedRows() {
        let now = Date(timeIntervalSince1970: 1_000)
        let running = session(id: "running", status: .running, now: now)
        let waiting = session(id: "waiting", status: .waiting, now: now)
        let approval = session(id: "approval", status: .waiting, pending: "Bash wants approval", now: now)
        let completed = session(id: "completed", status: .completed, now: now)

        #expect(AgentThreadProjection.snapshot(for: running).status == .running)
        #expect(AgentThreadProjection.snapshot(for: waiting).status == .waiting)
        #expect(AgentThreadProjection.snapshot(for: approval).status == .approvalRequired)
        #expect(AgentThreadProjection.snapshot(for: completed).status == .success)
    }

    @Test
    func completedAgentRowStaysVisibleInPanelSnapshot() {
        let now = Date(timeIntervalSince1970: 1_000)
        let agent = AgentThreadProjection.snapshot(for: session(id: "completed", status: .completed, now: now))

        let panel = ThreadPanelSnapshot(agentThreads: [agent])

        #expect(panel.activeCount == 1)
        #expect(panel.displayRows.first?.id == "completed")
        #expect(panel.displayRows.first?.status == .success)
    }

    @Test
    func genericAndAgentRowsRemainDistinctAndProjectedAgentGenericRowsAreFiltered() {
        let now = Date(timeIntervalSince1970: 1_000)
        let generic = PetThreadSnapshot(
            source: "petctl",
            title: "Generic event",
            context: "still works",
            directoryName: "project",
            messagePreview: "still works",
            action: nil,
            state: .running,
            status: .running
        )
        let projectedAgentGeneric = PetThreadSnapshot(
            source: "agent:codex:abc",
            title: "Projected animation",
            context: "running",
            directoryName: "project",
            messagePreview: "running",
            action: nil,
            state: .running,
            status: .running
        )
        let agent = AgentThreadProjection.snapshot(for: session(id: "codex-session", status: .running, now: now))

        let panel = ThreadPanelSnapshot(
            genericThreads: [generic, projectedAgentGeneric],
            agentThreads: [agent]
        )

        #expect(panel.genericThreads.map(\.source) == ["petctl"])
        #expect(panel.agentThreads.map(\.id) == ["codex-session"])
        #expect(panel.activeCount == 2)
        #expect(panel.displayRows.map(\.kind) == [.agent, .generic])
    }

    @Test
    func terminalPluginSendMessageCapabilityIsExposedToThreadRows() {
        let now = Date(timeIntervalSince1970: 1_000)
        let agent = AgentSession(
            id: "codex-session",
            kind: .codex,
            controlRoutes: [.terminalPlugin: [.observe, .sendMessage]],
            status: .running,
            createdAt: now,
            lastSeenAt: now
        )
        let row = ThreadDisplayRow(agent: AgentThreadProjection.snapshot(for: agent))

        #expect(row.canSendMessage == true)
    }

    private func session(
        id: String,
        status: AgentStatus,
        pending: String? = nil,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            kind: .codex,
            status: status,
            capabilities: [.observe],
            createdAt: now,
            lastSeenAt: now,
            cwd: "/tmp/project",
            title: "Codex",
            message: "Working",
            pendingPermissionDescription: pending
        )
    }
}
