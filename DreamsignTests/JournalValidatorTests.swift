import Testing
@testable import Dreamsign

@MainActor
@Suite("Journal validator")
struct JournalValidatorTests {
    static let vocabulary: Set<String> = [
        "was", "walking", "through", "my", "grandmother's", "grandmother", "old", "house", "but", "every", "door",
        "opened", "onto", "beach", "at", "night", "brother", "there", "building", "boat", "out", "of", "books",
        "in", "dark", "forest", "scary", "dream", "about", "dog", "ocean", "we", "flew", "over", "rooftops",
        "the", "and", "to", "is", "it", "they", "them", "then", "this", "that", "those", "these", "with", "for",
        "property", "met", "on", "bridge", "felt", "calm", "strange", "teacher", "train", "station", "glowing",
        "water", "falling", "rain", "upward", "mountain", "city", "red", "car", "chasing", "me", "laughing",
    ]

    let validator = JournalValidator(tokenizer: NaturalLanguageTokenizer(),
                                     lexicon: WordListLexicon(words: vocabulary))

    static let genuine = """
    I was walking through my grandmother's old house, but every door opened onto a beach at night. \
    My brother was there building a boat out of books.
    """

    @Test func genuineEntryPasses() {
        let result = validator.assess(Self.genuine, requirement: .dream)
        #expect(result.realWordCount >= 15)
        #expect(result.issues.isEmpty)
        #expect(result.isAcceptable)
        #expect(result.progress == 1)
    }

    @Test func shortGenuineEntryCountsButDoesNotPass() {
        let result = validator.assess("I was in a dark forest", requirement: .dream)
        #expect(result.realWordCount == 4)          // "I" and "a" are ignored single letters
        #expect(result.issues.isEmpty)
        #expect(!result.isAcceptable)
        #expect(abs(result.progress - 4.0 / 15.0) < 0.0001)
    }

    @Test func emptyTextIsNotAcceptable() {
        let result = validator.assess("   \n ", requirement: .noRecall)
        #expect(result.realWordCount == 0)
        #expect(!result.isAcceptable)
        #expect(result.progress == 0)
    }

    @Test func keyboardMashingIsBlocked() {
        let result = validator.assess("asdf jkl; qwer asdfgh sdfg hjkl", requirement: .noRecall)
        #expect(result.issues.contains(.keyboardMashing))
        #expect(result.primaryIssue == .keyboardMashing)
        #expect(!result.isAcceptable)
    }

    @Test func mashingPaddedWithRealWordsIsStillBlocked() {
        let text = Self.genuine + " sdkfjh lkjsdf fjdksla qpwoei zmxncb"
        let result = validator.assess(text, requirement: .dream)
        #expect(result.issues.contains(.keyboardMashing))
        #expect(!result.isAcceptable)
    }

    @Test func oneStrayMashedTokenIsTolerated() {
        let result = validator.assess(Self.genuine + " sdkfjh", requirement: .dream)
        #expect(!result.issues.contains(.keyboardMashing))
        #expect(result.isAcceptable)
    }

    @Test func stretchedLettersAreBlocked() {
        let result = validator.assess("sooooo scaaaaary dream about my dog", requirement: .noRecall)
        #expect(result.issues.contains(.repeatedCharacters))
        #expect(!result.isAcceptable)
    }

    @Test func repeatingOneWordIsLowVariety() {
        let result = validator.assess(String(repeating: "dream ", count: 20), requirement: .dream)
        #expect(result.realWordCount == 1)
        #expect(result.issues.contains(.lowVariety))
    }

    @Test func repeatingAPhraseIsLowVariety() {
        let result = validator.assess(String(repeating: "the ocean was dark and ", count: 6), requirement: .noRecall)
        #expect(result.issues.contains(.lowVariety))
        #expect(!result.isAcceptable)
    }

    @Test func stopwordPaddingNeedsDetail() {
        let text = "the and to is it they them then this that those these with for of at in was"
        let result = validator.assess(text, requirement: .noRecall)
        #expect(result.meetsCount)
        #expect(result.contentWordCount == 0)
        #expect(result.issues.contains(.needsDetail))
        #expect(!result.isAcceptable)
    }

    @Test func pronounceableNonsenseIsUnrecognized() {
        let result = validator.assess("blorp zindle fraxit mimble wobstock the dream was", requirement: .noRecall)
        #expect(result.issues.contains(.unrecognizedWords))
        #expect(!result.isAcceptable)
    }

    @Test func sleepyTyposAreForgiven() {
        let result = validator.assess(Self.genuine + " It felt strnage and wierd", requirement: .dream)
        #expect(result.issues.isEmpty)
        #expect(result.isAcceptable)
    }

    @Test func distinctCountIsCaseInsensitive() {
        let result = validator.assess("Ocean ocean OCEAN", requirement: .noRecall)
        #expect(result.realWordCount == 1)
    }

    @Test func numbersAndSingleLettersAreIgnored() {
        let result = validator.assess("At 3 we flew over 400 rooftops x", requirement: .noRecall)
        #expect(result.realWordCount == 5)          // at, we, flew, over, rooftops
        #expect(result.analyzedTokenCount == 5)
    }

    @Test func dictionaryWordsBeatKeyboardHeuristics() {
        // "property" contains the row run "erty" but is a real word.
        let known = validator.classify(WordToken(text: "property"), normalized: "property", language: "en")
        #expect(known == .known)
        let mashed = validator.classify(WordToken(text: "erty"), normalized: "erty", language: "en")
        #expect(mashed == .mashed)
    }

    @Test func namesCountAsRealWords() {
        let named = JournalValidator(tokenizer: StubTokenizer(names: ["Priya", "Tomasz", "Lisbon"]),
                                     lexicon: WordListLexicon(words: Self.vocabulary))
        let result = named.assess("Priya and Tomasz met me on a bridge in Lisbon", requirement: .noRecall)
        #expect(result.realWordCount == 9)          // 3 names + 6 dictionary words
        #expect(result.isAcceptable)
    }

    @Test func mashedTokensTaggedAsNamesDoNotCount() {
        let named = JournalValidator(tokenizer: StubTokenizer(names: ["Sdfgh"]),
                                     lexicon: WordListLexicon(words: Self.vocabulary))
        let token = WordToken(text: "Sdfgh", isName: true)
        #expect(named.classify(token, normalized: "sdfgh", language: "en") == .mashed)
    }

    @Test(arguments: [
        ("asdf", true), ("hjkl", true), ("qwerty", true), ("lkjsdf", true), ("fjdksla", true),
        ("jkjkjkjk", true), ("lalala", true), ("dream", false), ("strnage", false), ("wierd", false),
        ("blorp", false), ("ocean", false),
    ])
    func mashHeuristics(word: String, mashed: Bool) {
        #expect(GibberishHeuristics.looksMashed(Array(word)) == mashed)
    }

    @Test func heuristicsBuildingBlocks() {
        #expect(GibberishHeuristics.longestRun(Array("aaab")) == 3)
        #expect(GibberishHeuristics.longestRun(Array("abc")) == 1)
        #expect(GibberishHeuristics.isPeriodic(Array("abcabc")))
        #expect(!GibberishHeuristics.isPeriodic(Array("banana")))
        #expect(KeyboardGeometry.containsRowRun(Array("lkjh")))
        #expect(!KeyboardGeometry.containsRowRun(Array("house")))
        #expect(KeyboardGeometry.areAdjacent("a", "s"))
        #expect(KeyboardGeometry.areAdjacent("a", "q"))
        #expect(!KeyboardGeometry.areAdjacent("a", "p"))
        #expect(KeyboardGeometry.adjacencyRatio(Array("jkjkjk")) == 1)
    }

    @Test func requirementPresets() {
        #expect(JournalRequirement.dream.minimumWords == 15)
        #expect(JournalRequirement.noRecall.minimumWords == 8)
        #expect(JournalRequirement.dream.minimumContentWords == 3)
        #expect(JournalRequirement(minimumWords: 40).minimumContentWords == 10)
    }
}

/// End-to-end with the real on-device dictionaries (NLEmbedding + UITextChecker).
@MainActor
@Suite("Journal validator · system lexicon")
struct SystemLexiconTests {
    let validator = JournalValidator.system()

    @Test func realDreamPasses() {
        let text = """
        I was standing in a train station that slowly filled with warm water. My old teacher handed me \
        a glowing red umbrella and said the trains only leave when it rains upward.
        """
        let result = validator.assess(text, requirement: .dream)
        #expect(result.realWordCount >= 15)
        #expect(result.isAcceptable, "issues: \(result.issues)")
    }

    @Test func mashingFails() {
        let result = validator.assess("asdkfj qwoeiru zxmcnv lkasjdf poqwieu alskdjf qpwoeiru", requirement: .noRecall)
        #expect(!result.isAcceptable)
        #expect(result.realWordCount < 3)
    }
}
