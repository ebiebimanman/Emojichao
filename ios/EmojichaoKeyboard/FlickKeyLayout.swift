import Foundation

/// Which way a finger moved on a flick key before lifting.
enum FlickDirection {
    case center, left, up, right, down
}

/// One key of the iPhone-style 12-key (テンキー) layout: tapping cycles
/// through `cycle` (トグル入力), flicking picks a character directly.
struct FlickKey {
    let label: String
    /// Small hint text under the main label (number-mode keys, e.g. "☆♪→").
    var subLabel: String? = nil
    let center: String
    var left: String? = nil
    var up: String? = nil
    var right: String? = nil
    var down: String? = nil
    let cycle: [String]

    func character(for direction: FlickDirection) -> String? {
        switch direction {
        case .center: return center
        case .left: return left
        case .up: return up
        case .right: return right
        case .down: return down
        }
    }

    /// A key whose five flick positions are the first five characters of
    /// `chars` (center, left, up, right, down), like あいうえお.
    static func row(_ label: String, _ chars: String, cycle: String? = nil, subLabel: String? = nil) -> FlickKey {
        let c = chars.map(String.init)
        func at(_ i: Int) -> String? { i < c.count ? c[i] : nil }
        return FlickKey(
            label: label, subLabel: subLabel, center: c[0],
            left: at(1), up: at(2), right: at(3), down: at(4),
            cycle: (cycle ?? chars).map(String.init)
        )
    }
}

/// A slot in the 3×4 middle grid.
enum CenterKey {
    case flick(FlickKey)
    /// 小゛゜ in kana mode, a/A in alphabet mode: transforms the last character.
    case modifier(label: String)
}

enum KeyboardMode {
    case kana, alphabet, number

    var title: String {
        switch self {
        case .kana: return "あいう"
        case .alphabet: return "ABC"
        case .number: return "☆123"
        }
    }

    /// Rows top to bottom, three keys each — same arrangement as the iPhone
    /// 日本語かな keyboard.
    var grid: [[CenterKey]] {
        switch self {
        case .kana:
            return [
                [.flick(.row("あ", "あいうえお", cycle: "あいうえおぁぃぅぇぉ")),
                 .flick(.row("か", "かきくけこ")),
                 .flick(.row("さ", "さしすせそ"))],
                [.flick(.row("た", "たちつてと", cycle: "たちつてとっ")),
                 .flick(.row("な", "なにぬねの")),
                 .flick(.row("は", "はひふへほ"))],
                [.flick(.row("ま", "まみむめも")),
                 .flick(FlickKey(label: "や", center: "や", left: "「", up: "ゆ", right: "」", down: "よ",
                                 cycle: ["や", "ゆ", "よ", "ゃ", "ゅ", "ょ"])),
                 .flick(.row("ら", "らりるれろ"))],
                [.modifier(label: "小゛゜"),
                 .flick(FlickKey(label: "わ", center: "わ", left: "を", up: "ん", right: "ー",
                                 cycle: ["わ", "を", "ん", "ゎ", "ー"])),
                 .flick(FlickKey(label: "、。?!", center: "、", left: "。", up: "？", right: "！", down: "…",
                                 cycle: ["、", "。", "？", "！", "…"]))],
            ]
        case .alphabet:
            return [
                [.flick(.row("@#/&_", "@#/&_")), .flick(.row("ABC", "abc", cycle: "abcABC")), .flick(.row("DEF", "def", cycle: "defDEF"))],
                [.flick(.row("GHI", "ghi", cycle: "ghiGHI")), .flick(.row("JKL", "jkl", cycle: "jklJKL")), .flick(.row("MNO", "mno", cycle: "mnoMNO"))],
                [.flick(.row("PQRS", "pqrs", cycle: "pqrsPQRS")), .flick(.row("TUV", "tuv", cycle: "tuvTUV")), .flick(.row("WXYZ", "wxyz", cycle: "wxyzWXYZ"))],
                [.modifier(label: "a/A"), .flick(.row("'\"()", "'\"()")), .flick(.row(".,?!", ".,?!"))],
            ]
        case .number:
            return [
                [.flick(.row("1", "1☆♪→", subLabel: "☆♪→")),
                 .flick(.row("2", "2¥$€", subLabel: "¥$€")),
                 .flick(.row("3", "3%°#", subLabel: "%°#"))],
                [.flick(.row("4", "4○*・", subLabel: "○*・")),
                 .flick(.row("5", "5+×÷", subLabel: "+×÷")),
                 .flick(.row("6", "6<=>", subLabel: "<=>"))],
                [.flick(.row("7", "7「」:", subLabel: "「」:")),
                 .flick(.row("8", "8〒々〆", subLabel: "〒々〆")),
                 .flick(.row("9", "9^|\\", subLabel: "^|\\"))],
                [.flick(.row("()[]", "()[]")),
                 .flick(.row("0", "0〜…", subLabel: "〜…")),
                 .flick(.row(".,-/", ".,-/"))],
            ]
        }
    }
}

enum CharacterModifier {
    /// 小゛゜ cycles: each tap moves the last character one step along its
    /// group, e.g. は → ば → ぱ → は.
    private static let kanaCycles: [[Character]] = [
        "あぁ", "いぃ", "うぅゔ", "えぇ", "おぉ",
        "かが", "きぎ", "くぐ", "けげ", "こご",
        "さざ", "しじ", "すず", "せぜ", "そぞ",
        "ただ", "ちぢ", "つっづ", "てで", "とど",
        "はばぱ", "ひびぴ", "ふぶぷ", "へべぺ", "ほぼぽ",
        "やゃ", "ゆゅ", "よょ", "わゎ",
    ].map { Array($0) }

    static func next(after character: Character, in mode: KeyboardMode) -> Character? {
        switch mode {
        case .kana:
            guard let group = kanaCycles.first(where: { $0.contains(character) }),
                  let index = group.firstIndex(of: character) else { return nil }
            return group[(index + 1) % group.count]
        case .alphabet:
            guard character.isLetter, character.isASCII else { return nil }
            return character.isUppercase ? Character(character.lowercased()) : Character(character.uppercased())
        case .number:
            return nil
        }
    }
}
