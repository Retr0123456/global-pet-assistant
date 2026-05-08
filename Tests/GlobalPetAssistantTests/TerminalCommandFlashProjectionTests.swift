import Foundation
import Testing
@testable import GlobalPetAssistant

struct TerminalCommandFlashProjectionTests {
    @Test
    func successfulLongRunningCommandCreatesSuccessFlash() {
        let event = commandEvent(command: "swift test", exitCode: 0, durationMs: 3_100)
        let flash = TerminalCommandFlashProjection().localEvent(for: event)

        #expect(flash?.type == "flash")
        #expect(flash?.level == .success)
        #expect(flash?.message == "swift test passed")
        #expect(flash?.transient == true)
    }

    @Test
    func failedCommandCreatesDangerFlash() {
        let event = commandEvent(command: "swift build", exitCode: 1, durationMs: 200)
        let flash = TerminalCommandFlashProjection().localEvent(for: event)

        #expect(flash?.level == .danger)
        #expect(flash?.message == "swift build failed (1)")
        #expect(flash?.state == .failed)
    }

    @Test
    func ignoresNoisyCommands() {
        for command in ["cd", "ls", "pwd", "git status"] {
            let event = commandEvent(command: command, exitCode: 0, durationMs: 10_000)
            #expect(TerminalCommandFlashProjection().localEvent(for: event) == nil)
        }
    }

    @Test
    func shortSuccessfulCommandDoesNotFlash() {
        let event = commandEvent(command: "true", exitCode: 0, durationMs: 100)
        #expect(TerminalCommandFlashProjection().localEvent(for: event) == nil)
    }

    @Test
    @MainActor
    func commandFlashDoesNotCreateAgentThreadRow() {
        let event = commandEvent(command: "swift test", exitCode: 0, durationMs: 3_100)
        let flash = TerminalCommandFlashProjection().localEvent(for: event)
        let router = EventRouter(onStateChange: { _ in })

        router.accept(flash!)

        #expect(router.snapshot.activeThreads.isEmpty)
        #expect(router.snapshot.flashMessages.count == 1)
    }

    private func commandEvent(command: String, exitCode: Int, durationMs: Int) -> TerminalPluginEvent {
        TerminalPluginEvent(
            kind: .commandCompleted,
            terminal: TerminalSessionContext(
                kind: .kitty,
                sessionId: "kitty-42",
                windowId: "42",
                cwd: "/tmp/project",
                command: command
            ),
            command: command,
            exitCode: exitCode,
            durationMs: durationMs,
            occurredAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
