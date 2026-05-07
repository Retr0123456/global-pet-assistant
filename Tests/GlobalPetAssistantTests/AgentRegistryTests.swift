import Foundation
import Testing
@testable import GlobalPetAssistant

struct AgentRegistryTests {
    @Test
    func createsSessionFromFirstUpdate() {
        let registry = AgentRegistry()
        let observedAt = Date(timeIntervalSince1970: 1_000)

        let session = registry.upsert(AgentSessionUpdate(
            id: "codex-session-1",
            kind: .codex,
            status: .started,
            controlRoutes: [.agentAppServer: [.observe]],
            observedAt: observedAt,
            sourceStrength: .hookEvent,
            cwd: "/tmp/global-pet-assistant",
            title: "Session started"
        ))

        #expect(session.id == "codex-session-1")
        #expect(session.kind == .codex)
        #expect(session.status == .started)
        #expect(session.createdAt == observedAt)
        #expect(session.lastSeenAt == observedAt)
        #expect(session.cwd == "/tmp/global-pet-assistant")
        #expect(session.capabilities == [.observe])
        #expect(registry.snapshot.sessions.count == 1)
    }

    @Test
    func mergesSameIDAndPreservesCreatedAt() {
        let registry = AgentRegistry()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let seenAt = Date(timeIntervalSince1970: 1_030)

        registry.upsert(AgentSessionUpdate(
            id: "codex-session-1",
            kind: .codex,
            status: .started,
            observedAt: createdAt,
            sourceStrength: .hookEvent,
            title: "Started"
        ))
        let merged = registry.upsert(AgentSessionUpdate(
            id: "codex-session-1",
            kind: .codex,
            status: .running,
            observedAt: seenAt,
            sourceStrength: .hookEvent,
            message: "Using rg"
        ))

        #expect(registry.snapshot.sessions.count == 1)
        #expect(merged.createdAt == createdAt)
        #expect(merged.lastSeenAt == seenAt)
        #expect(merged.status == .running)
        #expect(merged.message == "Using rg")
    }

    @Test
    func strongerHookFieldsSurviveWeakerInferredUpdates() {
        let registry = AgentRegistry()
        let createdAt = Date(timeIntervalSince1970: 1_000)

        registry.upsert(AgentSessionUpdate(
            id: "codex-session-1",
            kind: .codex,
            status: .waiting,
            observedAt: createdAt,
            sourceStrength: .hookEvent,
            tty: "/dev/ttys003",
            title: "Real hook title",
            metadata: ["hook_event_name": .string("PermissionRequest")]
        ))
        let merged = registry.upsert(AgentSessionUpdate(
            id: "codex-session-1",
            kind: .codex,
            status: .running,
            observedAt: createdAt.addingTimeInterval(5),
            sourceStrength: .terminalScan,
            tty: "/dev/ttys999",
            title: "Weak terminal guess",
            metadata: ["hook_event_name": .string("TerminalScan")]
        ))

        #expect(merged.status == .waiting)
        #expect(merged.tty == "/dev/ttys003")
        #expect(merged.title == "Real hook title")
        #expect(merged.metadata["hook_event_name"] == .string("PermissionRequest"))
        #expect(merged.lastSeenAt == createdAt.addingTimeInterval(5))
    }

    @Test
    func equalHookStrengthCanRefreshMetadata() {
        let registry = AgentRegistry()
        let createdAt = Date(timeIntervalSince1970: 1_000)

        registry.upsert(AgentSessionUpdate(
            id: "codex-session-1",
            kind: .codex,
            status: .running,
            observedAt: createdAt,
            sourceStrength: .hookEvent,
            metadata: ["hook_event_name": .string("PreToolUse")]
        ))
        let merged = registry.upsert(AgentSessionUpdate(
            id: "codex-session-1",
            kind: .codex,
            status: .running,
            observedAt: createdAt.addingTimeInterval(1),
            sourceStrength: .hookEvent,
            metadata: [
                "hook_event_name": .string("PostToolUse"),
                "tool_name": .string("Bash")
            ]
        ))

        #expect(merged.metadata["hook_event_name"] == .string("PostToolUse"))
        #expect(merged.metadata["tool_name"] == .string("Bash"))
    }

    @Test
    func expiryRemovesRunningBeforeCompletedSessions() {
        let registry = AgentRegistry()
        let now = Date(timeIntervalSince1970: 1_000)

        registry.upsert(AgentSessionUpdate(
            id: "running",
            kind: .codex,
            status: .running,
            observedAt: now,
            sourceStrength: .hookEvent
        ))
        registry.upsert(AgentSessionUpdate(
            id: "completed",
            kind: .codex,
            status: .completed,
            observedAt: now,
            sourceStrength: .hookEvent
        ))

        let removed = registry.expireStale(
            now: now.addingTimeInterval(120),
            staleAfter: 60,
            keepCompletedFor: 600
        )

        #expect(removed.map(\.id) == ["running"])
        #expect(registry.snapshot.sessions.map(\.id) == ["completed"])
    }

    @Test
    func staticSourceOrderingMatchesPlan() {
        #expect(AgentSignalStrength.hookEvent > .appServerSnapshot)
        #expect(AgentSignalStrength.appServerSnapshot > .rolloutJSONL)
        #expect(AgentSignalStrength.rolloutJSONL > .tmuxScan)
        #expect(AgentSignalStrength.tmuxScan > .processScan)
        #expect(AgentSignalStrength.processScan > .terminalScan)
        #expect(AgentSignalStrength.terminalScan > .workspaceMarker)
    }
}
