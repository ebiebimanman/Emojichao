import Foundation

struct EmojiEntry: Codable, Hashable, Sendable {
    let emoji: String
    let name: String
    let englishName: String
    let keywords: [String]

    var description: String {
        // Keep the prompt small: the first keywords are the Japanese ones, and
        // the English meaning is already carried by englishName.
        let terms = keywords.prefix(8).joined(separator: ", ")
        return "\(emoji) — \(name) / \(englishName); \(terms)"
    }

    var isFlag: Bool {
        emoji.unicodeScalars.contains {
            (0x1F1E6...0x1F1FF).contains($0.value) ||
            (0xE0020...0xE007F).contains($0.value)
        }
    }

    func matchesLocalQuery(_ query: String) -> Bool {
        if query.unicodeScalars.allSatisfy(\.isASCII) {
            // A shortcode prefix must start a word or alias. Matching inside
            // "dromedary" made :omed incorrectly suggest the camel emoji.
            return name.lowercased().hasPrefix(query) ||
                englishName.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .contains { $0.hasPrefix(query) } ||
                keywords.contains { $0.lowercased().hasPrefix(query) }
        }
        return name.localizedCaseInsensitiveContains(query) ||
            englishName.localizedCaseInsensitiveContains(query) ||
            keywords.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

@MainActor
final class EmojiCatalog {
    static let shared = EmojiCatalog()
    private(set) var entries: [EmojiEntry] = []

    var searchableEntries: [EmojiEntry] {
        entries.filter { !$0.isFlag }
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EmojiShortcut/emoji-catalog-curated.json")
        let urls = [
            appSupport,
            Bundle.module.url(forResource: "emoji-catalog-curated", withExtension: "json"),
            Bundle.module.url(forResource: "emoji-catalog", withExtension: "json")
        ].compactMap { $0 }
        for url in urls {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([EmojiEntry].self, from: data) {
                entries = decoded
                break
            }
        }
    }

    func localMatches(_ query: String) -> [EmojiEntry] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // An empty query matches nothing. The trigger ':' alone must not
        // produce candidates.
        guard !normalized.isEmpty else { return [] }
        let matches = searchableEntries.filter { $0.matchesLocalQuery(normalized) }
        return matches.sorted {
            let leftScore = localMatchScore($0, query: normalized)
            let rightScore = localMatchScore($1, query: normalized)
            return leftScore == rightScore ? $0.name < $1.name : leftScore > rightScore
        }.prefix(12).map { $0 }
    }

    private func localMatchScore(_ entry: EmojiEntry, query: String) -> Int {
        let name = entry.name.lowercased()
        let englishWords = entry.englishName.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let keywords = entry.keywords.map { $0.lowercased() }
        if name == query || englishWords.contains(query) || keywords.contains(query) { return 300 }
        if name.hasPrefix(query) || englishWords.contains(where: { $0.hasPrefix(query) }) { return 200 }
        return keywords.contains(where: { $0.hasPrefix(query) }) ? 100 : 0
    }
}
