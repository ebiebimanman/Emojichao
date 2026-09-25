import AppKit
import ApplicationServices
import EmojiCatalogCore
import Foundation

// Replacing by the number of keyDown events is unsafe with Japanese IMEs:
// several Roman keys may produce one visible kana. Select the actual text
// before the caret, and refuse to replace when it cannot be verified.
enum ShortcutReplacement {
    private static let rangeType = AXValueType(rawValue: kAXValueCFRangeType)!

    enum SelectionFailure: Error {
        case initialFocusUnavailable
        case currentFocusUnavailable
        case focusChanged
        case caretUnavailable
        case textUnavailable
        case shortcutNotFound
        case selectionUnavailable

        var message: String {
            switch self {
            case .initialFocusUnavailable: "「:」入力時の入力欄を特定できません"
            case .currentFocusUnavailable: "選択時の入力欄を特定できません"
            case .focusChanged: "入力先が変わりました"
            case .caretUnavailable: "カーソル位置を読み取れません"
            case .textUnavailable: "直前の文字を読み取れません"
            case .shortcutNotFound: "入力した「:〜」を確認できません"
            case .selectionUnavailable: "この入力欄では文字を安全に選択できません"
            }
        }
    }

    /// A character that can begin a search word. See
    /// `EmojiSearchPolicy.isSearchableCharacter`, shared with the iOS
    /// keyboard extension, for the actual rule.
    static func isSearchableCharacter(_ characters: String) -> Bool {
        EmojiSearchPolicy.isSearchableCharacter(characters)
    }

    static func focusedElement() -> AXUIElement? {
        if let focused = focusedElement(in: AXUIElementCreateSystemWide()) {
            return focused
        }
        // Some apps do not expose their focused editor through the system-wide
        // object, but do expose it on the frontmost application's AX object.
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier > 0,
              frontmost.processIdentifier != getpid() else { return nil }
        return focusedElement(in: AXUIElementCreateApplication(frontmost.processIdentifier))
    }

    // Read visible text around the current AX caret. Callers handling an IME
    // trigger should wait until that trigger has committed marked text.
    static func contextBeforeCaret(in element: AXUIElement?, maxCharacters: Int = 10) -> String? {
        guard let element, maxCharacters > 0,
              let caret = selectedRange(of: element), caret.length == 0,
              caret.location > 0 else { return nil }
        for attribute in [kAXRoleAttribute, kAXSubroleAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let label = value as? String {
                let normalized = label.lowercased()
                if normalized.contains("secure") || normalized.contains("password") { return nil }
            }
        }
        let lookbackLength = min(caret.location, 80)
        var lookback = CFRange(location: caret.location - lookbackLength, length: lookbackLength)
        guard let text = textBeforeCaret(in: element, range: &lookback) else { return nil }
        return trailingContext(in: text, maxCharacters: maxCharacters)
    }

    static func trailingContext(in text: String, maxCharacters: Int = 10) -> String? {
        guard maxCharacters > 0 else { return nil }
        let context = String(text.suffix(maxCharacters))
        return context.isEmpty ? nil : context
    }

    static func trailingContextBeforeTrigger(
        in text: String, trigger: String, maxCharacters: Int = 10
    ) -> String? {
        guard trigger == ":" || trigger == "：", text.hasSuffix(trigger) else { return nil }
        return trailingContext(in: String(text.dropLast()), maxCharacters: maxCharacters)
    }

    // Japanese IMEs may not expose the latest composition through AX until
    // the ':' event commits it. Read after the trigger reaches the editor,
    // then exclude that trigger from the context sent for ranking.
    static func contextBeforeTrigger(
        in element: AXUIElement?, trigger: String, maxCharacters: Int = 10
    ) -> String? {
        guard let visible = contextBeforeCaret(
            in: element, maxCharacters: maxCharacters + 1
        ) else { return nil }
        return trailingContextBeforeTrigger(
            in: visible, trigger: trigger, maxCharacters: maxCharacters
        )
    }

    // Terminals publish their screen as an AXTextArea and accept a selected
    // range, but that range selects displayed text, not an editable one: the
    // paste that follows lands at the shell cursor and leaves the typed ':'
    // behind. Whether AXSelectedText is settable separates a real editor from
    // that screen buffer, and unlike the range probe it answers reliably.
    static func replacesSelectedText(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &settable
        ) == .success else { return false }
        return settable.boolValue
    }

    /// The shortcut as the editor shows it. A Japanese IME turns the roman
    /// keys we intercepted into different visible characters, so a fallback
    /// that counts or compares must work on what is on screen, not on what
    /// was typed.
    static func visibleShortcut(
        rawShortcut: String, originalElement: AXUIElement?
    ) -> String? {
        guard let originalElement, let focused = focusedElement(),
              CFEqual(originalElement, focused) else { return nil }
        guard let caret = selectedRange(of: focused), caret.length == 0,
              caret.location > 0 else { return nil }
        let lookbackLength = min(caret.location, 80)
        var lookback = CFRange(location: caret.location - lookbackLength, length: lookbackLength)
        guard let text = textBeforeCaret(in: focused, range: &lookback),
              let shortcut = suffixRange(
                  in: text, start: lookback.location, rawShortcut: rawShortcut
              ) else { return nil }
        return (text as NSString).substring(with: NSRange(
            location: shortcut.location - lookback.location, length: shortcut.length
        ))
    }

    /// The text the editor currently shows before the caret, used to confirm
    /// that a fallback deletion removed exactly the shortcut.
    static func textBeforeCaret(in element: AXUIElement?, characters: Int) -> String? {
        guard let element, characters > 0,
              let caret = selectedRange(of: element), caret.length == 0,
              caret.location > 0 else { return nil }
        let length = min(caret.location, characters)
        var range = CFRange(location: caret.location - length, length: length)
        return textBeforeCaret(in: element, range: &range)
    }

    /// The editor's own report of what is selected. Chromium-based editors
    /// ignore writes to the selected range but report the selection
    /// correctly, so this verifies a keyboard selection without the clipboard.
    static func selectedText(of element: AXUIElement?) -> String? {
        guard let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &value
        ) == .success else { return nil }
        return value as? String
    }

    private static func focusedElement(in root: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func selectVisibleShortcut(
        rawShortcut: String, originalElement: AXUIElement?
    ) -> Result<Void, SelectionFailure> {
        guard let originalElement else { return .failure(.initialFocusUnavailable) }
        guard let focused = focusedElement() else { return .failure(.currentFocusUnavailable) }
        guard CFEqual(originalElement, focused) else { return .failure(.focusChanged) }
        guard replacesSelectedText(focused) else { return .failure(.selectionUnavailable) }
        guard let caret = selectedRange(of: focused), caret.length == 0,
              caret.location > 0 else { return .failure(.caretUnavailable) }

        let lookbackLength = min(caret.location, 80)
        var lookback = CFRange(location: caret.location - lookbackLength, length: lookbackLength)
        guard let text = textBeforeCaret(in: focused, range: &lookback) else {
            return .failure(.textUnavailable)
        }
        guard let replacement = suffixRange(
            in: text, start: lookback.location, rawShortcut: rawShortcut
        ) else { return .failure(.shortcutNotFound) }

        guard setSelectedRange(replacement, in: focused) else {
            return .failure(.selectionUnavailable)
        }

        guard let actual = selectedRange(of: focused),
              actual.location == replacement.location,
              actual.length == replacement.length else {
            restoreCaret(caret, in: focused)
            return .failure(.selectionUnavailable)
        }
        return .success(())
    }

    static func selectVisibleText(
        _ expected: String, originalElement: AXUIElement?
    ) -> Result<Void, SelectionFailure> {
        guard let originalElement else { return .failure(.initialFocusUnavailable) }
        guard let focused = focusedElement() else { return .failure(.currentFocusUnavailable) }
        guard CFEqual(originalElement, focused) else { return .failure(.focusChanged) }
        guard replacesSelectedText(focused) else { return .failure(.selectionUnavailable) }
        guard let caret = selectedRange(of: focused), caret.length == 0 else {
            return .failure(.caretUnavailable)
        }
        let length = (expected as NSString).length
        guard length > 0, caret.location >= length else { return .failure(.shortcutNotFound) }
        var range = CFRange(location: caret.location - length, length: length)
        guard textBeforeCaret(in: focused, range: &range) == expected else {
            return .failure(.shortcutNotFound)
        }
        guard setSelectedRange(range, in: focused) else {
            return .failure(.selectionUnavailable)
        }
        guard let actual = selectedRange(of: focused),
              actual.location == range.location, actual.length == range.length else {
            restoreCaret(caret, in: focused)
            return .failure(.selectionUnavailable)
        }
        return .success(())
    }

    private static func textBeforeCaret(in element: AXUIElement, range: inout CFRange) -> String? {
        if let rangeValue = AXValueCreate(rangeType, &range) {
            var textValue: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                rangeValue,
                &textValue
            ) == .success, let text = textValue as? String,
                (text as NSString).length == range.length {
                return text
            }
        }

        // Some editable fields expose their full text as AXValue but do not
        // implement AXStringForRange. Keep the same verified caret/range check.
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXValueAttribute as CFString, &value
        ) == .success, let fullText = value as? String else { return nil }
        let nsText = fullText as NSString
        guard nsText.length <= 100_000, NSMaxRange(NSRange(location: range.location, length: range.length)) <= nsText.length else {
            return nil
        }
        return nsText.substring(with: NSRange(location: range.location, length: range.length))
    }

    static func suffixRange(in text: String, start: Int, rawShortcut: String) -> CFRange? {
        let nsText = text as NSString
        let colon = nsText.range(of: ":", options: .backwards)
        let fullWidthColon = nsText.range(of: "：", options: .backwards)
        let marker = max(
            colon.location == NSNotFound ? -1 : colon.location,
            fullWidthColon.location == NSNotFound ? -1 : fullWidthColon.location
        )
        guard marker >= 0 else { return nil }
        let length = nsText.length - marker
        // A context-only ':' is a valid shortcut too: it is the state shown
        // after undoing the automatic first-candidate selection.
        guard length >= 1, length <= 50 else { return nil }
        let suffix = nsText.substring(from: marker)
        let visibleQuery = String(suffix.dropFirst())
        guard !visibleQuery.contains(where: \.isWhitespace) else { return nil }

        // Latin text must be identical to what was typed. With an IME, the
        // visible kana and the intercepted Roman keys can differ in length.
        if suffix != rawShortcut {
            let rawQuery = String(rawShortcut.dropFirst())
            let isRomanInput = rawQuery.unicodeScalars.allSatisfy(\.isASCII)
            let hasJapaneseText = visibleQuery.unicodeScalars.contains {
                (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
            }
            guard isRomanInput && hasJapaneseText else { return nil }
        }
        return CFRange(location: start + marker, length: length)
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &value
        ) == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value as! AXValue, rangeType, &range) else { return nil }
        return range
    }

    private static func setSelectedRange(_ range: CFRange, in element: AXUIElement) -> Bool {
        // Do not rely on AXUIElementIsAttributeSettable here. Several editors
        // (including web views) report false or an error for that probe while
        // accepting the subsequent write. The write plus read-back below is
        // the meaningful safety check.
        var requested = range
        guard let value = AXValueCreate(rangeType, &requested) else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, value
        ) == .success
    }

    private static func restoreCaret(_ caret: CFRange, in element: AXUIElement) {
        var caret = caret
        if let value = AXValueCreate(rangeType, &caret) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        }
    }
}
