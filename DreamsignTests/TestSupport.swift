import Foundation
@testable import Dreamsign

enum Fixtures {
    /// New York: DST ends Sun Nov 1 2026 (2 AM → 1 AM) and starts Sun Mar 8 2026 (2 AM → 3 AM).
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
}

/// Deterministic dictionary for validator rules.
struct WordListLexicon: Lexicon {
    var words: Set<String>
    func isKnownWord(_ word: String, language: String) -> Bool { words.contains(word) }
}

/// Whitespace tokenizer that marks the given words as names.
struct StubTokenizer: WordTokenizing {
    var names: Set<String> = []
    func tokenize(_ text: String) -> (tokens: [WordToken], language: String) {
        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation && $0 != "'" })
            .map { WordToken(text: String($0), isName: names.contains(String($0))) }
        return (tokens, "en")
    }
}
