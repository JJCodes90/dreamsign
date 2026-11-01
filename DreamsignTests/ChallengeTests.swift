import Foundation
import Testing
@testable import Dreamsign

@Suite("Math challenge")
struct MathProblemGeneratorTests {
    /// Evaluates "a op b" or "a × b + c" as the generator writes them.
    static func evaluate(_ text: String) -> Int? {
        let parts = text.split(separator: " ").map(String.init)
        guard parts.count == 3 || parts.count == 5, var value = Int(parts[0]) else { return nil }
        var index = 1
        while index < parts.count {
            guard let rhs = Int(parts[index + 1]) else { return nil }
            switch parts[index] {
            case "+": value += rhs
            case "−": value -= rhs
            case "×": value *= rhs
            default: return nil
            }
            index += 2
        }
        return value
    }

    @Test(arguments: MathDifficulty.allCases)
    func answersAreCorrectAndPositive(_ difficulty: MathDifficulty) {
        var generator = MathProblemGenerator(source: SeededRandomNumberGenerator(seed: 42))
        for _ in 0..<500 {
            let problem = generator.next(difficulty)
            #expect(Self.evaluate(problem.text) == problem.answer, "\(problem.text)")
            #expect(problem.answer > 0)
        }
    }

    @Test func neverRepeatsBackToBack() {
        var generator = MathProblemGenerator(source: SeededRandomNumberGenerator(seed: 7))
        var previous = generator.next(.easy)
        for _ in 0..<300 {
            let next = generator.next(.easy)
            #expect(next != previous)
            previous = next
        }
    }

    @Test func seededGeneratorIsDeterministic() {
        var a = MathProblemGenerator(source: SeededRandomNumberGenerator(seed: 99))
        var b = MathProblemGenerator(source: SeededRandomNumberGenerator(seed: 99))
        for _ in 0..<20 {
            let lhs = a.next(.hard), rhs = b.next(.hard)
            #expect(lhs == rhs)
        }
    }

    @Test func difficultyShapesTheAnswerRange() {
        var generator = MathProblemGenerator(source: SeededRandomNumberGenerator(seed: 3))
        let easy = (0..<200).map { _ in generator.next(.easy).answer }
        let hard = (0..<200).map { _ in generator.next(.hard).answer }
        #expect(easy.max()! < 100)
        #expect(hard.max()! > 150)
    }
}

@Suite("Shake detection")
struct ShakeDetectorTests {
    /// |sin| wave: a back-and-forth shake at `hertz`, sampled at 60 Hz.
    func samples(hertz: Double, amplitude: Double, seconds: Double) -> [(Double, TimeInterval)] {
        stride(from: 0.0, to: seconds, by: 1.0 / 60.0).map { t in (abs(sin(2 * .pi * hertz * t)) * amplitude, t) }
    }

    func count(_ samples: [(Double, TimeInterval)], detector: ShakeDetector = ShakeDetector()) -> Int {
        var detector = detector
        return samples.filter { detector.process(magnitude: $0.0, at: $0.1) }.count
    }

    @Test func vigorousShakingCountsSteadily() {
        // 3 Hz back-and-forth = 6 acceleration peaks per second, each one a flick.
        let shakes = count(samples(hertz: 3, amplitude: 2.2, seconds: 5))
        #expect((28...31).contains(shakes))
    }

    @Test func gentleMovementDoesNotCount() {
        #expect(count(samples(hertz: 2, amplitude: 0.8, seconds: 5)) == 0)
    }

    @Test func sustainedAccelerationCountsOnce() {
        let flat = stride(from: 0.0, to: 2.0, by: 1.0 / 60.0).map { (2.0, $0) }
        #expect(count(flat) == 1)
    }

    @Test func releaseIsRequiredBetweenShakes() {
        // `process` is mutating, so capture each result before handing it to #expect.
        var detector = ShakeDetector()
        let first = detector.process(magnitude: 1.5, at: 0)
        let notReleased = detector.process(magnitude: 0.9, at: 0.3)   // never dropped below release
        let stillHeld = detector.process(magnitude: 1.6, at: 0.6)
        let rearm = detector.process(magnitude: 0.3, at: 0.7)         // re-arms
        let second = detector.process(magnitude: 1.6, at: 0.9)
        #expect(first)
        #expect(!notReleased)
        #expect(!stillHeld)
        #expect(!rearm)
        #expect(second)
    }

    @Test func magnitudeIsEuclidean() {
        #expect(ShakeDetector.magnitude(x: 3, y: 4, z: 0) == 5)
    }
}

@Suite("Journal stats")
struct JournalStatsTests {
    let calendar = Fixtures.calendar
    let now = Fixtures.date(2026, 11, 5, 9, 0)       // Thursday morning

    func fact(_ month: Int, _ day: Int, _ hour: Int, recalled: Bool = true) -> JournalStats.EntryFact {
        JournalStats.EntryFact(date: Fixtures.date(2026, month, day, hour), recalled: recalled)
    }

    @Test func wbtbAndMorningEntriesShareAMorning() {
        let wbtb = JournalStats.morning(of: Fixtures.date(2026, 11, 5, 3, 10), calendar: calendar)
        let morning = JournalStats.morning(of: Fixtures.date(2026, 11, 5, 7, 40), calendar: calendar)
        let lateNight = JournalStats.morning(of: Fixtures.date(2026, 11, 4, 23, 30), calendar: calendar)
        #expect(wbtb == morning)
        #expect(lateNight == morning)
        #expect(morning == Fixtures.date(2026, 11, 5))
    }

    @Test func streakCountsConsecutiveMornings() {
        let facts = [fact(11, 5, 7), fact(11, 4, 3), fact(11, 4, 7), fact(11, 3, 6), fact(11, 1, 7)]
        #expect(JournalStats.recallStreak(facts, now: now, calendar: calendar) == 3)
    }

    @Test func streakSurvivesUntilTodaysEntry() {
        let facts = [fact(11, 4, 7), fact(11, 3, 7)]
        #expect(JournalStats.recallStreak(facts, now: now, calendar: calendar) == 2)
    }

    @Test func noRecallEntriesDoNotExtendTheStreak() {
        let facts = [fact(11, 5, 7, recalled: false), fact(11, 4, 7), fact(11, 3, 7, recalled: false), fact(11, 2, 7)]
        #expect(JournalStats.recallStreak(facts, now: now, calendar: calendar) == 1)
    }

    @Test func streakAcrossDaylightSavingChange() {
        // DST ended on Nov 1 2026.
        let facts = [fact(10, 31, 7), fact(11, 1, 7), fact(11, 2, 7)]
        let monday = Fixtures.date(2026, 11, 2, 10, 0)
        #expect(JournalStats.recallStreak(facts, now: monday, calendar: calendar) == 3)
    }

    @Test func longestStreak() {
        let facts = [fact(10, 1, 7), fact(10, 2, 7), fact(10, 3, 7), fact(10, 4, 7), fact(10, 10, 7), fact(10, 11, 7)]
        #expect(JournalStats.longestRecallStreak(facts, calendar: calendar) == 4)
        #expect(JournalStats.longestRecallStreak([], calendar: calendar) == 0)
    }

    @Test func weeklyBucketsIncludeEmptyWeeks() {
        let dates = [Fixtures.date(2026, 11, 5, 7), Fixtures.date(2026, 11, 2, 7), Fixtures.date(2026, 10, 20, 7)]
        let buckets = JournalStats.entriesPerWeek(dates, weeks: 4, now: now, calendar: calendar)
        #expect(buckets.count == 4)
        #expect(buckets.map(\.count) == [0, 1, 0, 2])
        #expect(buckets.last?.start == Fixtures.date(2026, 11, 1))
    }

    @Test func recallRateIsPerMorning() {
        let facts = [fact(11, 5, 3), fact(11, 5, 7, recalled: false), fact(11, 4, 7, recalled: false)]
        #expect(JournalStats.recallRate(facts, calendar: calendar) == 0.5)
        #expect(JournalStats.recallRate([], calendar: calendar) == nil)
    }

    @Test func topSignsSortByCountThenName() {
        let counts = [JournalStats.SignCount(name: "Water", count: 3), .init(name: "Mom", count: 5),
                      .init(name: "Bridge", count: 3), .init(name: "Unused", count: 0)]
        #expect(JournalStats.topSigns(counts, limit: 3).map(\.name) == ["Mom", "Bridge", "Water"])
    }
}
