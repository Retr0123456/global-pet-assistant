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

    private let now: () -> Date
    private let onStateChange: StateHandler
    private var eventsBySource: [String: RoutedEvent] = [:]
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

        removeEvent(forSource: event.source)

        if let dedupeKey = event.normalizedDedupeKey,
           let existingSource = dedupeIndex[dedupeKey] {
            removeEvent(forSource: existingSource)
        }

        guard let expiresAt = expirationDate(for: event) else {
            updateCurrentState()
            return currentState
        }

        sequence += 1
        let routedEvent = RoutedEvent(
            event: event,
            state: event.resolvedPetState,
            priority: priority(for: event.resolvedPetState),
            sequence: sequence,
            expiresAt: expiresAt
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
                if lhs.priority == rhs.priority {
                    return lhs.sequence > rhs.sequence
                }
                return lhs.priority > rhs.priority
            }
            .map { routedEvent in
                PetThreadSnapshot(
                    source: routedEvent.event.source,
                    title: routedEvent.event.threadTitle,
                    context: routedEvent.event.threadContext,
                    state: routedEvent.state
                )
            }

        return EventRouterSnapshot(
            currentState: currentState,
            activeEventCount: eventsBySource.count,
            currentSource: currentSource,
            hasAction: currentAction != nil,
            activeThreads: activeThreads
        )
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

        guard !expiredSources.isEmpty else {
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
        guard let nextExpiration = eventsBySource.values.compactMap(\.expiresAt).min() else {
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

    private func expirationDate(for event: LocalPetEvent) -> Date? {
        let ttlMs = event.ttlMs ?? defaultTTL(for: event.resolvedPetState)
        guard ttlMs > 0 else {
            return nil
        }

        return now().addingTimeInterval(TimeInterval(ttlMs) / 1000)
    }

    private func defaultTTL(for state: PetAnimationState) -> Int {
        switch state {
        case .failed, .waiting:
            120_000
        case .review:
            45_000
        case .running, .runningLeft, .runningRight, .jumping, .waving:
            15_000
        case .idle:
            0
        }
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
}

struct PetThreadSnapshot: Equatable {
    let source: String
    let title: String
    let context: String
    let state: PetAnimationState
}

struct EventRouterSnapshot {
    let currentState: PetAnimationState
    let activeEventCount: Int
    let currentSource: String?
    let hasAction: Bool
    let activeThreads: [PetThreadSnapshot]
}
