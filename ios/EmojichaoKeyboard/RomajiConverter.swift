import Foundation

/// Converts romaji typed into a buffer into hiragana, incrementally, the
/// same way most Japanese IMEs' "ローマ字入力" mode works. No kanji
/// conversion — that needs a dictionary-backed conversion engine, well
/// beyond this keyboard's scope. Good enough to search the emoji catalog,
/// which already matches on hiragana/katakana keywords.
enum RomajiConverter {
    /// Splits `buffer` into hiragana ready to commit and romaji still
    /// waiting for more characters (e.g. a lone "k" waiting for a vowel).
    static func convert(_ buffer: String) -> (committed: String, remaining: String) {
        var committed = ""
        var remaining = Substring(buffer)
        let sokuonConsonants: Set<Character> = ["k", "s", "t", "p", "g", "z", "d", "b", "c", "f", "j"]

        while !remaining.isEmpty {
            if remaining.count >= 2,
               remaining[remaining.startIndex] == remaining[remaining.index(after: remaining.startIndex)],
               sokuonConsonants.contains(remaining[remaining.startIndex]) {
                committed += "っ"
                remaining.removeFirst()
                continue
            }
            if remaining.count >= 3, let kana = table[String(remaining.prefix(3))] {
                committed += kana
                remaining.removeFirst(3)
                continue
            }
            if remaining.count >= 2, let kana = table[String(remaining.prefix(2))] {
                committed += kana
                remaining.removeFirst(2)
                continue
            }
            if let kana = table[String(remaining.prefix(1))] {
                committed += kana
                remaining.removeFirst(1)
                continue
            }
            if remaining.first == "n", remaining.count >= 2,
               !"aiueoyn".contains(remaining[remaining.index(after: remaining.startIndex)]) {
                committed += "ん"
                remaining.removeFirst()
                continue
            }
            // No match yet (e.g. a lone consonant, or "n" at the very end):
            // wait for more input before deciding.
            break
        }
        return (committed, String(remaining))
    }

    private static let table: [String: String] = [
        "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
        "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ",
        "sa": "さ", "shi": "し", "si": "し", "su": "す", "se": "せ", "so": "そ",
        "sha": "しゃ", "shu": "しゅ", "sho": "しょ",
        "sya": "しゃ", "syu": "しゅ", "syo": "しょ",
        "ta": "た", "chi": "ち", "ti": "ち", "tsu": "つ", "tu": "つ", "te": "て", "to": "と",
        "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ",
        "tya": "ちゃ", "tyu": "ちゅ", "tyo": "ちょ",
        "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
        "nya": "にゃ", "nyu": "にゅ", "nyo": "にょ",
        "ha": "は", "hi": "ひ", "fu": "ふ", "hu": "ふ", "he": "へ", "ho": "ほ",
        "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ",
        "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
        "mya": "みゃ", "myu": "みゅ", "myo": "みょ",
        "ya": "や", "yu": "ゆ", "yo": "よ",
        "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
        "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ",
        "wa": "わ", "wo": "を", "wi": "うぃ", "we": "うぇ",
        "nn": "ん", "n'": "ん",
        "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
        "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ",
        "za": "ざ", "ji": "じ", "zi": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
        "ja": "じゃ", "ju": "じゅ", "jo": "じょ",
        "zya": "じゃ", "zyu": "じゅ", "zyo": "じょ",
        "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
        "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
        "bya": "びゃ", "byu": "びゅ", "byo": "びょ",
        "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
        "pya": "ぴゃ", "pyu": "ぴゅ", "pyo": "ぴょ",
        "-": "ー"
    ]
}
