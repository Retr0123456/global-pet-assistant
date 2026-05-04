import Foundation

final class SourceRateLimiter {
    struct Policy {
        let maxEvents: Int
        let windowMs: Int
    }

    struct Rejection {
        let retryAfterMs: Int
    }

    private let policies: [String: Policy]
    private let defaultPolicy: Policy
    private let now: () -> Date
    private let lock = NSLock()
    private var acceptedEventsBySource: [String: [Date]] = [:]

    init(
        policies: [String: Policy] = [
            "codex-cli": Policy(maxEvents: 30, windowMs: 60_000),
            "claude-code": Policy(maxEvents: 30, windowMs: 60_000),
            "ci": Policy(maxEvents: 10, windowMs: 60_000)
        ],
        defaultPolicy: Policy = Policy(maxEvents: 20, windowMs: 60_000),
        now: @escaping () -> Date = Date.init
    ) {
        self.policies = policies
        self.defaultPolicy = defaultPolicy
        self.now = now
    }

    func record(source rawSource: String) -> Rejection? {
        let source = normalizedSource(rawSource)
        let policy = policies[source] ?? defaultPolicy
        let currentDate = now()
        let windowSeconds = TimeInterval(policy.windowMs) / 1000

        lock.lock()
        defer {
            lock.unlock()
        }

        let retainedEvents = (acceptedEventsBySource[source] ?? []).filter {
            currentDate.timeIntervalSince($0) < windowSeconds
        }

        guard retainedEvents.count >= policy.maxEvents else {
            acceptedEventsBySource[source] = retainedEvents + [currentDate]
            return nil
        }

        let oldestAcceptedEvent = retainedEvents.min() ?? currentDate
        let elapsedMs = Int(currentDate.timeIntervalSince(oldestAcceptedEvent) * 1000)
        let retryAfterMs = max(1, policy.windowMs - elapsedMs)
        acceptedEventsBySource[source] = retainedEvents
        return Rejection(retryAfterMs: retryAfterMs)
    }

    private func normalizedSource(_ rawSource: String) -> String {
        let trimmed = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }
}
