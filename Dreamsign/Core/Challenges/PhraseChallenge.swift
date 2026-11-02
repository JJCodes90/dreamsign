import Foundation

enum PhraseLength: String, Codable, CaseIterable, Identifiable, Sendable {
    case short, medium, long

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: String(localized: "Short phrase")
        case .medium: String(localized: "Sentence")
        case .long: String(localized: "Long sentence")
        }
    }

    /// Original lines that double as dream-recall and lucidity intentions.
    var phrases: [String] {
        switch self {
        case .short:
            [String(localized: "I will remember my dreams"),
             String(localized: "Morning light, clear mind"),
             String(localized: "Feet on the floor, eyes open"),
             String(localized: "Today I notice the strange"),
             String(localized: "My dreams are worth writing down")]
        case .medium:
            [String(localized: "When something feels strange, I will ask if I am dreaming"),
             String(localized: "I am awake now, and tonight I will notice my dreams"),
             String(localized: "Every morning I remember a little more of the night"),
             String(localized: "I check my hands and the clock whenever things feel odd")]
        case .long:
            [String(localized: "Next time I see something impossible, I will stop, look at my hands, and realize that I am dreaming"),
             String(localized: "I am fully awake, my feet are on the floor, and I remember where my dreams took me last night"),
             String(localized: "Dreams fade quickly, so I write them down first and let the rest of the morning wait")]
        }
    }
}

/// Compares what was typed with the target phrase, forgiving case, punctuation and spacing.
struct PhraseMatcher: Sendable {
    let target: String
    private let normalizedTarget: [Character]

    init(_ target: String) {
        self.target = target
        normalizedTarget = Array(Self.normalize(target))
    }

    /// Lowercased letters, digits and single spaces; curly apostrophes and punctuation dropped.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var result = ""
        var pendingSpace = false
        for character in folded {
            if character.isLetter || character.isNumber {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.append(character)
            } else if character.isWhitespace {
                pendingSpace = true
            }
        }
        return result
    }

    /// How many leading characters of the normalized target have been typed correctly.
    func matchedCount(_ typed: String) -> Int {
        let normalized = Array(Self.normalize(typed))
        var count = 0
        while count < normalized.count, count < normalizedTarget.count, normalized[count] == normalizedTarget[count] {
            count += 1
        }
        return count
    }

    func progress(_ typed: String) -> Double {
        normalizedTarget.isEmpty ? 1 : Double(matchedCount(typed)) / Double(normalizedTarget.count)
    }

    func isMatch(_ typed: String) -> Bool {
        Self.normalize(typed) == String(normalizedTarget)
    }

    /// True when the typed text has gone off the rails (a wrong character after the matched part).
    func hasMistake(_ typed: String) -> Bool {
        matchedCount(typed) < Self.normalize(typed).count
    }

    /// The prefix of the original target that has been matched, for highlighting.
    func matchedPrefix(_ typed: String) -> String {
        var remaining = matchedCount(typed)
        guard remaining > 0 else { return "" }
        var end = target.startIndex
        var sawText = false
        var pendingSpace = false
        for index in target.indices {
            let folded = String(target[index]).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard let character = folded.first else { continue }
            if character.isLetter || character.isNumber {
                if pendingSpace, sawText { remaining -= 1 }
                pendingSpace = false
                guard remaining > 0 else { break }
                remaining -= 1
                sawText = true
                end = target.index(after: index)
                if remaining == 0 { break }
            } else if character.isWhitespace {
                pendingSpace = true
            }
        }
        return String(target[..<end])
    }
}
