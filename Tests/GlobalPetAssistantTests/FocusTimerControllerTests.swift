import Foundation
import Testing
@testable import GlobalPetAssistant

@MainActor
struct FocusTimerControllerTests {
    @Test
    func testStartCreatesSnapshotAndPersistsRecord() {
        let startDate = Date(timeIntervalSince1970: 1_000)
        var savedRecord: FocusTimerRecord?
        var snapshots: [FocusTimerSnapshot?] = []

        let controller = FocusTimerController(
            now: { startDate },
            loadRecord: { nil },
            saveRecord: { savedRecord = $0 },
            clearRecord: {},
            schedulesRealTimer: false,
            onSnapshotChange: { snapshots.append($0) },
            onCompleted: { _ in }
        )

        let snapshot = controller.start(durationSeconds: 25 * 60)

        #expect(snapshot?.remainingSeconds == 1_500)
        #expect(snapshot?.formattedRemaining == "25:00")
        #expect(savedRecord?.startedAt == startDate)
        #expect(savedRecord?.durationSeconds == 1_500)
        #expect(savedRecord?.endsAt == startDate.addingTimeInterval(1_500))
        #expect(snapshots.last??.remainingSeconds == 1_500)
    }

    @Test
    func testRefreshComputesRemainingFromEndDate() {
        var now = Date(timeIntervalSince1970: 1_000)
        var snapshots: [FocusTimerSnapshot?] = []

        let controller = FocusTimerController(
            now: { now },
            loadRecord: { nil },
            saveRecord: { _ in },
            clearRecord: {},
            schedulesRealTimer: false,
            onSnapshotChange: { snapshots.append($0) },
            onCompleted: { _ in }
        )

        controller.start(durationSeconds: 90)
        now = now.addingTimeInterval(30.2)
        controller.refresh()

        #expect(snapshots.last??.remainingSeconds == 60)
        #expect(snapshots.last??.formattedRemaining == "01:00")
    }

    @Test
    func testCancelClearsStateAndStorage() {
        let startDate = Date(timeIntervalSince1970: 1_000)
        var didClear = false
        var snapshots: [FocusTimerSnapshot?] = []

        let controller = FocusTimerController(
            now: { startDate },
            loadRecord: { nil },
            saveRecord: { _ in },
            clearRecord: { didClear = true },
            schedulesRealTimer: false,
            onSnapshotChange: { snapshots.append($0) },
            onCompleted: { _ in }
        )

        controller.start(durationSeconds: 300)
        let cancelled = controller.cancel()

        #expect(cancelled == true)
        #expect(controller.snapshot == nil)
        #expect(didClear == true)
        #expect(snapshots.last! == nil)
    }

    @Test
    func testRefreshCompletesExpiredTimer() {
        var now = Date(timeIntervalSince1970: 1_000)
        var didClear = false
        var completedSnapshot: FocusTimerSnapshot?
        var snapshots: [FocusTimerSnapshot?] = []

        let controller = FocusTimerController(
            now: { now },
            loadRecord: { nil },
            saveRecord: { _ in },
            clearRecord: { didClear = true },
            schedulesRealTimer: false,
            onSnapshotChange: { snapshots.append($0) },
            onCompleted: { completedSnapshot = $0 }
        )

        controller.start(durationSeconds: 10)
        now = now.addingTimeInterval(10)
        controller.refresh()

        #expect(controller.snapshot == nil)
        #expect(didClear == true)
        #expect(snapshots.last! == nil)
        #expect(completedSnapshot?.remainingSeconds == 0)
        #expect(completedSnapshot?.formattedRemaining == "00:00")
    }

    @Test
    func testRestoresUnexpiredRecord() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let now = startedAt.addingTimeInterval(120)
        let record = FocusTimerRecord(
            startedAt: startedAt,
            durationSeconds: 1_500,
            endsAt: startedAt.addingTimeInterval(1_500)
        )

        let controller = FocusTimerController(
            now: { now },
            loadRecord: { record },
            saveRecord: { _ in },
            clearRecord: {},
            schedulesRealTimer: false,
            onSnapshotChange: { _ in },
            onCompleted: { _ in }
        )

        #expect(controller.snapshot?.remainingSeconds == 1_380)
        #expect(controller.snapshot?.formattedRemaining == "23:00")
    }

    @Test
    func testExpiredRestoreClearsStorage() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let now = startedAt.addingTimeInterval(1_501)
        let record = FocusTimerRecord(
            startedAt: startedAt,
            durationSeconds: 1_500,
            endsAt: startedAt.addingTimeInterval(1_500)
        )
        var didClear = false

        let controller = FocusTimerController(
            now: { now },
            loadRecord: { record },
            saveRecord: { _ in },
            clearRecord: { didClear = true },
            schedulesRealTimer: false,
            onSnapshotChange: { _ in },
            onCompleted: { _ in }
        )

        #expect(controller.snapshot == nil)
        #expect(didClear == true)
    }
}
