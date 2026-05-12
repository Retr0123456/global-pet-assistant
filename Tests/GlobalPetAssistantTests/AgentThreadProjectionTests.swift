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
    func panelStatusSummaryUsesFailureSuccessRunningPriority() {
        let now = Date(timeIntervalSince1970: 1_000)
        let failed = AgentThreadProjection.snapshot(for: session(id: "failed", status: .failed, now: now))
        let completed = AgentThreadProjection.snapshot(for: session(id: "completed", status: .completed, now: now))
        let running = AgentThreadProjection.snapshot(for: session(id: "running", status: .running, now: now))
        let waiting = AgentThreadProjection.snapshot(for: session(id: "waiting", status: .waiting, pending: "Approve", now: now))

        let panel = ThreadPanelSnapshot(agentThreads: [running, waiting, completed, failed])

        #expect(panel.statusSummary.failedCount == 1)
        #expect(panel.statusSummary.runningCount == 2)
        #expect(panel.statusSummary.successCount == 1)
        #expect(panel.statusSummary.hasWaiting == true)
        #expect(panel.preferredPetState == .failed)
    }

    @Test
    func panelStatusSummaryUsesWavingForVisibleSuccessAfterFailureIsDismissed() {
        let now = Date(timeIntervalSince1970: 1_000)
        let completed = AgentThreadProjection.snapshot(for: session(id: "completed", status: .completed, now: now))
        let running = AgentThreadProjection.snapshot(for: session(id: "running", status: .running, now: now))

        let panel = ThreadPanelSnapshot(agentThreads: [running, completed])

        #expect(panel.statusSummary.failedCount == 0)
        #expect(panel.statusSummary.runningCount == 1)
        #expect(panel.statusSummary.successCount == 1)
        #expect(panel.preferredPetState == .waving)
    }

    @Test
    func panelStatusSummaryUsesWaitingAnimationForWaitingOnlyThreads() {
        let now = Date(timeIntervalSince1970: 1_000)
        let waiting = AgentThreadProjection.snapshot(for: session(id: "waiting", status: .waiting, now: now))
        let approval = AgentThreadProjection.snapshot(for: session(id: "approval", status: .waiting, pending: "Approve", now: now))

        let panel = ThreadPanelSnapshot(agentThreads: [waiting, approval])

        #expect(panel.statusSummary.runningCount == 2)
        #expect(panel.statusSummary.hasWaiting == true)
        #expect(panel.preferredPetState == .waiting)
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
    func terminalPluginFocusCapabilityDoesNotExposeReplyControlToThreadRows() {
        let now = Date(timeIntervalSince1970: 1_000)
        let agent = AgentSession(
            id: "codex-session",
            kind: .codex,
            capabilityRoutes: [.terminalPlugin: [.observe, .focus]],
            status: .running,
            createdAt: now,
            lastSeenAt: now
        )
        let row = ThreadDisplayRow(agent: AgentThreadProjection.snapshot(for: agent))

        #expect(row.canSendMessage == false)
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
