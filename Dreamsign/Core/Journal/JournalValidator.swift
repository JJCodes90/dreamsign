import Foundation

/// A word as typed, plus whether NaturalLanguage tagged it as a name (people and places
/// from dreams are rarely dictionary words).
struct WordToken: Hashable, Sendable {
    var text: String
    var isName = false
}

@MainActor
protocol WordTokenizing {
    /// Word tokens and the BCP-47 code of the dominant language.
    func tokenize(_ text: String) -> (tokens: [WordToken], language: String)
}

@MainActor
protocol Lexicon {
    func isKnownWord(_ word: String, language: String) -> Bool
}

struct JournalRequirement: Hashable, Sendable {
    var minimumWords: Int

    /// Distinct non-stopwords needed on top of the word count.
    var minimumContentWords: Int { max(3, minimumWords / 4) }

    static let dream = JournalRequirement(minimumWords: 15)
    static let noRecall = JournalRequirement(minimumWords: 8)
    static let quick = JournalRequirement(minimumWords: 10)
}

enum JournalIssue: String, Hashable, Sendable, CaseIterable {
    case keyboardMashing
    case repeatedCharacters
    case unrecognizedWords
    case lowVariety
    case needsDetail

    var message: String {
        switch self {
        case .keyboardMashing: String(localized: "That looks like keyboard mashing.")
        case .repeatedCharacters: String(localized: "Real words only — no stretched-out letters.")
        case .unrecognizedWords: String(localized: "A lot of this isn't recognized. Check spelling?")
        case .lowVariety: String(localized: "Try more varied words.")
        case .needsDetail: String(localized: "Add a detail — a person, a place, a feeling.")
        }
    }
}

struct JournalAssessment: Hashable, Sendable {
    /// Distinct real words (dictionary words + names), case-insensitive.
    var realWordCount = 0
    var requiredWords: Int
    var contentWordCount = 0
    var analyzedTokenCount = 0
    var issues: [JournalIssue] = []

    var progress: Double { min(1, Double(realWordCount) / Double(max(requiredWords, 1))) }
    var meetsCount: Bool { realWordCount >= requiredWords }
    var isAcceptable: Bool { meetsCount && issues.isEmpty }
    var primaryIssue: JournalIssue? { issues.first }
}

/// Decides whether a journal entry is a real attempt. Rules are deliberately forgiving of
/// sleepy typos and strict about mashing, padding and repetition.
@MainActor
struct JournalValidator {
    enum TokenClass: Equatable {
        case ignored, known, name, unknown, mashed, repeated
    }

    var tokenizer: any WordTokenizing
    var lexicon: any Lexicon

    func assess(_ text: String, requirement: JournalRequirement) -> JournalAssessment {
        var result = JournalAssessment(requiredWords: requirement.minimumWords)
        let (tokens, language) = tokenizer.tokenize(text)

        var real = Set<String>(), content = Set<String>(), seen: [String] = []
        var repeated = 0, mashed = 0, unknown = 0

        for token in tokens {
            let word = Self.normalize(token.text)
            switch classify(token, normalized: word, language: language) {
            case .ignored:
                continue
            case .known, .name:
                real.insert(word)
                if !Stopwords.isStopword(word, language: language) { content.insert(word) }
            case .unknown: unknown += 1
            case .mashed: mashed += 1
            case .repeated: repeated += 1
            }
            seen.append(word)
        }

        let total = seen.count
        result.realWordCount = real.count
        result.contentWordCount = content.count
        result.analyzedTokenCount = total

        var issues: [JournalIssue] = []
        if mashed >= max(2, Int((Double(total) * 0.1).rounded(.up))) { issues.append(.keyboardMashing) }
        if repeated >= 2 { issues.append(.repeatedCharacters) }
        if total >= 5, Double(unknown + mashed + repeated) / Double(total) > 0.4 { issues.append(.unrecognizedWords) }
        if total >= 10, Double(Set(seen).count) / Double(total) < 0.45 { issues.append(.lowVariety) }
        if result.meetsCount, Stopwords.hasList(for: language), content.count < requirement.minimumContentWords {
            issues.append(.needsDetail)
        }
        result.issues = issues
        return result
    }

    func classify(_ token: WordToken, normalized word: String, language: String) -> TokenClass {
        let letters = Array(word.filter(\.isLetter))
        guard letters.count >= 2, !word.contains(where: \.isNumber) else { return .ignored }
        if GibberishHeuristics.longestRun(letters) >= 3 { return .repeated }
        if lexicon.isKnownWord(word, language: language) { return .known }
        if GibberishHeuristics.looksMashed(letters) { return .mashed }
        if token.isName { return .name }
        return .unknown
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'")))
            .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }
}
