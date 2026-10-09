import XCTest
@testable import EmojiCatalogCore

/// Candidate lists as AzooKeyKanaKanjiConverter 0.11.2 returns them for
/// each reading (typo correction off, as the keyboard runs it), trimmed to
/// the interesting rows. "|" splits the converter's segments, each
/// word/ルビ.
final class ConversionRankingTests: XCTestCase {
    private func candidate(_ path: String, _ value: Double) -> ConversionRanking.Candidate {
        let segments = path.split(separator: "|").map { part -> ConversionRanking.Segment in
            let pieces = part.split(separator: "/")
            return .init(word: String(pieces[0]), ruby: String(pieces[1]))
        }
        return .init(
            text: segments.map(\.word).joined(),
            value: value,
            rubyCount: segments.map(\.ruby.count).reduce(0, +),
            segments: segments
        )
    }

    private func ranked(_ candidates: [ConversionRanking.Candidate], reading: String) -> [String] {
        ConversionRanking.order(candidates, reading: reading).map { candidates[$0].text }
    }

    func testKanjiSpellingBeatsHiraganaFallbackPath() {
        let texts = ranked([
            candidate("よく/ヨク|したい/シタイ", -23.1951),
            candidate("良くし/ヨクシ|たい/タイ", -24.0738),
            candidate("抑止/ヨクシ|隊/タイ", -24.1338),
            candidate("翌/ヨク|死体/シタイ", -24.4527),
            candidate("よくしたい/ヨクシタイ", -14.5)
        ], reading: "よくしたい")
        XCTAssertEqual(texts.first, "良くしたい")
        XCTAssertTrue(texts.contains("よくしたい"), "ひらがなは候補に残す")
        XCTAssertLessThan(texts.firstIndex(of: "よくしたい")!, texts.firstIndex(of: "抑止隊")!)
    }

    func testLoneKanjiDoesNotSwallowAuxiliary() {
        let texts = ranked([
            candidate("何が/ナニガ|向いて/ムイテ|総/ソウ|？/？", -42.9),
            candidate("何が/ナニガ|向い/ムイ|てそう/テソウ|？/？", -43.1515),
            candidate("なにが/ナニガ|向い/ムイ|てそう/テソウ|？/？", -44.7344),
            candidate("何/ナニ|が/ガ", -16.2306),
            candidate("なにがむいてそう？/ナニガムイテソウ？", -14.5)
        ], reading: "なにがむいてそう？")
        XCTAssertEqual(texts.first, "何が向いてそう？")
        XCTAssertTrue(texts.contains("なにがむいてそう？"))
    }

    func testAllDigitCountersBeatMixedNumerals() {
        let texts = ranked([
            candidate("4人/ヨニン|の中で/ノナカデ|一番/イチバン", -36.6494),
            candidate("世/ヨ|任/ニン|の中で/ノナカデ|1番/イチバン", -36.9),
            candidate("4人/ヨニン|の中で/ノナカデ|1番/イチバン", -37.2567),
            candidate("4人/ヨニン|のなかで/ノナカデ|一番/イチバン", -38.8212),
            candidate("余人/ヨニン|の中で/ノナカデ|1番/イチバン", -39.2775),
            candidate("よにんのなかでいちばん/ヨニンノナカデイチバン", -14.5)
        ], reading: "よにんのなかでいちばん")
        XCTAssertEqual(texts.first, "4人の中で1番")
        XCTAssertEqual(texts[1], "4人の中で一番")
        XCTAssertTrue(texts.contains("よにんのなかでいちばん"))
    }

    func testCorrectTopCandidateKeepsItsPlace() {
        let texts = ranked([
            candidate("強いて/シイテ|言う/イウ|なら/ナラ", -32.166),
            candidate("敷い/シイ|て言う/テイウ|なら/ナラ", -32.4566),
            candidate("強いて/シイテ|いう/イウ|なら/ナラ", -32.6423),
            candidate("しい/シイ|ていう/テイウ|なら/ナラ", -33.0799),
            candidate("しいていうなら/シイテイウナラ", -14.5)
        ], reading: "しいていうなら")
        XCTAssertEqual(texts.first, "強いて言うなら")
        XCTAssertTrue(texts.contains("しいていうなら"))
    }

    func testExactConversionsComeBeforePredictions() {
        // かわいい: the converter put a prediction (可愛いい, ルビ カワイイー)
        // ahead of the word itself.
        let texts = ranked([
            candidate("可愛いい/カワイイー", -8.6993),
            candidate("可愛い/カワイイ", -9.2),
            candidate("かわいい/カワイイ", -10.1)
        ], reading: "かわいい")
        XCTAssertEqual(texts, ["可愛い", "かわいい", "可愛いい"])
    }

    func testNounsTakingParticlesAreNotPenalized() {
        let texts = ranked([
            candidate("君/キミ|のことが/ノコトガ|好き/スキ", -20.0),
            candidate("気味/キミ|のことが/ノコトガ|好き/スキ", -20.5)
        ], reading: "きみのことがすき")
        XCTAssertEqual(texts.first, "君のことが好き")
    }
}
