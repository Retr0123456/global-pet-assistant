import Foundation
import Testing
@testable import GlobalPetAssistant

struct HookInstallerTests {
    @Test
    func installerPreservesUnrelatedHooksAndAddsManagedBridgeHooks() {
        let existing: JSONValue = .object([
            "hooks": .object([
                "PreToolUse": .array([
                    .object([
                        "matcher": .string("Bash"),
                        "hooks": .array([
                            .object([
                                "type": .string("command"),
                                "command": .string("echo user-hook")
                            ])
                        ])
                    ])
                ])
            ])
        ])

        let updated = HookInstaller.updatedHooksPayload(
            existing: existing,
            profile: CodexHookProfile(command: "/tmp/global-pet-agent-bridge --source codex")
        )
        let hooks = updated.objectValue?["hooks"]?.objectValue
        let preToolGroups = hooks?["PreToolUse"]?.arrayValueForTest ?? []

        #expect(preToolGroups.count == 2)
        #expect(preToolGroups.first?.objectValue?["hooks"]?.arrayValueForTest?.first?.objectValue?["command"] == .string("echo user-hook"))
        #expect(preToolGroups.last?.objectValue?["hooks"]?.arrayValueForTest?.first?.objectValue?["command"] == .string("/tmp/global-pet-agent-bridge --source codex"))
    }

    @Test
    func installerUpdatesManagedEntriesIdempotently() {
        let first = HookInstaller.updatedHooksPayload(
            existing: nil,
            profile: CodexHookProfile(command: "/old/global-pet-agent-bridge --source codex")
        )
        let second = HookInstaller.updatedHooksPayload(
            existing: first,
            profile: CodexHookProfile(command: "/new/global-pet-agent-bridge --source codex")
        )

        let hooks = second.objectValue?["hooks"]?.objectValue
        for event in CodexHookProfile(command: "").events {
            let groups = hooks?[event.name]?.arrayValueForTest ?? []
            #expect(groups.count == 1)
            #expect(groups.first?.objectValue?["hooks"]?.arrayValueForTest?.first?.objectValue?["command"] == .string("/new/global-pet-agent-bridge --source codex"))
        }
    }

    @Test
    func installerCoversExpectedCodexEvents() {
        let events = CodexHookProfile(command: "/tmp/global-pet-agent-bridge --source codex").events.map(\.name)

        #expect(events == [
            "SessionStart",
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "PermissionRequest",
            "Stop"
        ])
    }
}

private extension JSONValue {
    var arrayValueForTest: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }
}
