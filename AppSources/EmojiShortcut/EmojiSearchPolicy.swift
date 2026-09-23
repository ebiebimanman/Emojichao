import Foundation

enum EmojiSearchPolicy {
    struct TextSearchResume: Equatable {
        let shortcut: String
        let query: String
    }

    enum SelectionAction: Equatable {
        case select
        case waitForSearch
        case passThrough
    }

    static func selectionAction(candidateCount: Int, searchPending: Bool) -> SelectionAction {
        if candidateCount > 0 { return .select }
        return searchPending ? .waitForSearch : .passThrough
    }

    static func usesContextSearch(requested: Bool, query: String, hasContext: Bool) -> Bool {
        requested && query.isEmpty && hasContext
    }

    static func shouldAutoApplyFirstCandidate(isContextMode: Bool, candidateCount: Int) -> Bool {
        isContextMode && candidateCount > 0
    }

    static func shouldShowPanel(query: String, isContextMode: Bool) -> Bool {
        !query.isEmpty && !isContextMode
    }

    static func textSearchResume(shortcut: String, characters: String) -> TextSearchResume? {
        guard ShortcutReplacement.isSearchableCharacter(characters) else { return nil }
        let resumedShortcut = shortcut + characters
        return TextSearchResume(
            shortcut: resumedShortcut,
            query: String(resumedShortcut.dropFirst())
        )
    }

    static func typedTextToRestore(
        originalShortcut: String, resumedShortcut: String
    ) -> String {
        guard resumedShortcut.hasPrefix(originalShortcut) else { return resumedShortcut }
        return String(resumedShortcut.dropFirst(originalShortcut.count))
    }

    static func shouldSearchRemote(_ query: String, hasContext: Bool = false) -> Bool {
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
