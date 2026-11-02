import Foundation

/// One dismissal challenge in an alarm's sequence, with its settings.
struct Challenge: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case shake, math, journal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .shake: String(localized: "Shake")
            case .math: String(localized: "Math")
            case .journal: String(localized: "Dream journal")
            }
        }

        var symbol: String {
            switch self {
            case .shake: "iphone.gen3.radiowaves.left.and.right"
            case .math: "plus.forwardslash.minus"
            case .journal: "moon.stars"
            }
        }

        var pitch: String {
            switch self {
            case .shake: String(localized: "Get your body moving.")
            case .math: String(localized: "Switch your brain on.")
            case .journal: String(localized: "Catch the dream before it fades.")
            }
        }
    }

    static let shakeOptions = [20, 30, 50, 80, 120]
    static let problemOptions = [1, 2, 3, 5, 8]
    static let wordOptions = [8, 15, 25, 40]

    var id = UUID()
    var kind: Kind
    var shakeCount = 50
    /// 0 = needs a hard shake … 1 = a gentle wobble counts.
    var shakeSensitivity = ShakeDetector.defaultSensitivity
    var mathDifficulty: MathDifficulty = .medium
    var mathProblems = 3
    var journalWords = JournalRequirement.dream.minimumWords

    init(kind: Kind) { self.kind = kind }

    var summary: String {
        switch kind {
        case .shake: String(localized: "\(shakeCount) shakes")
        case .math: String(localized: "\(mathProblems) in a row · \(mathDifficulty.title)")
        case .journal: String(localized: "\(journalWords) words")
        }
    }

    // Tolerant decoding: new settings get defaults instead of dropping the alarm's challenges.
    enum CodingKeys: String, CodingKey { case id, kind, shakeCount, shakeSensitivity, mathDifficulty, mathProblems, journalWords }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        shakeCount = try container.decodeIfPresent(Int.self, forKey: .shakeCount) ?? 50
        shakeSensitivity = try container.decodeIfPresent(Double.self, forKey: .shakeSensitivity) ?? ShakeDetector.defaultSensitivity
        mathDifficulty = try container.decodeIfPresent(MathDifficulty.self, forKey: .mathDifficulty) ?? .medium
        mathProblems = try container.decodeIfPresent(Int.self, forKey: .mathProblems) ?? 3
        journalWords = try container.decodeIfPresent(Int.self, forKey: .journalWords) ?? JournalRequirement.dream.minimumWords
    }

    /// Body first (fights sleep inertia), journal while recall is fresh, math last.
    static let defaults: [Challenge] = [Challenge(kind: .shake), Challenge(kind: .journal)]
}
