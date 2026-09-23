import AppKit
import Carbon.HIToolbox

// Every fallback replacement needs committed text. While a Japanese IME is
// still composing, Shift-Left moves inside the conversion instead of
// selecting it, and Command-C copies nothing at all. The 英数 key commits
// what is on screen without sending Return, which in a chat app would post
// the message.
@MainActor
enum IMEComposition {
    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)      // kana
                || (0x4E00...0x9FFF).contains(scalar.value) // kanji
                || (0xFF00...0xFFEF).contains(scalar.value) // full-width forms
        }
    }

    // Committing can change what is on screen, so callers read the shortcut
    // again afterwards instead of reusing what they saw while composing.
    static func commit() async {
        _ = KeyboardReplacement.postKey(CGKeyCode(kVK_JIS_Eisu), flags: [])
        try? await Task.sleep(for: .milliseconds(120))
    }

    // 英数 also leaves the IME in alphanumeric mode. Put it back so the next
    // thing the user types is still Japanese.
    static func restoreKanaMode() {
        _ = KeyboardReplacement.postKey(CGKeyCode(kVK_JIS_Kana), flags: [])
    }
}
