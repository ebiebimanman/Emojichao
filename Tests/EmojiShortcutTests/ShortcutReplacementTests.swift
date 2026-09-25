import AppKit
import XCTest
@testable import EmojiShortcut

final class ShortcutReplacementTests: XCTestCase {
    @MainActor
    func testCandidatePanelAppearsBelowCaretWhenThereIsRoom() {
        let origin = CandidatePanel.preferredOrigin(
            anchor: NSRect(x: 300, y: 500, width: 2, height: 20),
            panelSize: NSSize(width: 380, height: 280),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 800)
        )
        XCTAssertEqual(origin, NSPoint(x: 300, y: 214))
    }

    @MainActor
    func testCandidatePanelMovesAboveCaretAndStaysOnScreen() {
        let origin = CandidatePanel.preferredOrigin(
            anchor: NSRect(x: 1100, y: 100, width: 2, height: 20),
            panelSize: NSSize(width: 380, height: 280),
            visibleFrame: NSRect(x: 0, y: 0, width: 1200, height: 800)
        )
        XCTAssertEqual(origin, NSPoint(x: 820, y: 126))
    }

    func testJapaneseIMESelectsOnlyVisibleSuffix() {
        let prefix = "今日は誕生日でした:かっぷけーき"
        let range = ShortcutReplacement.suffixRange(
            in: prefix, start: 0, rawShortcut: ":kappuke-ki"
        )
        XCTAssertNotNil(range)
        let selected = (prefix as NSString).substring(with: NSRange(
            location: range!.location, length: range!.length
        ))
        XCTAssertEqual(selected, ":かっぷけーき")
    }

    func testDoesNotMatchUnrelatedEnglishText() {
        XCTAssertNil(ShortcutReplacement.suffixRange(
            in: "今日は誕生日でした:other", start: 0, rawShortcut: ":cupcake"
        ))
    }

    func testDoesNotReachAcrossWhitespace() {
        XCTAssertNil(ShortcutReplacement.suffixRange(
            in: "前の:語 つづき", start: 0, rawShortcut: ":tsuzuki"
        ))
    }

    func testUsesNearestColonNotEarlierTime() {
        let text = "10:30集合ね :かっぷけーき"
        let range = ShortcutReplacement.suffixRange(
            in: text, start: 0, rawShortcut: ":kappuke-ki"
        )!
        XCTAssertEqual((text as NSString).substring(with: NSRange(
            location: range.location, length: range.length
        )), ":かっぷけーき")
    }

    func testContextUsesAtMostTenVisibleCharacters() {
        XCTAssertEqual(
            ShortcutReplacement.trailingContext(in: "今日はめっちゃ楽しかった〜 "),
            String("今日はめっちゃ楽しかった〜 ".suffix(10))
        )
        XCTAssertEqual(ShortcutReplacement.trailingContext(in: "短い "), "短い ")
        XCTAssertNil(ShortcutReplacement.trailingContext(in: ""))
    }

    func testContextIsReadAfterAndExcludesTrigger() {
        XCTAssertEqual(
            ShortcutReplacement.trailingContextBeforeTrigger(
                in: "めっちゃサイコー:", trigger: ":"
            ),
            "めっちゃサイコー"
        )
        XCTAssertEqual(
            ShortcutReplacement.trailingContextBeforeTrigger(
                in: "今日は本当にめっちゃサイコー：", trigger: "："
            ),
            String("今日は本当にめっちゃサイコー".suffix(10))
        )
        XCTAssertNil(ShortcutReplacement.trailingContextBeforeTrigger(
            in: "めっちゃサイコー", trigger: ":"
        ))
    }

    func testSearchableCharacterAcceptsQueryText() {
        XCTAssertTrue(ShortcutReplacement.isSearchableCharacter("s"))
        XCTAssertTrue(ShortcutReplacement.isSearchableCharacter("A"))
        XCTAssertTrue(ShortcutReplacement.isSearchableCharacter("よ"))
        XCTAssertTrue(ShortcutReplacement.isSearchableCharacter("1"))
    }

    func testSearchableCharacterRejectsKeysThatEndTheShortcut() {
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter(" "))
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter("\u{3000}"))
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter("\r"))
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter("\t"))
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter("\u{7f}"))
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter(":"))
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter("："))
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter(""))
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter("ab"))
    }

    func testSearchableCharacterRejectsArrowAndFunctionKeys() {
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter("\u{F701}"))
        XCTAssertFalse(ShortcutReplacement.isSearchableCharacter("\u{F704}"))
    }

    func testTriggerUsesActualCharacterBoundary() {
        func boundary(_ previous: Character?, _ trigger: String = ":")
            -> ShortcutReplacement.TriggerBoundary {
            ShortcutReplacement.triggerBoundary(after: previous, trigger: trigger)
        }
        XCTAssertEqual(boundary(nil), .allowed)
        XCTAssertEqual(boundary(" "), .allowed)
        XCTAssertEqual(boundary("\u{3000}"), .allowed)
        XCTAssertEqual(boundary("\n"), .allowed)
        XCTAssertEqual(boundary(" ", "："), .allowed)
    }

    func testTriggerFollowsJapaneseTextWithoutSpace() {
        func boundary(_ previous: Character, _ trigger: String = ":")
            -> ShortcutReplacement.TriggerBoundary {
            ShortcutReplacement.triggerBoundary(after: previous, trigger: trigger)
        }
        XCTAssertEqual(boundary("ね"), .halfWidthOnly)
        XCTAssertEqual(boundary("文"), .halfWidthOnly)
        XCTAssertEqual(boundary("ー"), .halfWidthOnly)
        XCTAssertEqual(boundary("々"), .halfWidthOnly)
        XCTAssertEqual(boundary("！"), .halfWidthOnly)
        XCTAssertEqual(boundary("😀"), .halfWidthOnly)
        XCTAssertEqual(boundary("ね", "："), .rejected)
    }

    func testTriggerIgnoresTimesAndLatinWords() {
        XCTAssertEqual(ShortcutReplacement.triggerBoundary(after: "4", trigger: ":"), .rejected)
        XCTAssertEqual(ShortcutReplacement.triggerBoundary(after: "４", trigger: ":"), .rejected)
        XCTAssertEqual(ShortcutReplacement.triggerBoundary(after: "a", trigger: ":"), .rejected)
        XCTAssertEqual(ShortcutReplacement.triggerBoundary(after: "é", trigger: ":"), .rejected)
        XCTAssertEqual(ShortcutReplacement.triggerBoundary(after: ":", trigger: ":"), .rejected)
    }

    func testFullWidthTriggerInEditorIsProse() {
        XCTAssertTrue(ShortcutReplacement.lastTriggerIsFullWidth(in: "日時："))
        XCTAssertTrue(ShortcutReplacement.lastTriggerIsFullWidth(in: "日時：ｓ"))
        XCTAssertFalse(ShortcutReplacement.lastTriggerIsFullWidth(in: "集合ね:"))
        XCTAssertFalse(ShortcutReplacement.lastTriggerIsFullWidth(in: "日時：14時 集合ね:s"))
        XCTAssertFalse(ShortcutReplacement.lastTriggerIsFullWidth(in: "集合ね"))
    }

    func testNavigationInvalidatesFallbackTypingContext() {
        XCTAssertEqual(ShortcutReplacement.trackedCharacter(from: "a"), "a")
        XCTAssertEqual(ShortcutReplacement.trackedCharacter(from: " "), " ")
        XCTAssertEqual(ShortcutReplacement.trackedCharacter(from: "\n"), "\n")
        XCTAssertNil(ShortcutReplacement.trackedCharacter(from: "\t"))
        XCTAssertNil(ShortcutReplacement.trackedCharacter(from: "\u{7f}"))
        XCTAssertNil(ShortcutReplacement.trackedCharacter(from: "\u{F701}"))
        XCTAssertNil(ShortcutReplacement.trackedCharacter(from: ""))
    }
}
