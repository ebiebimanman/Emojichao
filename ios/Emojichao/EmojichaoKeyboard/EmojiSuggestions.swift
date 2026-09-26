import EmojiCatalogCore
import Foundation

/// Fills the emoji row so it's never empty. The reading is searched as
/// typed and in katakana (はーと → ハート), alongside the top kanji
/// conversions (なく → 泣く); then, only if nothing matched, the reading's
/// last few characters (ねこかわいい → かわいい); then recently picked and
/// popular emoji.
@MainActor
enum EmojiSuggestions {
    static let limit = 12

    private static let recentKey = "RecentEmoji"
    private static let popular = ["😊", "😂", "🥹", "👍", "❤️", "🙏", "🎉", "😭", "✨", "🤔", "👀", "🥺"]
    /// How many kanji conversions to search, best first.
    private static let conversionsSearched = 8

    /// Load the catalog and build the search index ahead of the first
    /// keystroke; otherwise that keystroke pays for both and the key feels
    /// dead. Deferred a turn so the keyboard itself appears first.
    static func warmUp() {
        DispatchQueue.main.async {
            _ = index.count
            _ = byEmoji.count
        }
    }

    /// - Parameters:
    ///   - reading: The kana (or ABC word) as typed.
    ///   - conversions: Kanji conversions of exactly the reading, best
    ///     first (not predictions that run past it).
    static func candidates(for reading: String, conversions: [String] = []) -> [EmojiEntry] {
        var queries: [(text: String, weight: Double)] = [(reading, 1)]
        if let katakana = reading.applyingTransform(.hiraganaToKatakana, reverse: false), katakana != reading {
            queries.append((katakana, 1))
        }
        // Later conversions count a little less: 無く・泣く・鳴く are all
        // plausible for なく, but the dictionary's order is a hint.
        for (rank, text) in conversions.prefix(conversionsSearched).enumerated() where text != reading {
            queries.append((text, 0.95 - Double(rank) * 0.04))
        }

        var results = ranked(queries)
        if results.isEmpty {
            // Longest tail first, but never a lone character: "と" or "く"
            // matches half the catalog (🌽 とうもろこし, 🤧 くしゃみ).
            var tail = Substring(reading).suffix(6)
            while results.isEmpty, tail.count > 2 {
                tail = tail.dropFirst()
                let text = String(tail)
                var tailQueries: [(text: String, weight: Double)] = [(text, 0.5)]
                if let katakana = text.applyingTransform(.hiraganaToKatakana, reverse: false), katakana != text {
                    tailQueries.append((katakana, 0.5))
                }
                results = ranked(tailQueries)
            }
        }

        var seen = Set(results.map(\.emoji))
        for entry in fallback() where results.count < limit && seen.insert(entry.emoji).inserted {
            results.append(entry)
        }
        return Array(results.prefix(limit))
    }

    /// Recently picked emoji, then popular ones.
    static func fallback() -> [EmojiEntry] {
        let wanted = recent() + popular
        var seen = Set<String>()
        return wanted.compactMap { emoji in
            guard seen.insert(emoji).inserted else { return nil }
            return byEmoji[emoji] ?? byEmoji[emoji.replacingOccurrences(of: "\u{FE0F}", with: "")]
        }
    }

    static func recordPick(_ entry: EmojiEntry) {
        var recent = recent().filter { $0 != entry.emoji }
        recent.insert(entry.emoji, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(limit)), forKey: recentKey)
    }

    // MARK: - Scoring

    /// Each entry's name followed by its keywords, lowercased once.
    private static let index: [(entry: EmojiEntry, terms: [String])] =
        EmojiCatalog.shared.searchableEntries.map { entry in
            (entry, ([entry.name] + entry.keywords).map { $0.lowercased() })
        }

    private static let byEmoji = Dictionary(
        EmojiCatalog.shared.searchableEntries.map { ($0.emoji, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Entries matching any query, best first; catalog order breaks ties.
    private static func ranked(_ queries: [(text: String, weight: Double)]) -> [EmojiEntry] {
        var best: [Int: Double] = [:]
        for query in queries {
            let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !text.isEmpty else { continue }
            if text.unicodeScalars.allSatisfy(\.isASCII) {
                // English words keep the catalog's word-prefix rules, so
                // "omed" doesn't find the dromedary.
                let matches = EmojiCatalog.shared.localMatches(text)
                for (rank, entry) in matches.enumerated() {
                    guard let position = index.firstIndex(where: { $0.entry.emoji == entry.emoji }) else { continue }
                    best[position] = max(best[position] ?? 0, Double(250 - rank) * query.weight)
                }
                continue
            }
            for (position, item) in index.enumerated() {
                let score = Self.score(item.terms, for: text) * query.weight
                if score > 0 { best[position] = max(best[position] ?? 0, score) }
            }
        }
        return best
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { index[$0.key].entry }
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

    private static func recent() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }
}
