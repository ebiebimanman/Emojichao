import AppKit
import CoreGraphics

/// Experimental clipboard-free text insertion. The target application sees a
/// keyboard event whose Unicode payload is the selected emoji.
@MainActor
enum UnicodeTextInjection {
    enum Failure: Error, Equatable {
        case emptyText
        case eventPostingDenied
        case invalidTarget
        case eventUnavailable

        var message: String {
            switch self {
            case .emptyText: "入力する文字がありません"
            case .eventPostingDenied: "キー送信の許可がありません"
            case .invalidTarget: "入力先のアプリを特定できません"
            case .eventUnavailable: "Unicodeキーイベントを作成できません"
            }
        }
    }

    static func insert(
        _ text: String,
        into application: NSRunningApplication
    ) -> Result<Void, Failure> {
        guard !text.isEmpty else { return .failure(.emptyText) }
        guard application.processIdentifier > 0,
              application.processIdentifier != getpid(),
              !application.isTerminated else {
            return .failure(.invalidTarget)
        }
        guard CGPreflightPostEventAccess() else {
            return .failure(.eventPostingDenied)
        }
        guard let events = makeEvents(text: text) else {
            return .failure(.eventUnavailable)
        }

        // Address the process directly. This avoids a race where another app
        // becomes frontmost between closing the status menu and posting.
        events.keyDown.postToPid(application.processIdentifier)
        events.keyUp.postToPid(application.processIdentifier)
        return .success(())
    }

    static func requestEventPostingAccess() -> Bool {
        CGPreflightPostEventAccess() || CGRequestPostEventAccess()
    }

    static func makeEvents(text: String) -> (keyDown: CGEvent, keyUp: CGEvent)? {
        guard !text.isEmpty else { return nil }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(
            keyboardEventSource: source, virtualKey: 0, keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source, virtualKey: 0, keyDown: false
        ) else { return nil }

        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        keyDown.setIntegerValueField(
            .eventSourceUserData,
            value: KeyboardReplacement.syntheticEventMarker
        )
        keyUp.setIntegerValueField(
            .eventSourceUserData,
            value: KeyboardReplacement.syntheticEventMarker
        )
        return (keyDown, keyUp)
    }

    static func unicodeString(from event: CGEvent) -> String {
        var length = 0
        event.keyboardGetUnicodeString(
            maxStringLength: 0,
            actualStringLength: &length,
            unicodeString: nil
        )
        guard length > 0 else { return "" }
        var buffer = [UniChar](repeating: 0, count: length)
        buffer.withUnsafeMutableBufferPointer { pointer in
            event.keyboardGetUnicodeString(
                maxStringLength: pointer.count,
                actualStringLength: &length,
                unicodeString: pointer.baseAddress
            )
        }
        return String(utf16CodeUnits: buffer, count: length)
    }
}
