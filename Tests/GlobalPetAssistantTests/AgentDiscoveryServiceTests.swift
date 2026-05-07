import Foundation
import Testing
@testable import GlobalPetAssistant

@MainActor
struct AgentDiscoveryServiceTests {
    @Test
    func codexHookUpdatesRegistryAndProjectsPetEvent() throws {
        var snapshots: [AgentRegistrySnapshot] = []
        var projectedEvents: [LocalPetEvent] = []
        let service = AgentDiscoveryService(
            onSnapshotChange: { snapshot in
                snapshots.append(snapshot)
            },
            onProjectedEvent: { event in
                projectedEvents.append(event)
            }
        )

        service.receiveHookEnvelope(try envelope(payload: #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"Run tests"}"#))

        #expect(service.snapshot.sessions.count == 1)
        #expect(service.snapshot.sessions.first?.id == "s1")
        #expect(snapshots.count == 1)
        #expect(projectedEvents.count == 1)
        #expect(projectedEvents.first?.source.hasPrefix("agent:codex:") == true)
        #expect(projectedEvents.first?.dedupeKey == "agent-session:s1")
        #expect(projectedEvents.first?.state == .running)
    }

    @Test
    func projectedPermissionEventKeepsGenericSourceSeparateFromCanonicalSessionID() throws {
        var projectedEvents: [LocalPetEvent] = []
        let service = AgentDiscoveryService(onProjectedEvent: { event in
            projectedEvents.append(event)
        })

        service.receiveHookEnvelope(try envelope(payload: #"{"hook_event_name":"PermissionRequest","session_id":"canonical-session","tool_name":"Bash","tool_input":{"command":"git push"}}"#))

        let event = try #require(projectedEvents.first)
        #expect(event.source != "canonical-session")
        #expect(event.source.hasPrefix("agent:codex:") == true)
        #expect(event.type == "agent.permission.request")
        #expect(event.level == .warning)
    }

    private func envelope(payload: String) throws -> AgentHookEnvelope {
        try AgentHookEnvelope.make(
            source: .codex,
            arguments: [],
            stdinData: Data(payload.utf8),
            environment: ["PWD": "/tmp/project"],
            receivedAt: Date(timeIntervalSince1970: 1_000),
            currentDirectory: "/tmp/project",
            parentProcessID: nil
        )
    }
}
