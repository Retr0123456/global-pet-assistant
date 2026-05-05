import Foundation

struct FocusTimerRecord: Codable, Equatable {
    let startedAt: Date
    let durationSeconds: Int
    let endsAt: Date
}

struct FocusTimerSnapshot: Equatable {
    let startedAt: Date
    let durationSeconds: Int
    let endsAt: Date
    let remainingSeconds: Int

    var isRunning: Bool {
        remainingSeconds > 0
    }

    var isEndingSoon: Bool {
        remainingSeconds > 0 && remainingSeconds <= 60
    }

    var formattedRemaining: String {
        let hours = remainingSeconds / 3_600
        let minutes = (remainingSeconds % 3_600) / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

@MainActor
final class FocusTimerController {
    typealias SnapshotHandler = @MainActor (FocusTimerSnapshot?) -> Void
    typealias CompletionHandler = @MainActor (FocusTimerSnapshot) -> Void

    private let now: () -> Date
    private let loadRecord: () -> FocusTimerRecord?
    private let saveRecord: (FocusTimerRecord) throws -> Void
    private let clearRecord: () -> Void
    private let schedulesRealTimer: Bool
    private let onSnapshotChange: SnapshotHandler
    private let onCompleted: CompletionHandler
    private var activeRecord: FocusTimerRecord?
    private var tickTimer: Timer?

    init(
        now: @escaping () -> Date = Date.init,
        loadRecord: @escaping () -> FocusTimerRecord? = AppStorage.loadFocusTimerRecord,
        saveRecord: @escaping (FocusTimerRecord) throws -> Void = AppStorage.saveFocusTimerRecord,
        clearRecord: @escaping () -> Void = AppStorage.clearFocusTimerRecord,
        schedulesRealTimer: Bool = true,
        onSnapshotChange: @escaping SnapshotHandler,
        onCompleted: @escaping CompletionHandler
    ) {
        self.now = now
        self.loadRecord = loadRecord
        self.saveRecord = saveRecord
        self.clearRecord = clearRecord
        self.schedulesRealTimer = schedulesRealTimer
        self.onSnapshotChange = onSnapshotChange
        self.onCompleted = onCompleted

        restoreActiveRecord()
    }

    var snapshot: FocusTimerSnapshot? {
        guard let activeRecord else {
            return nil
        }

        return makeSnapshot(for: activeRecord)
    }

    @discardableResult
    func start(durationSeconds: Int) -> FocusTimerSnapshot? {
        guard durationSeconds > 0 else {
            return nil
        }

        let startedAt = now()
        let record = FocusTimerRecord(
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            endsAt: startedAt.addingTimeInterval(TimeInterval(durationSeconds))
        )
        activeRecord = record
        do {
            try saveRecord(record)
        } catch {
            NSLog("GlobalPetAssistant could not persist focus timer: \(String(describing: error))")
        }

        scheduleTickTimer()
        let snapshot = makeSnapshot(for: record)
        onSnapshotChange(snapshot)
        return snapshot
    }

    @discardableResult
    func cancel() -> Bool {
        guard activeRecord != nil else {
            return false
        }

        activeRecord = nil
        tickTimer?.invalidate()
        tickTimer = nil
        clearRecord()
        onSnapshotChange(nil)
        return true
    }

    func refresh() {
        tick()
    }

    private func restoreActiveRecord() {
        guard let record = loadRecord() else {
            return
        }

        guard record.endsAt > now(), record.durationSeconds > 0 else {
            clearRecord()
            return
        }

        activeRecord = record
        scheduleTickTimer()
    }

    private func tick() {
        guard let record = activeRecord else {
            onSnapshotChange(nil)
            return
        }

        let snapshot = makeSnapshot(for: record)
        guard snapshot.remainingSeconds > 0 else {
            completeTimer(record: record)
            return
        }

        onSnapshotChange(snapshot)
    }

    private func completeTimer(record: FocusTimerRecord) {
        let completedSnapshot = FocusTimerSnapshot(
            startedAt: record.startedAt,
            durationSeconds: record.durationSeconds,
            endsAt: record.endsAt,
            remainingSeconds: 0
        )
        activeRecord = nil
        tickTimer?.invalidate()
        tickTimer = nil
        clearRecord()
        onSnapshotChange(nil)
        onCompleted(completedSnapshot)
    }

    private func makeSnapshot(for record: FocusTimerRecord) -> FocusTimerSnapshot {
        let remaining = max(0, Int(ceil(record.endsAt.timeIntervalSince(now()))))
        return FocusTimerSnapshot(
            startedAt: record.startedAt,
            durationSeconds: record.durationSeconds,
            endsAt: record.endsAt,
            remainingSeconds: remaining
        )
    }

    private func scheduleTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil

        guard schedulesRealTimer else {
            return
        }

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
}
