import Foundation
import NaturalLanguage

/// A sign the journal has seen before.
struct KnownSign: Hashable, Sendable {
    var name: String
    var category: DreamSignCategory
    var count: Int
}

struct SignSuggestion: Hashable, Identifiable, Sendable {
    var name: String
    var category: DreamSignCategory
    /// How many earlier dreams it appeared in (0 = new).
    var earlierCount: Int
    /// Short note for classic signs ("a classic reality-check cue").
    var note: String?

    var id: String { DreamSign.key(for: name) }
}

struct DreamReading: Hashable, Sendable {
    var title: String?
    var signs: [SignSuggestion]
    /// Read by Apple Intelligence (vs. the on-device word rules).
    var usedModel = false
}

/// Suggestions without a language model: signs already in the journal that this dream
/// mentions, classic dream-sign themes, and names of people and places.
struct HeuristicSignReader: Sendable {
    struct Theme: Sendable {
        var name: String
        var category: DreamSignCategory
        var triggers: [String]
        var note: String?
    }

    static let themes: [Theme] = [
        Theme(name: String(localized: "Strange clocks"), category: .theme, triggers: ["clock", "clocks", "watch said", "the time was"],
              note: String(localized: "a classic reality-check cue")),
        Theme(name: String(localized: "Flying"), category: .theme, triggers: ["fly", "flying", "flew", "floating", "levitat"]),
        Theme(name: String(localized: "Teeth falling out"), category: .theme, triggers: ["teeth", "tooth"]),
        Theme(name: String(localized: "Running late"), category: .theme, triggers: ["late for", "running late", "missed the", "missed my"]),
        Theme(name: String(localized: "Exams"), category: .theme, triggers: ["exam", "test i", "quiz", "studied"]),
        Theme(name: String(localized: "Water"), category: .theme, triggers: ["water", "ocean", "flood", "swimming", "underwater"]),
        Theme(name: String(localized: "Falling"), category: .theme, triggers: ["falling", "fell off", "fell from", "fell down"]),
        Theme(name: String(localized: "Being chased"), category: .theme, triggers: ["chased", "chasing me", "running from", "ran from"]),
        Theme(name: String(localized: "Endless hallways"), category: .place, triggers: ["hallway", "corridor", "endless"]),
        Theme(name: String(localized: "Stairs"), category: .theme, triggers: ["stairs", "staircase", "steps that"]),
        Theme(name: String(localized: "School"), category: .place, triggers: ["school", "classroom", "teacher"]),
        Theme(name: String(localized: "Phones that won't work"), category: .theme, triggers: ["phone wouldn", "couldn't call", "dial", "phone broke"]),
        Theme(name: String(localized: "Text that changes"), category: .theme, triggers: ["couldn't read", "words kept", "rewriting", "letters"],
              note: String(localized: "a classic reality-check cue")),
    ]

    var limit = 5

    func read(_ text: String, known: [KnownSign], tagged: Set<String> = []) -> DreamReading {
        let lower = text.lowercased()
        var results: [SignSuggestion] = []
        func add(_ suggestion: SignSuggestion) {
            guard results.count < limit, !tagged.contains(suggestion.id), !results.contains(where: { $0.id == suggestion.id })
            else { return }
            results.append(suggestion)
        }

        // 1. Known signs mentioned in this dream, most frequent first.
        for sign in known.sorted(by: { $0.count > $1.count }) where Self.mentions(lower, sign.name.lowercased()) {
            add(SignSuggestion(name: sign.name, category: sign.category, earlierCount: sign.count))
        }
        // 2. Classic themes.
        let knownKeys = Dictionary(known.map { (DreamSign.key(for: $0.name), $0) }, uniquingKeysWith: { a, _ in a })
        for theme in Self.themes where theme.triggers.contains(where: { lower.contains($0) }) {
            let themeKey = DreamSign.key(for: theme.name)
            // "School" adds nothing next to a known "Old school".
            if results.contains(where: { $0.id.contains(themeKey) || themeKey.contains($0.id) }) { continue }
            let existing = knownKeys[themeKey]
            add(SignSuggestion(name: existing?.name ?? theme.name, category: existing?.category ?? theme.category,
                               earlierCount: existing?.count ?? 0, note: theme.note))
        }
        // 3. Names of people and places.
        for (name, category) in Self.names(in: text) {
            let existing = knownKeys[DreamSign.key(for: name)]
            add(SignSuggestion(name: existing?.name ?? name, category: existing?.category ?? category,
                               earlierCount: existing?.count ?? 0))
        }
        return DreamReading(title: nil, signs: results)
    }

    /// Whole-word (or whole-phrase) match.
    static func mentions(_ text: String, _ phrase: String) -> Bool {
        guard phrase.count > 1 else { return false }
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: phrase, options: [.diacriticInsensitive], range: searchRange) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !(before?.isLetter ?? false), !(after?.isLetter ?? false) { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    static func names(in text: String) -> [(String, DreamSignCategory)] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found: [(String, DreamSignCategory)] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            switch tag {
            case .personalName: found.append((String(text[range]), .person))
            case .placeName: found.append((String(text[range]), .place))
            default: break
            }
            return true
        }
        return found
    }
}
