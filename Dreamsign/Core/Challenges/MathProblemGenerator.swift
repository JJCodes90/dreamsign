import Foundation

enum MathDifficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case easy, medium, hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: String(localized: "Easy")
        case .medium: String(localized: "Medium")
        case .hard: String(localized: "Hard")
        }
    }

    var example: String {
        switch self {
        case .easy: "34 + 27"
        case .medium: "38 × 7"
        case .hard: "23 × 14"
        }
    }
}

struct MathProblem: Hashable, Sendable {
    let text: String
    let answer: Int
}

/// Problems that need a little working memory but no pen and paper. Answers are always
/// positive integers so the keypad never needs a minus key.
struct MathProblemGenerator<Source: RandomNumberGenerator> {
    var source: Source
    private var last: MathProblem?

    init(source: Source) { self.source = source }

    mutating func next(_ difficulty: MathDifficulty) -> MathProblem {
        var problem = make(difficulty)
        while problem == last { problem = make(difficulty) }
        last = problem
        return problem
    }

    private mutating func make(_ difficulty: MathDifficulty) -> MathProblem {
        let variant = Bool.random(using: &source)
        switch difficulty {
        case .easy:
            if variant {
                let a = int(12...59), b = int(11...39)
                return MathProblem(text: "\(a) + \(b)", answer: a + b)
            }
            let a = int(41...98), b = int(11...(a - 12))
            return MathProblem(text: "\(a) − \(b)", answer: a - b)
        case .medium:
            if variant {
                let a = int(13...49), b = int(3...9)
                return MathProblem(text: "\(a) × \(b)", answer: a * b)
            }
            let a = int(124...489), b = int(37...99)
            return MathProblem(text: "\(a) + \(b)", answer: a + b)
        case .hard:
            if variant {
                let a = int(12...29), b = int(11...19)
                return MathProblem(text: "\(a) × \(b)", answer: a * b)
            }
            let a = int(6...12), b = int(6...12), c = int(13...49)
            return MathProblem(text: "\(a) × \(b) + \(c)", answer: a * b + c)
        }
    }

    private mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &source)
    }
}

extension MathProblemGenerator where Source == SystemRandomNumberGenerator {
    init() { self.init(source: SystemRandomNumberGenerator()) }
}

/// Deterministic generator for tests (SplitMix64).
struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
