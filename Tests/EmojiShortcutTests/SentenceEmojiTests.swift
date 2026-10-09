import XCTest
@testable import EmojiCatalogCore

final class SentenceEmojiTests: XCTestCase {
    private let index = EmojiSearchIndex(entries: [
        EmojiEntry(emoji: "🍖", name: "骨付き肉", englishName: "meat on bone", keywords: ["肉", "焼肉"]),
        EmojiEntry(emoji: "😆", name: "きゃー", englishName: "grinning squinting face", keywords: ["楽しい", "嬉しい", "笑"]),
        EmojiEntry(emoji: "😭", name: "号泣", englishName: "loudly crying face", keywords: ["泣く", "悲しい"]),
        EmojiEntry(emoji: "🐱", name: "猫", englishName: "cat face", keywords: ["ねこ", "cat"]),
        EmojiEntry(emoji: "🌽", name: "とうもろこし", englishName: "ear of corn", keywords: ["と", "corn"])
    ])

    func testSentenceEndingMarks() {
        XCTAssertTrue(SentenceContext.endsSentence("楽しかった！"))
        XCTAssertTrue(SentenceContext.endsSentence("行く？"))
        XCTAssertTrue(SentenceContext.endsSentence("またね～"))
        XCTAssertFalse(SentenceContext.endsSentence("楽しかった"))
        XCTAssertFalse(SentenceContext.endsSentence(""))
    }

    func testLastSentenceTakesOnlyTheNewestOne() {
        XCTAssertEqual(SentenceContext.lastSentence(in: "おはよう。今日は焼肉で楽しかった！"), "今日は焼肉で楽しかった！")
        XCTAssertEqual(SentenceContext.lastSentence(in: "昨日は雨\n猫かわいい "), "猫かわいい")
        XCTAssertEqual(SentenceContext.lastSentence(in: "あいうえお", maxLength: 3), "うえお")
        XCTAssertNil(SentenceContext.lastSentence(in: "楽しかった😆"), "絵文字を付けた後は提案しない")
        XCTAssertNil(SentenceContext.lastSentence(in: "。！"))
        XCTAssertNil(SentenceContext.lastSentence(in: ""))
    }

    func testSentenceMatchesCombineWordsAndConjugations() {
        let results = index.sentenceMatches("今日は焼肉で楽しかった！").map(\.emoji)
        XCTAssertEqual(Set(results), ["😆", "🍖"])
        // The feeling at the end outranks the food in the middle.
        XCTAssertEqual(results.first, "😆")
        XCTAssertEqual(index.sentenceMatches("映画で泣いた").map(\.emoji), ["😭"])
    }

    func testSentenceMatchesIgnoreLoneKanaAndEnglish() {
        XCTAssertEqual(index.sentenceMatches("ねこと遊んだ").map(\.emoji), ["🐱"])
        XCTAssertTrue(index.sentenceMatches("i love my cat").isEmpty)
    }

    func testWordSearchMatchesCatalogOrder() {
        XCTAssertEqual(index.ranked([.init("ねこ", weight: 1)]).map(\.emoji), ["🐱"])
        XCTAssertEqual(index.ranked([.init("cat", weight: 1)]).map(\.emoji), ["🐱"])
        XCTAssertEqual(index.entry(for: "🍖")?.name, "骨付き肉")
    }
}
