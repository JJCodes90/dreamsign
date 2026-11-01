import Foundation
import NaturalLanguage
import UIKit

/// `NLTokenizer` word tokens + `NLTagger` name detection + `NLLanguageRecognizer`.
@MainActor
struct NaturalLanguageTokenizer: WordTokenizing {
    func tokenize(_ text: String) -> (tokens: [WordToken], language: String) {
        let language = Self.dominantLanguage(of: text)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(language)

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)

        let nameTags: Set<NLTag> = [.personalName, .placeName, .organizationName]
        var tokens: [WordToken] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let (tag, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType)
            tokens.append(WordToken(text: String(text[range]), isName: tag.map(nameTags.contains) ?? false))
            return true
        }
        return (tokens, language.rawValue)
    }

    /// Short sleepy text is easy to misidentify, so require some confidence before
    /// leaving the person's own language.
    static func dominantLanguage(of text: String) -> NLLanguage {
        let fallback = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier }
            .map(NLLanguage.init(rawValue:)) ?? .english
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.6, text.count >= 24
        else { return fallback }
        return language
    }
}

/// Dictionary check: on-device `NLEmbedding` vocabulary first, `UITextChecker` second.
@MainActor
final class SystemLexicon: Lexicon {
    static let shared = SystemLexicon()

    private let checker = UITextChecker()
    private var embeddings: [String: NLEmbedding] = [:]
    private var unavailableEmbeddings: Set<String> = []
    private var cache: [String: Bool] = [:]

    func isKnownWord(_ word: String, language: String) -> Bool {
        let key = language + "|" + word
        if let cached = cache[key] { return cached }
        let known = embedding(for: language)?.contains(word) == true || spellCheckerAccepts(word, language: language)
        cache[key] = known
        return known
    }

    private func embedding(for language: String) -> NLEmbedding? {
        if let embedding = embeddings[language] { return embedding }
        guard !unavailableEmbeddings.contains(language) else { return nil }
        guard let embedding = NLEmbedding.wordEmbedding(for: NLLanguage(rawValue: language)) else {
            unavailableEmbeddings.insert(language)
            return nil
        }
        embeddings[language] = embedding
        return embedding
    }

    private func spellCheckerAccepts(_ word: String, language: String) -> Bool {
        guard let checkerLanguage = Self.checkerLanguage(for: language) else { return false }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let miss = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: checkerLanguage)
        return miss.location == NSNotFound
    }

    private static func checkerLanguage(for code: String) -> String? {
        let available = UITextChecker.availableLanguages
        if available.contains(code) { return code }
        return available.first { $0.hasPrefix(code + "_") || $0.hasPrefix(code + "-") }
    }
}

extension JournalValidator {
    static func system() -> JournalValidator {
        JournalValidator(tokenizer: NaturalLanguageTokenizer(), lexicon: SystemLexicon.shared)
    }
}
