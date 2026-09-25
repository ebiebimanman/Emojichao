import EmojiCatalogCore
import Foundation

/// Fills the candidate strip so it's never empty: exact matches for the
/// word first, then matches for its tail (ねこかわいい → かわいい → …), then
/// recently picked and popular emoji.
@MainActor
enum EmojiSuggestions {
    static let limit = 12

    private static let recentKey = "RecentEmoji"
    private static let popular = ["😊", "😂", "🥹", "👍", "❤️", "🙏", "🎉", "😭", "✨", "🤔", "👀", "🥺"]

    static func candidates(for word: String) -> [EmojiEntry] {
        var results: [EmojiEntry] = []
        var seen = Set<String>()
        func add(_ entries: [EmojiEntry]) {
            for entry in entries where results.count < limit && seen.insert(entry.emoji).inserted {
                results.append(entry)
            }
        }

        let catalog = EmojiCatalog.shared
        add(catalog.localMatches(word))
        // Longest tail first: the word usually ends in what it's about.
        var tail = Substring(word)
        while results.isEmpty, tail.count > 1 {
            tail = tail.dropFirst()
            add(catalog.localMatches(String(tail)))
        }
        add(fallback())
        return results
    }

    /// Recently picked emoji, then popular ones.
    static func fallback() -> [EmojiEntry] {
        let wanted = recent() + popular
        let byEmoji = Dictionary(
            EmojiCatalog.shared.searchableEntries.map { ($0.emoji, $0) },
            uniquingKeysWith: { first, _ in first }
        )
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

    private static func recent() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }
}
