import Foundation

// Keeps typing-driven searches from repeatedly using a project's API quota.
struct SearchRequestPacer {
    let minimumInterval: TimeInterval
    private(set) var lastAttemptAt: Date?
    private(set) var cooldownUntil: Date?
    private(set) var consecutiveRateLimits = 0

    init(minimumInterval: TimeInterval, cooldownUntil: Date? = nil) {
        self.minimumInterval = minimumInterval
        self.cooldownUntil = cooldownUntil
    }

    func waitDuration(at now: Date) -> TimeInterval {
        let afterSpacing = lastAttemptAt?.addingTimeInterval(minimumInterval) ?? .distantPast
        let allowedAt = max(afterSpacing, cooldownUntil ?? .distantPast)
        return max(0, allowedAt.timeIntervalSince(now))
    }

    mutating func recordAttempt(at now: Date) {
        lastAttemptAt = now
    }

    @discardableResult
    mutating func recordRateLimit(at now: Date) -> TimeInterval {
        consecutiveRateLimits += 1
        let exponent = min(consecutiveRateLimits - 1, 6)
        let delay = min(TimeInterval(60 * (1 << exponent)), 3600)
        cooldownUntil = now.addingTimeInterval(delay)
        return delay
    }

    mutating func recordSuccess() {
        consecutiveRateLimits = 0
        cooldownUntil = nil
    }
}
