import Foundation

/// Reorders a kana-kanji converter's candidates where its scores are close
/// but the winner reads badly. The converter (AzooKey on iOS) scores whole
/// paths through its lattice; a few kinds of path slip through often enough
/// to be worth catching:
///
/// - Lone kanji glued between grammar: 翌|幾 for よくいく, 何が向いて|総 for
///   なにがむいてそ(う), 世|任 for よにん. A one-character word with no
///   particle after it is usually a rare reading that happened to fit the
///   kana (猫が, 君の are left alone).
/// - The lattice falling back to kana: よく|したい over 良くしたい. A
///   hiragana path made of several pieces isn't a word choice, so a kanji
///   spelling that's about as likely goes first (the kana stays listed).
/// - Mixed numerals: 4人の中で一番. Once a counter is in digits, the
///   all-digit spelling (4人の中で1番) wins.
/// - Predictions ahead of the reading: いい → いいっ, かわいい → 可愛いい.
///   Conversions of exactly what was typed come first.
///
/// The penalties are a few points of the converter's log-scale score, so
/// they only settle near ties; a clearly better path keeps its place.
public enum ConversionRanking {
    public struct Segment: Equatable, Sendable {
        public let word: String
        /// Katakana reading of `word`.
        public let ruby: String

        public init(word: String, ruby: String) {
            self.word = word
            self.ruby = ruby
        }
    }

    public struct Candidate: Equatable, Sendable {
        public let text: String
        /// The converter's score; higher is better.
        public let value: Double
        /// How many characters of the reading it covers; more than the
        /// reading's length means a prediction.
        public let rubyCount: Int
        public let segments: [Segment]

        public init(text: String, value: Double, rubyCount: Int, segments: [Segment]) {
            self.text = text
            self.value = value
            self.rubyCount = rubyCount
            self.segments = segments
        }
    }

    static let loneKanjiPenalty = 1.5
    static let kanaPathPenalty = 1.5
    static let mixedNumeralPenalty = 1.0

    /// The order to show `candidates` in, as indices into it.
    /// - Parameter reading: The hiragana typed, e.g. "よくしたい".
    public static func order(_ candidates: [Candidate], reading: String) -> [Int] {
        let length = reading.count
        // The converter lists its whole-reading paths best first, then
        // extras (plain kana, katakana) scored on another scale. Only that
        // first sorted run is comparable.
        var block: [Int] = []
        for index in candidates.indices where candidates[index].rubyCount == length {
            if let last = block.last, candidates[index].value > candidates[last].value { break }
            block.append(index)
        }
        let texts = Set(block.map { candidates[$0].text })
        var scores: [Int: Double] = [:]
        for index in block {
            let candidate = candidates[index]
            scores[index] = candidate.value - penalty(for: candidate, reading: reading, alternatives: texts)
        }
        // Block indices ascend, so comparing them keeps ties in order.
        let ranked = block.sorted { left, right in
            let leftScore = scores[left] ?? 0
            let rightScore = scores[right] ?? 0
            return leftScore == rightScore ? left < right : leftScore > rightScore
        }
        let taken = Set(block)
        return ranked + candidates.indices.filter { !taken.contains($0) }
    }

    static func penalty(for candidate: Candidate, reading: String, alternatives: Set<String>) -> Double {
        var result = 0.0
        if candidate.segments.count > 1 {
            let segments = candidate.segments
            for (position, segment) in segments.enumerated() where isLoneKanji(segment.word) {
                // 猫が, 君の, 後で: a noun taking a particle is a real use.
                let next = segments.indices.contains(position + 1) ? segments[position + 1].word.first : nil
                if let next, particles.contains(next) { continue }
                result += loneKanjiPenalty
            }
            if candidate.text == reading { result += kanaPathPenalty }
        }
        if let digits = digitized(candidate.text), alternatives.contains(digits) {
            result += mixedNumeralPenalty
        }
        return result
    }

    private static let particles: Set<Character> = ["の", "が", "は", "を", "に", "で", "と", "も", "へ", "や"]

    /// A word that is a single kanji (猫 counts; 猫の, 4人 don't).
    static func isLoneKanji(_ word: String) -> Bool {
        guard word.count == 1, let scalar = word.unicodeScalars.first else { return false }
        return scalar.properties.isIdeographic
    }

    private static let kanjiDigits: [Character: Character] = [
        "一": "1", "二": "2", "三": "3", "四": "4", "五": "5",
        "六": "6", "七": "7", "八": "8", "九": "9"
    ]

    /// `text` with its kanji numerals as digits, if it mixes the two
    /// (4人の中で一番 → 4人の中で1番); nil otherwise.
    static func digitized(_ text: String) -> String? {
        guard text.contains(where: \.isASCIIDigit), text.contains(where: { kanjiDigits[$0] != nil }) else { return nil }
        return String(text.map { kanjiDigits[$0] ?? $0 })
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
