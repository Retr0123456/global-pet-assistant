import Foundation
import Testing
@testable import GlobalPetAssistant

struct SourceRateLimiterTests {
    @Test
    func testDefaultSourceEventuallyReturnsDenied() {
        let limiter = SourceRateLimiter()

        for _ in 0..<20 {
            #expect(limiter.record(source: "spam-test") == nil)
        }

        #expect(limiter.record(source: "spam-test") != nil)
    }

    @Test
    func testCodexCLIUsesHigherConfiguredLimit() {
        let limiter = SourceRateLimiter()

        for _ in 0..<30 {
            #expect(limiter.record(source: "codex-cli") == nil)
        }

        #expect(limiter.record(source: "codex-cli") != nil)
    }

    @Test
    func testRetryAfterIsPositiveWhenDenied() {
        let limiter = SourceRateLimiter(
            policies: [:],
            defaultPolicy: SourceRateLimiter.Policy(maxEvents: 1, windowMs: 1_000)
        )

        #expect(limiter.record(source: "tool") == nil)
        let rejection = limiter.record(source: "tool")

        #expect(rejection?.retryAfterMs ?? 0 > 0)
    }

    @Test
    func testOldTimestampsFallOutOfWindow() {
        var now = Date(timeIntervalSince1970: 1_000)
        let limiter = SourceRateLimiter(
            policies: [:],
            defaultPolicy: SourceRateLimiter.Policy(maxEvents: 2, windowMs: 1_000),
            now: { now }
        )

        #expect(limiter.record(source: "tool") == nil)
        #expect(limiter.record(source: "tool") == nil)
        #expect(limiter.record(source: "tool") != nil)

        now = now.addingTimeInterval(1.1)
        #expect(limiter.record(source: "tool") == nil)
    }
}
