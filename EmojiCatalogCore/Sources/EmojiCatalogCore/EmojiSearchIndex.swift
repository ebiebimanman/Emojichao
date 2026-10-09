import Foundation

/// The catalog's names and keywords, lowercased once, and the keyboard's
/// scoring over them. A plain value with no actor, so searches run on a
/// background task: scoring every entry for a reading and its conversions
/// on the main thread held up the next key tap.
public struct EmojiSearchIndex: Sendable {
    public struct Query: Sendable, Equatable {
        public let text: String
        public let weight: Double

        public init(_ text: String, weight: Double) {
            self.text = text
            self.weight = weight
        }
    }

    private struct Item: Sendable {
        let entry: EmojiEntry
        /// The name, then the keywords, lowercased.
        let terms: [String]
    }

    private let items: [Item]
    private let positions: [String: Int]

    public init(entries: [EmojiEntry]) {
        items = entries.map { entry in
            Item(entry: entry, terms: ([entry.name] + entry.keywords).map { $0.lowercased() })
        }
        positions = Dictionary(
            items.enumerated().map { ($0.element.entry.emoji, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func entry(for emoji: String) -> EmojiEntry? {
        positions[emoji].map { items[$0].entry }
    }

    // MARK: - Word search

    /// Entries matching any query, best first; catalog order breaks ties.
    /// Returns early (with what it has) once the calling task is cancelled.
    public func ranked(_ queries: [Query]) -> [EmojiEntry] {
        var best: [Int: Double] = [:]
        for query in queries {
            if Task.isCancelled { break }
            let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !text.isEmpty else { continue }
            if text.unicodeScalars.allSatisfy(\.isASCII) {
                // English words keep the catalog's word-prefix rules, so
                // "omed" doesn't find the dromedary.
                for (rank, entry) in localMatches(text).enumerated() {
                    guard let position = positions[entry.emoji] else { continue }
                    best[position] = max(best[position] ?? 0, Double(250 - rank) * query.weight)
                }
                continue
            }
            for (position, item) in items.enumerated() {
                let score = Self.score(item.terms, for: text) * query.weight
                if score > 0 { best[position] = max(best[position] ?? 0, score) }
            }
        }
        return best
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { items[$0.key].entry }
    }

    /// Same matches and order as `EmojiCatalog.localMatches`.
    private func localMatches(_ query: String) -> [EmojiEntry] {
        var matches: [(entry: EmojiEntry, score: Int)] = []
        for item in items where item.entry.matchesLocalQuery(query) {
            matches.append((item.entry, item.entry.localMatchScore(query)))
        }
        matches.sort { $0.score == $1.score ? $0.entry.name < $1.entry.name : $0.score > $1.score }
        return matches.prefix(12).map(\.entry)
    }

    /// Exact beats prefix beats substring; a match on the name or an early
    /// keyword (the most representative ones) beats a late keyword.
    private static func score(_ terms: [String], for query: String) -> Double {
        var result = 0.0
        for (position, term) in terms.enumerated() {
            let base: Double
            if term == query {
                base = 300
            } else if term.hasPrefix(query) {
                base = 200
            } else if query.count >= 2, term.contains(query) {
                base = 100
            } else {
                continue
            }
            result = max(result, base - Double(min(position, 20)))
        }
        return result
    }

    // MARK: - Sentence search

    /// Emoji for a whole sentence (今日は焼肉で楽しかった！), from every
    /// catalog word that appears in it rather than one typed word. Longer
    /// words are more telling than short ones, words near the end (where
    /// Japanese puts the feeling) count more, and an entry matched by
    /// several words beats one matched by a single word.
    public func sentenceMatches(_ sentence: String, limit: Int = 12) -> [EmojiEntry] {
        let text = sentence.lowercased()
        let length = Double(max(text.count, 1))
        guard !text.isEmpty else { return [] }
        var scored: [(position: Int, score: Double)] = []
        for (position, item) in items.enumerated() {
            if Task.isCancelled { return [] }
            var best = 0.0
            var forms: [String] = []
            for (termIndex, term) in item.terms.enumerated() {
                guard let (form, weight) = Self.sentenceForm(of: term, in: text) else { continue }
                // Where the word starts, 0 (beginning) ... 1 (end).
                let start = text.range(of: form, options: .backwards)
                    .map { Double(text.distance(from: text.startIndex, to: $0.lowerBound)) / length } ?? 0
                let specificity = 100 + 40 * Double(min(form.count, 5)) - 2 * Double(min(termIndex, 20))
                best = max(best, specificity * weight * (0.5 + 0.5 * start))
                forms.append(form)
            }
            // 肉 inside 焼肉 is the same word, not a second one.
            let words = forms.filter { form in !forms.contains { $0 != form && $0.contains(form) } }
            if best > 0 {
                scored.append((position, best + 15 * Double(min(Set(words).count - 1, 3))))
            }
        }
        return scored
            .sorted { $0.score == $1.score ? $0.position < $1.position : $0.score > $1.score }
            .prefix(limit)
            .map { items[$0.position].entry }
    }

    /// Single-kanji keywords shared by whole families of emoji (人 by every
    /// person, 顔 by every face): in a sentence they're noise (4人, 笑顔).
    private static let genericKanji: Set<String> = [
        "人", "顔", "手", "目", "日", "中", "気", "物", "事", "時", "番", "一", "上", "下", "大", "小"
    ]

    /// How `term` shows up in `text`, if it does: as is, or by its stem when
    /// conjugated (楽しい in 楽しかった, 泣く in 泣いた).
    private static func sentenceForm(of term: String, in text: String) -> (form: String, weight: Double)? {
        // ASCII keywords are English; a lone kana ("と") matches anything.
        guard !term.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
        let hasKanji = term.unicodeScalars.contains(where: \.properties.isIdeographic)
        guard term.count >= 2 || (hasKanji && !genericKanji.contains(term)) else { return nil }
        if text.contains(term) {
            // A single kanji (肉 in 焼肉) says less than a word.
            return (term, term.count == 1 ? 0.7 : 1)
        }
        guard let last = term.unicodeScalars.last, (0x3041...0x3096).contains(last.value) else { return nil }
        let stem = String(term.dropLast())
        // 泣 is still telling; かわい is, か isn't.
        guard hasKanji ? !stem.isEmpty : stem.count >= 3, text.contains(stem) else { return nil }
        return (stem, 0.85)
    }
}
