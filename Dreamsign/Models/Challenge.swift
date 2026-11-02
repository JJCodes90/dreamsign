import Foundation

/// One dismissal challenge in an alarm's sequence, with its settings.
struct Challenge: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case shake, math, journal, steps, scan, phrase, memory

        var id: String { rawValue }

        var title: String {
            switch self {
            case .shake: String(localized: "Shake")
            case .math: String(localized: "Math")
            case .journal: String(localized: "Dream journal")
            case .steps: String(localized: "Walk")
            case .scan: String(localized: "Scan a code")
            case .phrase: String(localized: "Type a phrase")
            case .memory: String(localized: "Memory")
            }
        }

        var symbol: String {
            switch self {
            case .shake: "iphone.gen3.radiowaves.left.and.right"
            case .math: "plus.forwardslash.minus"
            case .journal: "moon.stars"
            case .steps: "figure.walk"
            case .scan: "barcode.viewfinder"
            case .phrase: "character.cursor.ibeam"
            case .memory: "square.grid.3x3.fill"
            }
        }

        var pitch: String {
            switch self {
            case .shake: String(localized: "Get your body moving.")
            case .math: String(localized: "Switch your brain on.")
            case .journal: String(localized: "Catch the dream before it fades.")
            case .steps: String(localized: "Out of bed and on your feet.")
            case .scan: String(localized: "Walk to a code in another room.")
            case .phrase: String(localized: "Focus your eyes and fingers.")
            case .memory: String(localized: "Prove your brain is online.")
            }
        }
    }

    static let shakeOptions = [20, 30, 50, 80, 120]
    static let problemOptions = [1, 2, 3, 5, 8]
    static let wordOptions = [8, 15, 25, 40]
    static let stepOptions = [20, 30, 50, 100]
    static let memoryOptions = [4, 5, 6, 7]

    var id = UUID()
    var kind: Kind
    var shakeCount = 50
    /// 0 = needs a hard shake … 1 = a gentle wobble counts.
    var shakeSensitivity = ShakeDetector.defaultSensitivity
    var mathDifficulty: MathDifficulty = .medium
    var mathProblems = 3
    var journalWords = JournalRequirement.dream.minimumWords
    var stepCount = 30
    var phraseLength: PhraseLength = .medium
    var memoryLength = 5
    /// Payload of the barcode or QR code to scan, registered in settings.
    var scanCode = ""
    /// Where the code is, e.g. "Toothpaste, bathroom".
    var scanLabel = ""

    init(kind: Kind) { self.kind = kind }

    var summary: String {
        switch kind {
        case .shake: String(localized: "\(shakeCount) shakes")
        case .math: String(localized: "\(mathProblems) in a row · \(mathDifficulty.title)")
        case .journal: String(localized: "\(journalWords) words")
        case .steps: String(localized: "\(stepCount) steps")
        case .scan: scanCode.isEmpty ? String(localized: "Not set up yet") : (scanLabel.isEmpty ? String(localized: "Code registered") : scanLabel)
        case .phrase: phraseLength.title
        case .memory: String(localized: "\(memoryLength)-step pattern")
        }
    }

    /// A scan challenge without a registered code can't be done; it falls back to math.
    var needsSetup: Bool { kind == .scan && scanCode.isEmpty }

    // Tolerant decoding: new settings get defaults instead of dropping the alarm's challenges.
    enum CodingKeys: String, CodingKey {
        case id, kind, shakeCount, shakeSensitivity, mathDifficulty, mathProblems, journalWords
        case stepCount, phraseLength, memoryLength, scanCode, scanLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        shakeCount = try container.decodeIfPresent(Int.self, forKey: .shakeCount) ?? 50
        shakeSensitivity = try container.decodeIfPresent(Double.self, forKey: .shakeSensitivity) ?? ShakeDetector.defaultSensitivity
        mathDifficulty = try container.decodeIfPresent(MathDifficulty.self, forKey: .mathDifficulty) ?? .medium
        mathProblems = try container.decodeIfPresent(Int.self, forKey: .mathProblems) ?? 3
        journalWords = try container.decodeIfPresent(Int.self, forKey: .journalWords) ?? JournalRequirement.dream.minimumWords
        stepCount = try container.decodeIfPresent(Int.self, forKey: .stepCount) ?? 30
        phraseLength = try container.decodeIfPresent(PhraseLength.self, forKey: .phraseLength) ?? .medium
        memoryLength = try container.decodeIfPresent(Int.self, forKey: .memoryLength) ?? 5
        scanCode = try container.decodeIfPresent(String.self, forKey: .scanCode) ?? ""
        scanLabel = try container.decodeIfPresent(String.self, forKey: .scanLabel) ?? ""
    }

    /// Body first (fights sleep inertia), journal while recall is fresh, math last.
    static let defaults: [Challenge] = [Challenge(kind: .shake), Challenge(kind: .journal)]
}
