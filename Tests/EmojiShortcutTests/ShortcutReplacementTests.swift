import XCTest
@testable import EmojiShortcut

final class ShortcutReplacementTests: XCTestCase {
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
}
