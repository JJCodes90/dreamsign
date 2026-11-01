import Foundation

/// Function words that carry no dream content. Used so "the and of to in…" can't pass as a journal.
enum Stopwords {
    static func isStopword(_ word: String, language: String) -> Bool {
        guard language.hasPrefix("en") else { return false }
        return english.contains(word.replacingOccurrences(of: "’", with: "'"))
    }

    static func hasList(for language: String) -> Bool { language.hasPrefix("en") }

    private static let english: Set<String> = [
        "a", "about", "above", "after", "again", "against", "all", "am", "an", "and", "any", "are", "as", "at",
        "be", "because", "been", "before", "being", "below", "between", "both", "but", "by",
        "can", "could", "did", "do", "does", "doing", "down", "during",
        "each", "even", "ever", "every", "few", "for", "from", "further",
        "had", "has", "have", "having", "he", "her", "here", "hers", "herself", "him", "himself", "his", "how",
        "i", "if", "in", "into", "is", "it", "its", "itself", "just",
        "me", "more", "most", "my", "myself", "no", "nor", "not", "now",
        "of", "off", "on", "once", "only", "or", "other", "our", "ours", "ourselves", "out", "over", "own",
        "same", "she", "should", "so", "some", "such",
        "than", "that", "the", "their", "theirs", "them", "themselves", "then", "there", "these", "they",
        "this", "those", "through", "to", "too", "under", "until", "up", "us",
        "very", "was", "we", "were", "what", "when", "where", "which", "while", "who", "whom", "why",
        "will", "with", "would", "you", "your", "yours", "yourself", "yourselves",
        "also", "really", "like", "got", "get", "go", "went", "one", "thing", "things", "kind", "sort",
        "i'm", "it's", "don't", "didn't", "wasn't", "couldn't", "i'd", "i've", "there's", "that's",
    ]
}
