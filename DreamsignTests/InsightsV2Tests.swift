import Foundation
import Testing
@testable import Dreamsign

@Suite("Suggested dream signs")
struct HeuristicSignReaderTests {
    let reader = HeuristicSignReader()
    let known = [KnownSign(name: "Old school", category: .place, count: 5),
                 KnownSign(name: "Grandma", category: .person, count: 3),
                 KnownSign(name: "Cat", category: .theme, count: 9)]

    @Test func knownSignsComeFirstByFrequency() {
        let reading = reader.read("Back at my old school. Grandma was there, and the clock had no hands.", known: known)
        #expect(reading.signs.prefix(2).map(\.name) == ["Old school", "Grandma"])
        #expect(reading.signs.first?.earlierCount == 5)
        #expect(reading.signs.contains { $0.name == String(localized: "Strange clocks") && $0.note != nil })
        // "School" adds nothing next to "Old school".
        #expect(!reading.signs.contains { $0.name == String(localized: "School") })
        #expect(reading.title == nil)
    }

    @Test func wholeWordsOnly() {
        #expect(HeuristicSignReader.mentions("a cat sat", "cat"))
        #expect(!HeuristicSignReader.mentions("concatenate the catalog", "cat"))
        #expect(HeuristicSignReader.mentions("my old school, again", "old school"))
    }

    @Test func taggedAndDuplicatesAreSkippedAndCapped() {
        let text = "flying over water, teeth falling, an exam, being chased down endless stairs, the cat"
        let reading = reader.read(text, known: known, tagged: [DreamSign.key(for: "Cat")])
        #expect(!reading.signs.contains { $0.name == "Cat" })
        #expect(reading.signs.count <= 5)
        #expect(Set(reading.signs.map(\.id)).count == reading.signs.count)
    }
}

@Suite("Dream calendar")
struct DreamCalendarTests {
    let calendar = Fixtures.calendar

    @Test func monthStartsUnderItsWeekdayAndKeepsTheBestLevel() {
        // November 2026 starts on a Sunday.
        let facts = [
            DreamCalendar.Fact(date: Fixtures.date(2026, 11, 2, 7, 0), recalled: true, lucid: false, words: 10),
            DreamCalendar.Fact(date: Fixtures.date(2026, 11, 2, 7, 30), recalled: true, lucid: false, words: 60),
            DreamCalendar.Fact(date: Fixtures.date(2026, 11, 3, 3, 0), recalled: true, lucid: true, words: 20),
            DreamCalendar.Fact(date: Fixtures.date(2026, 11, 4, 7, 0), recalled: false, lucid: false, words: 8),
        ]
        let days = DreamCalendar.month(containing: Fixtures.date(2026, 11, 15), facts: facts, calendar: calendar)
        #expect(days.prefix(1).allSatisfy { $0 != nil })          // no leading blanks
        #expect(days.compactMap { $0 }.count == 30)
        let level = { (day: Int) in days.compactMap { $0 }[day - 1].level }
        #expect(level(1) == .empty)
        #expect(level(2) == .full)
        #expect(level(3) == .lucid)
        #expect(level(4) == .fragment)
    }

    @Test func leadingBlanks() {
        // October 2026 starts on a Thursday: four blanks with Sunday first.
        let days = DreamCalendar.month(containing: Fixtures.date(2026, 10, 10), facts: [], calendar: calendar)
        #expect(days.prefix(4).allSatisfy { $0 == nil })
        #expect(days[4] != nil)
        #expect(days.count == 4 + 31)
    }
}

@Suite("Milestones")
struct MilestoneTests {
    let calendar = Fixtures.calendar

    func mornings(_ count: Int, lucidEvery: Int = 0, from start: Date = Fixtures.date(2026, 10, 1, 7)) -> [JournalStats.EntryFact] {
        (0..<count).map { index in
            JournalStats.EntryFact(date: start.addingTimeInterval(Double(index) * 86_400), recalled: true,
                                   lucid: lucidEvery > 0 && index % lucidEvery == lucidEvery - 1)
        }
    }

    @Test func achievementsCarryTheDateReached() {
        let facts = mornings(12, lucidEvery: 4)
        let all = Milestones.all(facts, calendar: calendar)
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        #expect(byID["first-dream"]?.achievedAt == facts[0].date)
        #expect(byID["first-lucid"]?.achievedAt == facts[3].date)
        #expect(byID["streak-7"]?.isAchieved == true)
        #expect(byID["streak-30"]?.current == 12)
        #expect(byID["dreams-10"]?.achievedAt == facts[9].date)
        #expect(byID["dreams-25"]?.current == 12)
        #expect(byID["lucid-5"]?.current == 3)
    }

    @Test func highlightsLeaveRoomForTheNextGoal() {
        let highlights = Milestones.highlights(mornings(12, lucidEvery: 4), calendar: calendar)
        #expect(highlights.count == 3)
        #expect(highlights.prefix(2).allSatisfy(\.isAchieved))
        #expect(highlights.last?.isAchieved == false)
        #expect(Milestones.highlights([], calendar: calendar).allSatisfy { !$0.isAchieved })
    }

    @Test func aGapBreaksTheStreak() {
        let facts = mornings(4) + mornings(4, from: Fixtures.date(2026, 10, 10, 7))
        let streak = Milestones.all(facts, calendar: calendar).first { $0.id == "streak-7" }
        #expect(streak?.isAchieved == false)
        #expect(streak?.current == 4)
    }
}

@Suite("Sleep from Health")
struct SleepNightsTests {
    let calendar = Fixtures.calendar

    @Test func overlappingSourcesAreNotCountedTwice() {
        let bed = Fixtures.date(2026, 11, 1, 23, 0)
        let samples = [
            SleepSample(start: bed, end: bed.addingTimeInterval(4 * 3600), stage: .asleep),
            SleepSample(start: bed.addingTimeInterval(3 * 3600), end: bed.addingTimeInterval(7 * 3600), stage: .asleep),
            SleepSample(start: bed.addingTimeInterval(5 * 3600), end: bed.addingTimeInterval(6 * 3600), stage: .rem),
            SleepSample(start: bed.addingTimeInterval(7 * 3600), end: bed.addingTimeInterval(7.5 * 3600), stage: .awake),
        ]
        let nights = SleepNights.summarize(samples, calendar: calendar)
        #expect(nights.count == 1)
        #expect(nights[0].asleepMinutes == 420)
        #expect(nights[0].remMinutes == 60)
        #expect(nights[0].morning == Fixtures.date(2026, 11, 2))
    }

    @Test func comparesRecallOnLongAndShortNights() {
        var nights: [SleepNight] = []
        var facts: [JournalStats.EntryFact] = []
        for day in 1...8 {
            let morning = Fixtures.date(2026, 10, day)
            let long = day <= 4
            nights.append(SleepNight(morning: morning, asleepMinutes: long ? 480 : 360, remMinutes: 90))
            // Recall every long night, one short night.
            if long || day == 5 {
                facts.append(JournalStats.EntryFact(date: Fixtures.date(2026, 10, day, 7), recalled: true))
            }
        }
        let comparison = SleepNights.recallComparison(nights, facts: facts, calendar: calendar)
        #expect(comparison?.longRate == 1)
        #expect(comparison?.shortRate == 0.25)
        #expect(SleepNights.recallComparison(Array(nights.prefix(5)), facts: facts, calendar: calendar) == nil)
    }
}

@Suite("Widget data")
struct SharedStoreTests {
    @Test func realityChecksCountPerDay() {
        let day = Fixtures.date(2026, 11, 2, 9)
        let before = SharedStore.realityChecksToday(now: day, calendar: Fixtures.calendar)
        SharedStore.logRealityCheck(now: day, calendar: Fixtures.calendar)
        #expect(SharedStore.realityChecksToday(now: day, calendar: Fixtures.calendar) == before + 1)
        #expect(SharedStore.realityChecksToday(now: day.addingTimeInterval(86_400), calendar: Fixtures.calendar) == 0)
    }

    @Test func snapshotRoundTrips() {
        let original = SharedStore.snapshot
        defer { SharedStore.snapshot = original }
        SharedStore.snapshot = .sample
        #expect(SharedStore.snapshot?.tonightSign == WidgetSnapshot.sample.tonightSign)
        #expect(SharedStore.snapshot?.recallStreak == 12)
    }
}
