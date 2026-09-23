import AppKit
import XCTest
@testable import EmojiShortcut

final class KeyboardReplacementTests: XCTestCase {
    func testOneSharedReplacementPolicyCoversBrowserAndTerminalFallbacks() async {
        let strategies = await MainActor.run {
            [
                KeyboardReplacement.visibleTextStrategy(
                    hasInspectableElement: true, replacesSelectedText: true
                ),
                KeyboardReplacement.visibleTextStrategy(
                    hasInspectableElement: false, replacesSelectedText: false
                ),
                KeyboardReplacement.visibleTextStrategy(
                    hasInspectableElement: true, replacesSelectedText: false
                )
            ]
        }
        XCTAssertEqual(strategies, [
            .verifiedKeyboardSelection,
            .verifiedKeyboardSelection,
            .verifiedDeletion
        ])
    }

    func testOnlyASCIIShortcodesAreEligible() async {
        let results = await MainActor.run {
            [
                KeyboardReplacement.canReplace(":happy"),
                KeyboardReplacement.canReplace(":face_holding_back_tears"),
                KeyboardReplacement.canReplace(":tada"),
                KeyboardReplacement.canReplace(":かっぷけーき"),
                KeyboardReplacement.canReplace(":happy "),
                KeyboardReplacement.canReplace("happy"),
                KeyboardReplacement.canReplace(":")
            ]
        }
        XCTAssertEqual(results, [true, true, true, false, false, false, true])
    }

    func testPasteboardSnapshotRestoresMultipleTypes() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString("original", forType: .string))
        let customType = NSPasteboard.PasteboardType("com.emoji-shortcut.test-data")
        XCTAssertTrue(item.setData(Data([1, 2, 3]), forType: customType))
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        XCTAssertNotNil(snapshot)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("temporary", forType: .string))
        XCTAssertTrue(snapshot!.restore(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: customType), Data([1, 2, 3]))
    }
}
