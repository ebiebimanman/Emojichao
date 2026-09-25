import Foundation

// Keeps typing-driven searches from repeatedly using a project's API quota.
public struct SearchRequestPacer {
    public let minimumInterval: TimeInterval
    public private(set) var lastAttemptAt: Date?
    public private(set) var cooldownUntil: Date?
    public private(set) var consecutiveRateLimits = 0

    public init(minimumInterval: TimeInterval, cooldownUntil: Date? = nil) {
        self.minimumInterval = minimumInterval
        self.cooldownUntil = cooldownUntil
    }

    public func waitDuration(at now: Date) -> TimeInterval {
        let afterSpacing = lastAttemptAt?.addingTimeInterval(minimumInterval) ?? .distantPast
        let allowedAt = max(afterSpacing, cooldownUntil ?? .distantPast)
        return max(0, allowedAt.timeIntervalSince(now))
    }

    public mutating func recordAttempt(at now: Date) {
        lastAttemptAt = now
    }

    @discardableResult
    public mutating func recordRateLimit(at now: Date) -> TimeInterval {
        consecutiveRateLimits += 1
        let exponent = min(consecutiveRateLimits - 1, 6)
        let delay = min(TimeInterval(60 * (1 << exponent)), 3600)
        cooldownUntil = now.addingTimeInterval(delay)
        return delay
    }

    public mutating func recordSuccess() {
        consecutiveRateLimits = 0
        cooldownUntil = nil
    }
}
