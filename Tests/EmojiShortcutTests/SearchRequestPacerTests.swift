import XCTest
@testable import EmojiCatalogCore

final class SearchRequestPacerTests: XCTestCase {
    func testSpacesRequestsByTenSeconds() {
        var pacer = SearchRequestPacer(minimumInterval: 10)
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(pacer.waitDuration(at: now), 0)
        pacer.recordAttempt(at: now)
        XCTAssertEqual(pacer.waitDuration(at: now), 10)
        XCTAssertEqual(pacer.waitDuration(at: now.addingTimeInterval(11)), 0)
    }

    func testRateLimitBackoffAndSuccessReset() {
        var pacer = SearchRequestPacer(minimumInterval: 10)
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(pacer.recordRateLimit(at: now), 60)
        XCTAssertEqual(pacer.waitDuration(at: now), 60)
        XCTAssertEqual(pacer.recordRateLimit(at: now), 120)
        XCTAssertEqual(pacer.waitDuration(at: now), 120)
        pacer.recordSuccess()
        XCTAssertEqual(pacer.waitDuration(at: now), 0)
        XCTAssertEqual(pacer.recordRateLimit(at: now), 60)
    }

    func testJevUsesShorterSpacingButSameRateLimitBackoff() {
        var pacer = SearchRequestPacer(minimumInterval: 0.5)
        let now = Date(timeIntervalSince1970: 1_000)
        pacer.recordAttempt(at: now)
        XCTAssertEqual(pacer.waitDuration(at: now), 0.5)
        XCTAssertEqual(pacer.recordRateLimit(at: now), 60)
        XCTAssertEqual(pacer.waitDuration(at: now), 60)
    }
}
