import Foundation

@MainActor
final class EventRouter {
    typealias StateHandler = @MainActor (PetAnimationState) -> Void
    typealias SnapshotHandler = @MainActor (EventRouterSnapshot) -> Void

    private struct RoutedEvent {
        let event: LocalPetEvent
        let state: PetAnimationState
        let priority: Int
        let sequence: Int
        let expiresAt: Date?
    }

    private struct RoutedFlashEvent {
        let id: String
        let event: LocalPetEvent
        let level: PetEventLevel
        let message: String
        let state: PetAnimationState
        let sequence: Int
        let expiresAt: Date
    }

    private let now: () -> Date
    private let onStateChange: StateHandler
    private var eventsBySource: [String: RoutedEvent] = [:]
    private var flashEvents: [RoutedFlashEvent] = []
    private var dedupeIndex: [String: String] = [:]
    private var expirationTimer: Timer?
    private var sequence = 0
    private(set) var currentState: PetAnimationState = .idle
    private(set) var currentAction: LocalPetAction?
    private(set) var currentSource: String?
    private let onSnapshotChange: SnapshotHandler?

    init(
        now: @escaping () -> Date = Date.init,
        onStateChange: @escaping StateHandler,
        onSnapshotChange: SnapshotHandler? = nil
    ) {
        self.now = now
        self.onStateChange = onStateChange
        self.onSnapshotChange = onSnapshotChange
    }

    @discardableResult
    func accept(_ event: LocalPetEvent) -> PetAnimationState {
        pruneExpired()

        if event.clearsRouter {
            clear()
            return currentState
        }

        if event.isFlashEvent {
            acceptFlash(event)
            return currentState
        }

        removeEvent(forSource: event.source)

        if let dedupeKey = event.normalizedDedupeKey,
           let existingSource = dedupeIndex[dedupeKey] {
            removeEvent(forSource: existingSource)
        }

        sequence += 1
        let routedEvent = RoutedEvent(
            event: event,
            state: event.resolvedPetState,
            priority: priority(for: event.resolvedPetState),
            sequence: sequence,
            expiresAt: nil
        )
        eventsBySource[event.source] = routedEvent

        if let dedupeKey = event.normalizedDedupeKey {
            dedupeIndex[dedupeKey] = event.source
        }

        updateCurrentState()
        scheduleExpirationTimer()
        notifySnapshotChange()
        return currentState
    }

    @discardableResult
    func clear() -> PetAnimationState {
        eventsBySource.removeAll()
        flashEvents.removeAll()
        dedupeIndex.removeAll()
        expirationTimer?.invalidate()
        expirationTimer = nil
        currentAction = nil
        currentSource = nil
        updateCurrentState()
        notifySnapshotChange()
        return currentState
    }

    @discardableResult
    func clearSource(_ source: String) -> PetAnimationState {
        removeEvent(forSource: source)
        updateCurrentState()
        scheduleExpirationTimer()
        notifySnapshotChange()
        return currentState
    }

    var snapshot: EventRouterSnapshot {
        pruneExpired()
        return makeSnapshot()
    }

    private func makeSnapshot() -> EventRouterSnapshot {
        let activeThreads = eventsBySource.values
            .sorted { lhs, rhs in
                lhs.sequence > rhs.sequence
            }
            .map { routedEvent in
                PetThreadSnapshot(
                    source: routedEvent.event.source,
                    title: routedEvent.event.threadTitle,
                    context: routedEvent.event.threadContext,
                    directoryName: routedEvent.event.threadDirectoryName,
                    messagePreview: routedEvent.event.threadMessagePreview,
                    action: routedEvent.event.action,
                    state: routedEvent.state,
                    status: routedEvent.event.threadStatus
                )
            }

        let flashMessages = flashEvents.map { flashEvent in
            PetFlashSnapshot(
                id: flashEvent.id,
                source: flashEvent.event.source,
                level: flashEvent.level,
                message: flashEvent.message,
                state: flashEvent.state,
                expiresAt: flashEvent.expiresAt
            )
        }

        return EventRouterSnapshot(
            currentState: currentState,
            activeEventCount: eventsBySource.count,
            currentSource: currentSource,
            hasAction: currentAction != nil,
            activeThreads: activeThreads,
            flashMessages: flashMessages
        )
    }

    private func acceptFlash(_ event: LocalPetEvent) {
        guard let expiresAt = expirationDate(forFlash: event) else {
            notifySnapshotChange()
            scheduleExpirationTimer()
            return
        }

        sequence += 1
        let flashEvent = RoutedFlashEvent(
            id: "\(event.source)-\(sequence)",
            event: event,
            level: event.level ?? .info,
            message: event.flashMessagePreview,
            state: event.flashAnimationState,
            sequence: sequence,
            expiresAt: expiresAt
        )
        flashEvents.insert(flashEvent, at: 0)

        if flashEvents.count > Self.maxFlashEventCount {
            flashEvents.removeLast(flashEvents.count - Self.maxFlashEventCount)
        }

        scheduleExpirationTimer()
        notifySnapshotChange()
    }

    private func removeEvent(forSource source: String) {
        guard let existing = eventsBySource.removeValue(forKey: source) else {
            return
        }

        if let dedupeKey = existing.event.normalizedDedupeKey,
           dedupeIndex[dedupeKey] == source {
            dedupeIndex.removeValue(forKey: dedupeKey)
        }
    }

    private func pruneExpired() {
        let date = now()
        let expiredSources = eventsBySource.compactMap { source, event in
            if let expiresAt = event.expiresAt, expiresAt <= date {
                return source
            }
            return nil
        }
        let originalFlashCount = flashEvents.count
        flashEvents.removeAll { event in
            event.expiresAt <= date
        }

        guard !expiredSources.isEmpty || flashEvents.count != originalFlashCount else {
            return
        }

        for source in expiredSources {
            removeEvent(forSource: source)
        }
        updateCurrentState()
        scheduleExpirationTimer()
        notifySnapshotChange()
    }

    private func updateCurrentState() {
        let selected = eventsBySource.values.max { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.sequence < rhs.sequence
            }
            return lhs.priority < rhs.priority
        }

        let nextState = selected?.state ?? .idle
        currentAction = selected?.event.action
        currentSource = selected?.event.source

        guard nextState != currentState else {
            return
        }

        currentState = nextState
        onStateChange(nextState)
    }

    private func scheduleExpirationTimer() {
        expirationTimer?.invalidate()

        let now = now()
        let nextExpirations = eventsBySource.values.compactMap(\.expiresAt) + flashEvents.map(\.expiresAt)
        guard let nextExpiration = nextExpirations.min() else {
            expirationTimer = nil
            return
        }

        let interval = max(0.05, nextExpiration.timeIntervalSince(now))
        expirationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.pruneExpired()
            }
        }
    }

    private func expirationDate(forFlash event: LocalPetEvent) -> Date? {
        let ttlMs = event.ttlMs ?? Self.defaultFlashTTL
        guard ttlMs > 0 else {
            return nil
        }

        return now().addingTimeInterval(TimeInterval(ttlMs) / 1000)
    }

    private func priority(for state: PetAnimationState) -> Int {
        switch state {
        case .failed:
            50
        case .waiting:
            40
        case .running, .runningLeft, .runningRight, .jumping, .waving:
            30
        case .review:
            20
        case .idle:
            0
        }
    }

    private func notifySnapshotChange() {
        onSnapshotChange?(makeSnapshot())
    }

    private static let maxFlashEventCount = 3
    private static let defaultFlashTTL = 4_500
}

struct PetThreadSnapshot: Equatable {
    let source: String
    let title: String
    let context: String
    let directoryName: String
    let messagePreview: String
    let action: LocalPetAction?
    let state: PetAnimationState
    let status: PetThreadStatus
}

struct PetFlashSnapshot: Equatable {
    let id: String
    let source: String
    let level: PetEventLevel
    let message: String
    let state: PetAnimationState
    let expiresAt: Date
}

struct EventRouterSnapshot {
    let currentState: PetAnimationState
    let activeEventCount: Int
    let currentSource: String?
    let hasAction: Bool
    let activeThreads: [PetThreadSnapshot]
    let flashMessages: [PetFlashSnapshot]
}
