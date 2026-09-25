import CoreGraphics
import XCTest
@testable import EmojiShortcut

final class UnicodeTextInjectionTests: XCTestCase {
    func testEmojiIsStoredAsUnicodeEventPayloadWithoutPasteboard() async {
        let value = await MainActor.run { () -> String? in
            guard let events = UnicodeTextInjection.makeEvents(text: "🤓") else {
                return nil
            }
            return UnicodeTextInjection.unicodeString(from: events.keyDown)
        }
        XCTAssertEqual(value, "🤓")
    }

    func testMultipleGraphemeClustersRoundTripThroughEvent() async {
        let value = await MainActor.run { () -> String? in
            guard let events = UnicodeTextInjection.makeEvents(text: "👨‍👩‍👧‍👦✨") else {
                return nil
            }
            return UnicodeTextInjection.unicodeString(from: events.keyDown)
        }
        XCTAssertEqual(value, "👨‍👩‍👧‍👦✨")
    }

    func testEmptyTextDoesNotCreateEvents() async {
        let eventsAreNil = await MainActor.run {
            UnicodeTextInjection.makeEvents(text: "") == nil
        }
        XCTAssertTrue(eventsAreNil)
    }
}
