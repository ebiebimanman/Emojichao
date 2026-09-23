import XCTest
@testable import EmojiShortcut

final class IMECompositionTests: XCTestCase {
    func testDetectsTextThatCameFromAJapaneseIME() async {
        let results = await MainActor.run {
            [
                IMEComposition.containsJapanese("：いいかんじ"),
                IMEComposition.containsJapanese(":いい感じ"),
                IMEComposition.containsJapanese("：カップケーキ"),
                IMEComposition.containsJapanese("："),
                IMEComposition.containsJapanese(":iikanzi"),
                IMEComposition.containsJapanese(":tada")
            ]
        }
        XCTAssertEqual(results, [true, true, true, true, false, false])
    }
}
