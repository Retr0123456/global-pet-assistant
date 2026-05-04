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
}
