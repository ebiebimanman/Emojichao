import Foundation

/// Finds the sentence just written, for emoji that fit it as a whole.
public enum SentenceContext {
    /// Marks that end a sentence in casual Japanese as well as English.
    public static let terminators: Set<Character> = ["。", "．", "！", "？", "!", "?", "～", "〜", "…", "♪"]

    /// Whether `text` (what's before the cursor) ends a sentence.
    public static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return terminators.contains(last)
    }

    /// The last sentence of `text`, ending marks included (they carry the
    /// tone: 行く？ vs 行く！), at most `maxLength` characters; nil when
    /// there's nothing worth searching for, or it already ends in emoji.
    public static func lastSentence(in text: String, maxLength: Int = 60) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !isEmoji(last) else { return nil }
        // Step back over the closing marks, then to the previous boundary.
        var start = trimmed.endIndex
        while start > trimmed.startIndex, terminators.contains(trimmed[trimmed.index(before: start)]) {
            start = trimmed.index(before: start)
        }
        while start > trimmed.startIndex {
            let previous = trimmed[trimmed.index(before: start)]
            if terminators.contains(previous) || previous.isNewline { break }
            start = trimmed.index(before: start)
        }
        let sentence = String(trimmed[start...].suffix(maxLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = sentence.filter { !terminators.contains($0) }
        return body.count >= 2 ? sentence : nil
    }

    private static func isEmoji(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first, first.properties.isEmoji else { return false }
        // Digits and # are "emoji" too; count them only as keycaps.
        return first.properties.isEmojiPresentation || character.unicodeScalars.count > 1
    }
}
