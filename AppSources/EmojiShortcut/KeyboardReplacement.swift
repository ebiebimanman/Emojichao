import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Fallback for editors that refuse an Accessibility selection, or do not
// expose their focused text field at all. Never act on key counts alone:
// select or delete what the editor shows, and replace it only after reading
// back that the editor agrees it is exactly the shortcut.
@MainActor
enum KeyboardReplacement {
    static let syntheticEventMarker: Int64 = 0x454D4F4A4953

    enum VisibleTextStrategy: Equatable {
        case verifiedKeyboardSelection
        case verifiedDeletion
    }

    enum Failure: Error {
        case unsupportedShortcut
        case targetChanged
        case clipboardUnavailable
        case eventUnavailable
        case copyFailed
        case selectionMismatch
        case deletionFailed
        case composingText

        var message: String {
            switch self {
            case .unsupportedShortcut: "英数字のショートコードだけ試せます"
            case .targetChanged: "入力先が変わったため中止しました"
            case .clipboardUnavailable: "クリップボードを安全に保持できないため中止しました"
            case .eventUnavailable: "キー操作を送れないため中止しました"
            case .copyFailed: "選択した文字を確認できませんでした"
            case .selectionMismatch: "選択した文字が入力内容と一致しません"
            case .deletionFailed: "入力した「:〜」を消せませんでした"
            case .composingText: "変換中の文字はこのアプリでは置き換えられません"
            }
        }
    }

    static func canReplace(_ shortcut: String) -> Bool {
        guard shortcut.count >= 1, shortcut.count <= 50,
              shortcut.first == ":" else { return false }
        return shortcut.dropFirst().unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 43, 45, 95: true
            default: false
            }
        }
    }

    static func visibleTextStrategy(
        hasInspectableElement: Bool, replacesSelectedText: Bool
    ) -> VisibleTextStrategy {
        hasInspectableElement && !replacesSelectedText
            ? .verifiedDeletion
            : .verifiedKeyboardSelection
    }

    static func replaceVisibleText(
        _ expected: String,
        with replacement: String,
        in targetApp: NSRunningApplication,
        element: AXUIElement?,
        strategy requestedStrategy: VisibleTextStrategy? = nil,
        stillValid: () -> Bool,
        onPastePosted: () -> Void = {}
    ) async -> Result<Void, Failure> {
        let replacesSelectedText = element.map {
            ShortcutReplacement.replacesSelectedText($0)
        } ?? false
        let strategy = requestedStrategy ?? visibleTextStrategy(
            hasInspectableElement: element != nil,
            replacesSelectedText: replacesSelectedText
        )
        switch strategy {
        case .verifiedKeyboardSelection:
            return await replaceExact(
                expected, with: replacement, in: targetApp,
                element: element, stillValid: stillValid,
                onPastePosted: onPastePosted
            )
        case .verifiedDeletion:
            guard let element else { return .failure(.targetChanged) }
            return await deleteVisible(
                expected, with: replacement, in: targetApp,
                element: element, stillValid: stillValid,
                onPastePosted: onPastePosted
            )
        }
    }

    /// Replaces the emoji that this app has just inserted. This is only used
    /// while AutoAppliedSelection remains valid: mouse clicks, cursor keys,
    /// modifiers, and unrelated input clear that state. The caret is therefore
    /// immediately after our insertion, so one Backspace removes the complete
    /// emoji grapheme in native, Chromium, and terminal editors alike.
    static func replaceMostRecentInsertion(
        _ expected: String,
        with replacement: String,
        in targetApp: NSRunningApplication,
        stillValid: () -> Bool,
        onPastePosted: () -> Void = {}
    ) async -> Result<Void, Failure> {
        guard !expected.isEmpty, !replacement.isEmpty else {
            return .failure(.unsupportedShortcut)
        }
        guard isTargetFrontmost(targetApp), stillValid() else {
            return .failure(.targetChanged)
        }
        guard CGPreflightPostEventAccess() else { return .failure(.eventUnavailable) }
        let pasteboard = NSPasteboard.general
        guard let snapshot = PasteboardSnapshot.capture(from: pasteboard) else {
            return .failure(.clipboardUnavailable)
        }
        var clipboardChangeToRestore: Int?
        defer {
            if let clipboardChangeToRestore {
                restoreIfUnchanged(
                    snapshot, pasteboard: pasteboard,
                    expectedChange: clipboardChangeToRestore
                )
            }
        }
        guard postKey(CGKeyCode(kVK_Delete), flags: []) else {
            return .failure(.eventUnavailable)
        }
        try? await Task.sleep(for: .milliseconds(60))
        guard isTargetFrontmost(targetApp), stillValid() else {
            return .failure(.targetChanged)
        }
        return await paste(
            replacement, over: snapshot, pasteboard: pasteboard,
            clipboardChangeToRestore: &clipboardChangeToRestore,
            selectionStarted: false, targetApp: targetApp,
            stillValid: stillValid, onPastePosted: onPastePosted
        )
    }

    // Generic context fallback for editors that do not expose AX text ranges.
    // It temporarily selects the visible text before the caret, copies it,
    // collapses the selection, and restores the user's clipboard unchanged.
    static func contextBeforeCaret(
        in targetApp: NSRunningApplication,
        maxCharacters: Int = 10
    ) async -> String? {
        guard maxCharacters > 0,
              isTargetFrontmost(targetApp),
              CGPreflightPostEventAccess() else { return nil }
        let pasteboard = NSPasteboard.general
        guard let snapshot = PasteboardSnapshot.capture(from: pasteboard) else { return nil }
        let beforeCopy = pasteboard.changeCount
        var selectionStarted = false
        defer {
            if selectionStarted, isTargetFrontmost(targetApp) {
                _ = postKey(CGKeyCode(kVK_RightArrow), flags: [])
            }
            if pasteboard.changeCount != beforeCopy {
                _ = snapshot.restore(to: pasteboard)
            }
        }

        for _ in 0..<maxCharacters {
            guard isTargetFrontmost(targetApp),
                  postKey(CGKeyCode(kVK_LeftArrow), flags: .maskShift) else { return nil }
            selectionStarted = true
        }
        try? await Task.sleep(for: .milliseconds(80))
        guard isTargetFrontmost(targetApp), pasteboard.changeCount == beforeCopy,
              postKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand) else { return nil }

        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(20))
            guard isTargetFrontmost(targetApp) else { return nil }
            if pasteboard.changeCount != beforeCopy {
                return pasteboard.string(forType: .string).map {
                    String($0.suffix(maxCharacters))
                }
            }
        }
        return nil
    }

    static func replace(
        shortcut: String,
        with emoji: String,
        in targetApp: NSRunningApplication,
        stillValid: () -> Bool,
        onPastePosted: () -> Void = {}
    ) async -> Result<Void, Failure> {
        guard canReplace(shortcut) else { return .failure(.unsupportedShortcut) }
        return await replaceExact(
            shortcut, with: emoji, in: targetApp,
            stillValid: stillValid, onPastePosted: onPastePosted
        )
    }

    static func replaceExact(
        _ expected: String,
        with emoji: String,
        in targetApp: NSRunningApplication,
        element: AXUIElement? = nil,
        stillValid: () -> Bool,
        onPastePosted: () -> Void = {}
    ) async -> Result<Void, Failure> {
        guard !expected.isEmpty, expected.count <= 50 else {
            return .failure(.unsupportedShortcut)
        }
        guard isTargetFrontmost(targetApp), stillValid() else { return .failure(.targetChanged) }
        guard CGPreflightPostEventAccess() else { return .failure(.eventUnavailable) }
        let pasteboard = NSPasteboard.general
        guard let snapshot = PasteboardSnapshot.capture(from: pasteboard) else {
            return .failure(.clipboardUnavailable)
        }
        let beforeCopy = pasteboard.changeCount
        var clipboardChangeToRestore: Int?
        defer {
            if let clipboardChangeToRestore {
                restoreIfUnchanged(snapshot, pasteboard: pasteboard,
                                   expectedChange: clipboardChangeToRestore)
            }
        }

        for _ in expected {
            guard postKey(CGKeyCode(kVK_LeftArrow), flags: .maskShift) else {
                return finishFailure(.eventUnavailable, selectionStarted: true,
                                     targetApp: targetApp, stillValid: stillValid)
            }
        }
        try? await Task.sleep(for: .milliseconds(80))
        guard isTargetFrontmost(targetApp), stillValid() else {
            return .failure(.targetChanged)
        }

        // Editors that describe their selection through Accessibility are
        // verified without touching the clipboard. Chromium-based ones
        // (Chrome pages, Slack, ChatGPT) belong here: they ignore a request
        // to move the selection, but report it correctly once the keys have.
        if let selected = ShortcutReplacement.selectedText(of: element) {
            guard selected == expected else {
                return finishFailure(.selectionMismatch, selectionStarted: true,
                                     targetApp: targetApp, stillValid: stillValid)
            }
        } else {
            guard pasteboard.changeCount == beforeCopy else {
                return finishFailure(.clipboardUnavailable, selectionStarted: true,
                                     targetApp: targetApp, stillValid: stillValid)
            }
            guard postKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand) else {
                return finishFailure(.eventUnavailable, selectionStarted: true,
                                     targetApp: targetApp, stillValid: stillValid)
            }

            var copied = false
            for _ in 0..<25 {
                try? await Task.sleep(for: .milliseconds(20))
                guard isTargetFrontmost(targetApp), stillValid() else {
                    return .failure(.targetChanged)
                }
                if pasteboard.changeCount != beforeCopy {
                    copied = true
                    clipboardChangeToRestore = pasteboard.changeCount
                    break
                }
            }
            guard copied else {
                return finishFailure(.copyFailed, selectionStarted: true,
                                     targetApp: targetApp, stillValid: stillValid)
            }
            let copyChange = pasteboard.changeCount
            guard pasteboard.string(forType: .string) == expected else {
                return finishFailure(.selectionMismatch, selectionStarted: true,
                                     targetApp: targetApp, stillValid: stillValid)
            }
            guard pasteboard.changeCount == copyChange else {
                return finishFailure(.clipboardUnavailable, selectionStarted: true,
                                     targetApp: targetApp, stillValid: stillValid)
            }
        }

        guard isTargetFrontmost(targetApp), stillValid() else {
            return .failure(.targetChanged)
        }
        return await paste(
            emoji, over: snapshot, pasteboard: pasteboard,
            clipboardChangeToRestore: &clipboardChangeToRestore,
            selectionStarted: true, targetApp: targetApp,
            stillValid: stillValid, onPastePosted: onPastePosted
        )
    }

    // Replacement for editors with no editable selection at all. Terminals
    // are the case: their line editor removes one character per Backspace,
    // so the shortcut can be deleted instead of selected. The count comes
    // from the text Accessibility shows on screen, never from how many keys
    // were pressed, and the screen is read back before anything is pasted.
    static func deleteVisible(
        _ expected: String,
        with emoji: String,
        in targetApp: NSRunningApplication,
        element: AXUIElement,
        stillValid: () -> Bool,
        onPastePosted: () -> Void = {}
    ) async -> Result<Void, Failure> {
        guard !expected.isEmpty, expected.count <= 50 else {
            return .failure(.unsupportedShortcut)
        }
        guard isTargetFrontmost(targetApp), stillValid() else { return .failure(.targetChanged) }
        guard CGPreflightPostEventAccess() else { return .failure(.eventUnavailable) }
        guard let before = ShortcutReplacement.textBeforeCaret(in: element, characters: 80),
              before.hasSuffix(expected) else { return .failure(.selectionMismatch) }
        let remainder = String(before.dropLast(expected.count))
        let pasteboard = NSPasteboard.general
        guard let snapshot = PasteboardSnapshot.capture(from: pasteboard) else {
            return .failure(.clipboardUnavailable)
        }
        var clipboardChangeToRestore: Int?
        defer {
            if let clipboardChangeToRestore {
                restoreIfUnchanged(snapshot, pasteboard: pasteboard,
                                   expectedChange: clipboardChangeToRestore)
            }
        }

        for _ in expected {
            guard isTargetFrontmost(targetApp), stillValid() else {
                return .failure(.targetChanged)
            }
            guard postKey(CGKeyCode(kVK_Delete), flags: []) else {
                return .failure(.eventUnavailable)
            }
            try? await Task.sleep(for: .milliseconds(15))
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard isTargetFrontmost(targetApp), stillValid() else {
            return .failure(.targetChanged)
        }
        // Confirm the editor lost exactly the shortcut and nothing else.
        guard let after = ShortcutReplacement.textBeforeCaret(in: element, characters: 80),
              !after.hasSuffix(expected), after.hasSuffix(remainder) else {
            return .failure(.deletionFailed)
        }
        return await paste(
            emoji, over: snapshot, pasteboard: pasteboard,
            clipboardChangeToRestore: &clipboardChangeToRestore,
            selectionStarted: false, targetApp: targetApp,
            stillValid: stillValid, onPastePosted: onPastePosted
        )
    }

    private static func paste(
        _ emoji: String,
        over snapshot: PasteboardSnapshot,
        pasteboard: NSPasteboard,
        clipboardChangeToRestore: inout Int?,
        selectionStarted: Bool,
        targetApp: NSRunningApplication,
        stillValid: () -> Bool,
        onPastePosted: () -> Void
    ) async -> Result<Void, Failure> {
        pasteboard.clearContents()
        clipboardChangeToRestore = pasteboard.changeCount
        guard pasteboard.setString(emoji, forType: .string) else {
            return finishFailure(.clipboardUnavailable, selectionStarted: selectionStarted,
                                 targetApp: targetApp, stillValid: stillValid)
        }
        clipboardChangeToRestore = pasteboard.changeCount
        guard postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand) else {
            return finishFailure(.eventUnavailable, selectionStarted: selectionStarted,
                                 targetApp: targetApp, stillValid: stillValid)
        }
        // The replacement has been posted. The caller can resume normal
        // typing while the clipboard snapshot remains alive for restoration.
        onPastePosted()
        // The target app receives Command-V asynchronously. Restore only if
        // our emoji is still the clipboard's current content.
        try? await Task.sleep(for: .milliseconds(500))
        return .success(())
    }

    private static func finishFailure(
        _ reason: Failure,
        selectionStarted: Bool,
        targetApp: NSRunningApplication,
        stillValid: () -> Bool
    ) -> Result<Void, Failure> {
        if selectionStarted, isTargetFrontmost(targetApp), stillValid() {
            _ = postKey(CGKeyCode(kVK_RightArrow), flags: [])
        }
        return .failure(reason)
    }

    private static func isTargetFrontmost(_ targetApp: NSRunningApplication) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        return frontmost.isEqual(targetApp)
    }

    private static func restoreIfUnchanged(
        _ snapshot: PasteboardSnapshot, pasteboard: NSPasteboard, expectedChange: Int
    ) {
        if pasteboard.changeCount == expectedChange {
            _ = snapshot.restore(to: pasteboard)
        }
    }

    static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        let sourceItems = pasteboard.pasteboardItems ?? []
        guard sourceItems.count <= 8 else { return nil }
        var totalBytes = 0
        var saved: [[(NSPasteboard.PasteboardType, Data)]] = []
        for item in sourceItems {
            guard !item.types.isEmpty else { return nil }
            var savedTypes: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                totalBytes += data.count
                guard totalBytes <= 4_000_000 else { return nil }
                savedTypes.append((type, data))
            }
            saved.append(savedTypes)
        }
        // Ensure every original type can be reconstructed before Command-C
        // changes the general pasteboard.
        let snapshot = PasteboardSnapshot(items: saved)
        guard snapshot.makeItems() != nil else { return nil }
        return snapshot
    }

    func restore(to pasteboard: NSPasteboard) -> Bool {
        guard let restoredItems = makeItems() else { return false }
        pasteboard.clearContents()
        return restoredItems.isEmpty || pasteboard.writeObjects(restoredItems)
    }

    private func makeItems() -> [NSPasteboardItem]? {
        var restored: [NSPasteboardItem] = []
        for savedTypes in items {
            let item = NSPasteboardItem()
            for (type, data) in savedTypes {
                guard item.setData(data, forType: type) else { return nil }
            }
            restored.append(item)
        }
        return restored
    }
}
