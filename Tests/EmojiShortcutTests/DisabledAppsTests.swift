import XCTest
@testable import EmojiShortcut

final class DisabledAppsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DisabledAppsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNoAppIsDisabledByDefault() {
        XCTAssertEqual(DisabledApps.identifiers(using: defaults), [])
        XCTAssertFalse(DisabledApps.isDisabled("com.tinyspeck.slackmacgap", using: defaults))
    }

    func testDisablingAndReenablingOneApp() {
        DisabledApps.setDisabled(true, for: "com.tinyspeck.slackmacgap", using: defaults)
        XCTAssertTrue(DisabledApps.isDisabled("com.tinyspeck.slackmacgap", using: defaults))
        XCTAssertFalse(DisabledApps.isDisabled("com.apple.Notes", using: defaults))

        DisabledApps.setDisabled(false, for: "com.tinyspeck.slackmacgap", using: defaults)
        XCTAssertFalse(DisabledApps.isDisabled("com.tinyspeck.slackmacgap", using: defaults))
        XCTAssertEqual(DisabledApps.identifiers(using: defaults), [])
    }

    func testBundleIdentifiersMatchRegardlessOfCase() {
        DisabledApps.setDisabled(true, for: "com.hnc.Discord", using: defaults)
        XCTAssertTrue(DisabledApps.isDisabled("com.hnc.discord", using: defaults))
        // The stored spelling survives so the settings list stays readable
        // when the app is not installed on this Mac.
        XCTAssertEqual(DisabledApps.identifiers(using: defaults), ["com.hnc.Discord"])

        DisabledApps.setDisabled(true, for: "COM.HNC.DISCORD", using: defaults)
        XCTAssertEqual(DisabledApps.identifiers(using: defaults), ["com.hnc.Discord"])

        DisabledApps.setDisabled(false, for: "com.hnc.discord", using: defaults)
        XCTAssertEqual(DisabledApps.identifiers(using: defaults), [])
    }

    func testEmptyAndMissingIdentifiersAreIgnored() {
        DisabledApps.setDisabled(true, for: nil, using: defaults)
        DisabledApps.setDisabled(true, for: "   ", using: defaults)
        XCTAssertEqual(DisabledApps.identifiers(using: defaults), [])
        XCTAssertFalse(DisabledApps.isDisabled(nil, using: defaults))
        XCTAssertFalse(DisabledApps.isDisabled("", using: defaults))
    }

    func testIdentifiersKeepOrderAndDropStoredDuplicates() {
        defaults.set(
            ["com.tinyspeck.slackmacgap", " com.hnc.Discord ", "com.tinyspeck.slackmacgap", ""],
            forKey: DisabledApps.defaultsKey
        )
        XCTAssertEqual(
            DisabledApps.identifiers(using: defaults),
            ["com.tinyspeck.slackmacgap", "com.hnc.Discord"]
        )
    }

    func testChangeNotificationIsPostedOnlyWhenTheListChanges() {
        var changes = 0
        let observer = NotificationCenter.default.addObserver(
            forName: DisabledApps.didChangeNotification, object: nil, queue: nil
        ) { _ in changes += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        DisabledApps.setDisabled(true, for: "com.tinyspeck.slackmacgap", using: defaults)
        XCTAssertEqual(changes, 1)
        DisabledApps.setDisabled(true, for: "com.tinyspeck.slackmacgap", using: defaults)
        XCTAssertEqual(changes, 1)
        DisabledApps.setDisabled(false, for: "com.apple.Notes", using: defaults)
        XCTAssertEqual(changes, 1)
        DisabledApps.setDisabled(false, for: "com.tinyspeck.slackmacgap", using: defaults)
        XCTAssertEqual(changes, 2)
    }
}
