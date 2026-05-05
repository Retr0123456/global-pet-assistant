import Foundation
import Testing
@testable import GlobalPetAssistant

@MainActor
struct EventRouterTests {
    @Test
    func testFailedBeatsWaitingReviewAndRunning() {
        var now = Date(timeIntervalSince1970: 1_000)
        let router = EventRouter(now: { now }, onStateChange: { _ in })

        router.accept(LocalPetEvent(source: "running", level: .running, ttlMs: 10_000))
        #expect(router.currentState == PetAnimationState.running)

        router.accept(LocalPetEvent(source: "waiting", level: .warning, ttlMs: 10_000))
        #expect(router.currentState == PetAnimationState.waiting)

        router.accept(LocalPetEvent(source: "review", level: .success, ttlMs: 10_000))
        #expect(router.currentState == PetAnimationState.waiting)

        router.accept(LocalPetEvent(source: "failed", level: .danger, ttlMs: 10_000))
        #expect(router.currentState == PetAnimationState.failed)

        router.accept(LocalPetEvent(source: "new-running", level: .running, ttlMs: 10_000))
        #expect(router.currentState == PetAnimationState.failed)
        now = now.addingTimeInterval(1)
    }

    @Test
    func testNewerSameSourceEventReplacesOldEvent() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(source: "codex-cli", level: .running, ttlMs: 10_000))
        router.accept(LocalPetEvent(source: "codex-cli", level: .warning, ttlMs: 10_000))

        let snapshot = router.snapshot
        #expect(snapshot.activeEventCount == 1)
        #expect(snapshot.currentSource == "codex-cli")
        #expect(snapshot.activeThreads.first?.title == "codex-cli")
        #expect(router.currentState == PetAnimationState.waiting)
    }

    @Test
    func testDedupeKeyRemovesPreviousEventFromAnotherSource() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(source: "source-a", level: .danger, ttlMs: 10_000, dedupeKey: "job-1"))
        router.accept(LocalPetEvent(source: "source-b", level: .running, ttlMs: 10_000, dedupeKey: "job-1"))

        let snapshot = router.snapshot
        #expect(snapshot.activeEventCount == 1)
        #expect(snapshot.currentSource == "source-b")
        #expect(router.currentState == PetAnimationState.running)
    }

    @Test
    func testSnapshotIncludesThreadTitleAndContext() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(
            source: "codex-cli",
            type: "task.started",
            level: .running,
            title: "Design personal knowledge base architecture",
            message: "Submitted 62cea60 and created the GitHub Actions deploy task.",
            ttlMs: 10_000,
            cwd: "/tmp/global-pet-assistant"
        ))

        let thread = router.snapshot.activeThreads.first
        #expect(thread?.title == "Design personal knowledge base architecture")
        #expect(thread?.context == "Submitted 62cea60 and created the GitHub Actions deploy task.")
        #expect(thread?.directoryName == "global-pet-assistant")
        #expect(thread?.messagePreview == "Submitted 62cea60 and created the GitHub Actions deploy task.")
        #expect(thread?.state == .running)
        #expect(thread?.status == .running)
    }

    @Test
    func testSnapshotIncludesQuickThreadStatus() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(
            source: "codex-running",
            type: "codex.turn.running",
            state: .running,
            ttlMs: 10_000
        ))
        router.accept(LocalPetEvent(
            source: "codex-approval",
            type: "codex.permission.request",
            level: .warning,
            ttlMs: 10_000
        ))
        router.accept(LocalPetEvent(
            source: "codex-success",
            type: "codex.turn.review",
            level: .success,
            ttlMs: 10_000
        ))
        router.accept(LocalPetEvent(
            source: "local-build",
            type: "build.failed",
            level: .danger,
            ttlMs: 10_000
        ))
        router.accept(LocalPetEvent(
            source: "agent-waiting",
            type: "agent.waiting",
            level: .warning,
            ttlMs: 10_000
        ))

        let statusesBySource = Dictionary(
            uniqueKeysWithValues: router.snapshot.activeThreads.map { ($0.source, $0.status) }
        )

        #expect(statusesBySource["codex-running"] == .running)
        #expect(statusesBySource["codex-approval"] == .approvalRequired)
        #expect(statusesBySource["codex-success"] == .success)
        #expect(statusesBySource["local-build"] == .failed)
        #expect(statusesBySource["agent-waiting"] == .waiting)
    }

    @Test
    func testThreadStatusIndicatorsUseDistinctSymbols() {
        #expect(PetThreadStatus.running.indicator.symbolName == "arrow.triangle.2.circlepath")
        #expect(PetThreadStatus.waiting.indicator.symbolName == "hourglass")
        #expect(PetThreadStatus.success.indicator.symbolName == "checkmark.circle.fill")
        #expect(PetThreadStatus.failed.indicator.symbolName == "xmark.circle.fill")
        #expect(PetThreadStatus.approvalRequired.indicator.symbolName == "exclamationmark.triangle.fill")
    }

    @Test
    func testSnapshotPreviewCompactsLongMultilineMessages() {
        let router = EventRouter(onStateChange: { _ in })
        let longMessage = """
        Hello~
        This is a longer message preview that should be compacted into a single readable line before it is shown in the message area.
        """

        router.accept(LocalPetEvent(
            source: "codex-cli",
            level: .running,
            message: longMessage,
            ttlMs: 10_000,
            cwd: "/tmp/global-pet-assistant"
        ))

        let thread = router.snapshot.activeThreads.first
        #expect(thread?.directoryName == "global-pet-assistant")
        #expect(thread?.messagePreview.hasPrefix("Hello~ This is a longer message preview") == true)
        #expect(thread?.messagePreview.hasSuffix("…") == true)
    }

    @Test
    func testNewRunningEventBeatsStaleReviewEvent() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(source: "old-codex-session", level: .success, ttlMs: 300_000))
        #expect(router.currentState == PetAnimationState.review)

        router.accept(LocalPetEvent(source: "active-codex-session", level: .running, ttlMs: 120_000))

        let snapshot = router.snapshot
        #expect(snapshot.activeEventCount == 2)
        #expect(snapshot.currentSource == "active-codex-session")
        #expect(router.currentState == PetAnimationState.running)
    }

    @Test
    func testSnapshotThreadsAreNewestFirst() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(
            source: "older",
            level: .danger,
            message: "Older high-priority failure",
            ttlMs: 300_000
        ))
        router.accept(LocalPetEvent(
            source: "newer",
            level: .running,
            message: "Newest running message",
            ttlMs: 120_000
        ))

        let snapshot = router.snapshot
        #expect(snapshot.currentSource == "older")
        #expect(snapshot.activeThreads.first?.source == "newer")
        #expect(snapshot.activeThreads.first?.context == "Newest running message")
    }

    @Test
    func testSameDirectoryDistinctSessionsRemainSeparateThreads() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(
            source: "codex-cli:kitty-41",
            level: .running,
            message: "First tab is running.",
            ttlMs: 120_000,
            cwd: "/tmp/global-pet-assistant"
        ))
        router.accept(LocalPetEvent(
            source: "codex-cli:kitty-42",
            level: .running,
            message: "Second tab is running.",
            ttlMs: 120_000,
            cwd: "/tmp/global-pet-assistant"
        ))

        let snapshot = router.snapshot
        #expect(snapshot.activeEventCount == 2)
        #expect(snapshot.activeThreads.map(\.source) == ["codex-cli:kitty-42", "codex-cli:kitty-41"])
        #expect(snapshot.activeThreads.map(\.directoryName) == ["global-pet-assistant", "global-pet-assistant"])
        #expect(snapshot.activeThreads.map(\.messagePreview) == ["Second tab is running.", "First tab is running."])
    }

    @Test
    func testTTLExpiryReturnsRouterToIdle() {
        var now = Date(timeIntervalSince1970: 1_000)
        let router = EventRouter(now: { now }, onStateChange: { _ in })

        router.accept(LocalPetEvent(source: "codex-cli", level: .running, ttlMs: 1_000))
        #expect(router.currentState == PetAnimationState.running)

        now = now.addingTimeInterval(1.1)
        let snapshot = router.snapshot

        #expect(snapshot.activeEventCount == 0)
        #expect(router.currentState == PetAnimationState.idle)
    }

    @Test
    func testClearRemovesAllActiveEvents() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(source: "a", level: .danger, ttlMs: 10_000))
        router.accept(LocalPetEvent(source: "b", level: .warning, ttlMs: 10_000))

        router.clear()

        let snapshot = router.snapshot
        #expect(snapshot.activeEventCount == 0)
        #expect(snapshot.currentSource == nil)
        #expect(router.currentState == PetAnimationState.idle)
    }

    @Test
    func testFlashDoesNotChangeActiveThreadCountOrBadgeCount() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(source: "codex-cli", level: .running, ttlMs: 10_000))
        router.accept(LocalPetEvent(source: "terminal", type: "flash", level: .success, message: "swift test passed"))

        let snapshot = router.snapshot
        #expect(snapshot.activeEventCount == 1)
        #expect(snapshot.activeThreads.map(\.source) == ["codex-cli"])
        #expect(snapshot.flashMessages.count == 1)
        #expect(router.currentState == .running)
    }

    @Test
    func testFlashMessagesAreNewestFirstAndCappedAtThree() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(source: "one", type: "flash", level: .info, message: "first"))
        router.accept(LocalPetEvent(source: "two", type: "flash", level: .success, message: "second"))
        router.accept(LocalPetEvent(source: "three", type: "flash", level: .warning, message: "third"))
        router.accept(LocalPetEvent(source: "four", type: "flash", level: .danger, message: "fourth"))

        let snapshot = router.snapshot
        #expect(snapshot.flashMessages.map(\.message) == ["fourth", "third", "second"])
        #expect(snapshot.flashMessages.count == 3)
        #expect(snapshot.activeEventCount == 0)
    }

    @Test
    func testFlashDefaultTTLExpiresIndependently() {
        var now = Date(timeIntervalSince1970: 1_000)
        let router = EventRouter(now: { now }, onStateChange: { _ in })

        router.accept(LocalPetEvent(source: "terminal", type: "flash", level: .success, message: "swift test passed"))
        #expect(router.snapshot.flashMessages.count == 1)

        now = now.addingTimeInterval(4.6)
        #expect(router.snapshot.flashMessages.isEmpty)
        #expect(router.currentState == .idle)
    }

    @Test
    func testFlashDoesNotOverrideLongRunningCurrentState() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(source: "codex-cli", level: .running, ttlMs: 120_000))
        router.accept(LocalPetEvent(source: "terminal", type: "flash", level: .danger, message: "build failed"))

        let snapshot = router.snapshot
        #expect(snapshot.currentState == .running)
        #expect(snapshot.currentSource == "codex-cli")
        #expect(snapshot.flashMessages.first?.state == .failed)
        #expect(router.currentState == .running)
    }

    @Test
    func testTransientNotifyRoutesAsFlash() {
        let router = EventRouter(onStateChange: { _ in })

        router.accept(LocalPetEvent(
            source: "terminal",
            type: "notify",
            level: .success,
            message: "legacy transient",
            transient: true
        ))

        let snapshot = router.snapshot
        #expect(snapshot.activeEventCount == 0)
        #expect(snapshot.flashMessages.first?.message == "legacy transient")
        #expect(snapshot.flashMessages.first?.state == .waving)
        #expect(router.currentState == .idle)
    }
}
