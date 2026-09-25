import Foundation

public enum EmojiSearchPolicy {
    public struct TextSearchResume: Equatable {
        public let shortcut: String
        public let query: String
    }

    @frozen public enum SelectionAction: Equatable {
        case select
        case waitForSearch
        case passThrough
    }

    public static func selectionAction(candidateCount: Int, searchPending: Bool) -> SelectionAction {
        if candidateCount > 0 { return .select }
        return searchPending ? .waitForSearch : .passThrough
    }

    public static func usesContextSearch(requested: Bool, query: String, hasContext: Bool) -> Bool {
        requested && query.isEmpty && hasContext
    }

    public static func shouldAutoApplyFirstCandidate(isContextMode: Bool, candidateCount: Int) -> Bool {
        isContextMode && candidateCount > 0
    }

    public static func shouldShowPanel(query: String, isContextMode: Bool) -> Bool {
        !query.isEmpty && !isContextMode
    }

    /// A character that can begin a search word. Arrow and function keys arrive
    /// as private-use scalars, and Return, Tab and Delete as control
    /// characters. None of them belong in a query, and neither does a space,
    /// which ends the shortcut, nor another ':', which starts a new one.
    public static func isSearchableCharacter(_ characters: String) -> Bool {
        guard characters.count == 1, let scalar = characters.unicodeScalars.first else { return false }
        if characters == ":" || characters == "：" { return false }
        if (0xF700...0xF8FF).contains(scalar.value) { return false }
        let rejected = CharacterSet.controlCharacters
            .union(.whitespacesAndNewlines)
            .union(.illegalCharacters)
        return !rejected.contains(scalar)
    }

    public static func textSearchResume(shortcut: String, characters: String) -> TextSearchResume? {
        guard isSearchableCharacter(characters) else { return nil }
        let resumedShortcut = shortcut + characters
        return TextSearchResume(
            shortcut: resumedShortcut,
            query: String(resumedShortcut.dropFirst())
        )
    }

    public static func typedTextToRestore(
        originalShortcut: String, resumedShortcut: String
    ) -> String {
        guard resumedShortcut.hasPrefix(originalShortcut) else { return resumedShortcut }
        return String(resumedShortcut.dropFirst(originalShortcut.count))
    }

    public static func shouldSearchRemote(_ query: String, hasContext: Bool = false) -> Bool {
        if query.isEmpty { return hasContext }
        guard query.count >= 2 else { return false }
        let normalized = query.lowercased()
        let isLatinWord = normalized.unicodeScalars.allSatisfy {
            $0.isASCII && CharacterSet.letters.contains($0)
        }
        // Very short romanized fragments such as "omed" are often unfinished.
        // Keep local prefix results visible, but wait for more input before
        // asking either remote model to invent an interpretation.
        if isLatinWord && normalized.count <= 4,
           let last = normalized.last,
           "bcdfghjklmpqrstvwxyz".contains(last) {
            return false
        }
        return true
    }
}
