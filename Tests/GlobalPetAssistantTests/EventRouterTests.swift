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
