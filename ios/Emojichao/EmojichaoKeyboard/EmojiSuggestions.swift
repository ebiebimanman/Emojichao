import EmojiCatalogCore
import Foundation

/// Fills the emoji row so it's never empty. The reading is searched as
/// typed and in katakana (はーと → ハート), alongside the top kanji
/// conversions (なく → 泣く); then, only if nothing matched, the reading's
/// last few characters (ねこかわいい → かわいい); then recently picked and
/// popular emoji.
///
/// Scoring touches every catalog entry once per query, so it runs on a
/// background task (see KeyboardViewController.searchLocal); nothing here
/// needs the main thread except building the index from the catalog.
enum EmojiSuggestions {
    static let limit = 12

    /// What a search found: `entries` is what to show, padded out with
    /// recent and popular emoji; `matched` says whether any of it actually
    /// matched, or it's all padding.
    struct Result: Sendable {
        let entries: [EmojiEntry]
        let matched: Bool
    }

    private static let recentKey = "RecentEmoji"
    private static let popular = ["😊", "😂", "🥹", "👍", "❤️", "🙏", "🎉", "😭", "✨", "🤔", "👀", "🥺"]
    /// How many kanji conversions to search, best first.
    private static let conversionsSearched = 8

    /// The catalog lives on the main actor; the index built from it doesn't.
    @MainActor
    static func makeIndex() -> Task<EmojiSearchIndex, Never> {
        let entries = EmojiCatalog.shared.searchableEntries
        return Task.detached(priority: .userInitiated) { EmojiSearchIndex(entries: entries) }
    }

    /// - Parameters:
    ///   - reading: The kana (or ABC word) as typed.
    ///   - conversions: Kanji conversions of exactly the reading, best
    ///     first (not predictions that run past it).
    ///   - recent: `recent()`, read beforehand on the main thread.
    static func candidates(
        for reading: String, conversions: [String] = [],
        in index: EmojiSearchIndex, recent: [String]
    ) -> Result {
        var queries = [EmojiSearchIndex.Query(reading, weight: 1)]
        if let katakana = reading.applyingTransform(.hiraganaToKatakana, reverse: false), katakana != reading {
            queries.append(.init(katakana, weight: 1))
        }
        // Later conversions count a little less: 無く・泣く・鳴く are all
        // plausible for なく, but the dictionary's order is a hint.
        for (rank, text) in conversions.prefix(conversionsSearched).enumerated() where text != reading {
            queries.append(.init(text, weight: 0.95 - Double(rank) * 0.04))
        }

        var results = index.ranked(queries)
        if results.isEmpty {
            // Longest tail first, but never a lone character: "と" or "く"
            // matches half the catalog (🌽 とうもろこし, 🤧 くしゃみ).
            var tail = Substring(reading).suffix(6)
            while results.isEmpty, tail.count > 2, !Task.isCancelled {
                tail = tail.dropFirst()
                let text = String(tail)
                var tailQueries = [EmojiSearchIndex.Query(text, weight: 0.5)]
                if let katakana = text.applyingTransform(.hiraganaToKatakana, reverse: false), katakana != text {
                    tailQueries.append(.init(katakana, weight: 0.5))
                }
                results = index.ranked(tailQueries)
            }
        }
        return padded(results, in: index, recent: recent)
    }

    /// Emoji for the whole sentence just written (今日は焼肉で楽しかった！),
    /// or nothing: padding with popular emoji would hide that none fit.
    static func sentenceCandidates(for sentence: String, in index: EmojiSearchIndex) -> [EmojiEntry] {
        index.sentenceMatches(sentence, limit: limit)
    }

    /// Recently picked emoji, then popular ones.
    static func fallback(in index: EmojiSearchIndex, recent: [String]) -> [EmojiEntry] {
        let wanted = recent + popular
        var seen = Set<String>()
        return wanted.compactMap { emoji in
            guard seen.insert(emoji).inserted else { return nil }
            return index.entry(for: emoji) ?? index.entry(for: emoji.replacingOccurrences(of: "\u{FE0F}", with: ""))
        }
    }

    static func recordPick(_ entry: EmojiEntry) {
        var recent = recent().filter { $0 != entry.emoji }
        recent.insert(entry.emoji, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(limit)), forKey: recentKey)
    }

    static func recent() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    private static func padded(_ matches: [EmojiEntry], in index: EmojiSearchIndex, recent: [String]) -> Result {
        var entries = matches
        var seen = Set(entries.map(\.emoji))
        for entry in fallback(in: index, recent: recent) where entries.count < limit && seen.insert(entry.emoji).inserted {
            entries.append(entry)
        }
        return Result(entries: Array(entries.prefix(limit)), matched: !matches.isEmpty)
    }
}
