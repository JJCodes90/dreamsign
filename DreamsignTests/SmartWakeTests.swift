import Foundation
import Testing
@testable import Dreamsign

@Suite("Phrase challenge")
struct PhraseMatcherTests {
    let matcher = PhraseMatcher("I'll remember my dreams, today.")

    @Test func forgivesCasePunctuationAndSpacing() {
        #expect(matcher.isMatch("ill remember my dreams today"))
        #expect(matcher.isMatch("  I’LL   Remember my DREAMS today!! "))
        #expect(!matcher.isMatch("ill remember my dream today"))
    }

    @Test func tracksProgressAndMistakes() {
        #expect(matcher.matchedCount("") == 0)
        #expect(matcher.matchedCount("ill rem") == 7)
        #expect(!matcher.hasMistake("ill rem"))
        #expect(matcher.hasMistake("ill rex"))
        #expect(matcher.progress("ill remember my dreams today") == 1)
    }

    @Test func highlightsTheOriginalText() {
        #expect(matcher.matchedPrefix("") == "")
        #expect(matcher.matchedPrefix("ill") == "I'll")
        #expect(matcher.matchedPrefix("ill re") == "I'll re")
        #expect(matcher.matchedPrefix("ill remember my dreams today") == "I'll remember my dreams, today")
    }

    @Test(arguments: PhraseLength.allCases)
    func everyPhraseMatchesItself(_ length: PhraseLength) {
        for phrase in length.phrases {
            #expect(PhraseMatcher(phrase).isMatch(phrase))
            #expect(PhraseMatcher(phrase).matchedPrefix(phrase).count >= phrase.count - 1)
        }
    }
}

@Suite("Memory challenge")
struct MemoryGameTests {
    @Test func patternsHaveNoBackToBackRepeats() {
        var random = SeededRandomNumberGenerator(seed: 3)
        for length in Challenge.memoryOptions {
            var game = MemoryGame(length: length)
            for _ in 0..<200 {
                game.newPattern(using: &random)
                #expect(game.pattern.count == length)
                #expect(zip(game.pattern, game.pattern.dropFirst()).allSatisfy { $0 != $1 })
                #expect(game.pattern.allSatisfy { (0..<MemoryGame.tileCount).contains($0) })
            }
        }
    }

    @Test func solvingAndMistakes() {
        var random = SeededRandomNumberGenerator(seed: 8)
        var game = MemoryGame(length: 4)
        game.newPattern(using: &random)
        let pattern = game.pattern
        #expect(game.tap(pattern[0]) == .correct)
        let wrong = (pattern[1] + 1) % MemoryGame.tileCount
        #expect(game.tap(wrong) == .mistake)
        #expect(game.entered.isEmpty)
        var last = MemoryGame.Result.correct
        for tile in pattern { last = game.tap(tile) }
        #expect(last == .solved)
    }
}

@Suite("Wake-up check dots")
struct DotLayoutTests {
    @Test func dotsStayInsideAndApart() {
        var random = SeededRandomNumberGenerator(seed: 21)
        for _ in 0..<200 {
            let points = DotLayout.positions(count: 3, using: &random)
            #expect(points.count == 3)
            #expect(points.allSatisfy { (0.15...0.85).contains($0.x) && (0.15...0.85).contains($0.y) })
            for i in points.indices {
                for j in points.indices where j > i {
                    #expect(hypot(points[i].x - points[j].x, points[i].y - points[j].y) >= 0.2)
                }
            }
        }
    }
}

@Suite("Sleep plan")
struct SleepPlanTests {
    @Test func bedtimesEndOnACycle() {
        let options = SleepPlan.options(forWake: AlarmTime(hour: 6, minute: 45))
        #expect(options.map(\.bedtime) == [AlarmTime(hour: 0, minute: 30), AlarmTime(hour: 23, minute: 0), AlarmTime(hour: 21, minute: 30)])
        #expect(options.map(\.sleepMinutes) == [360, 450, 540])
        #expect(SleepPlan.closestOption(forWake: AlarmTime(hour: 6, minute: 45), goalMinutes: 480).cycles == 5)
    }

    @Test func weeklyNudgesLandTheEveningBefore() {
        let nudges = SleepPlan.weeklyNudges([
            .init(wake: AlarmTime(hour: 6, minute: 45), weekdays: [.monday, .friday], goalMinutes: 480, label: "Work"),
        ])
        // In bed by 10:30 PM → nudge at 10:00 PM on Sunday and Thursday.
        #expect(nudges.map(\.weekday) == [1, 5])
        #expect(nudges.allSatisfy { $0.time == AlarmTime(hour: 22, minute: 0) && $0.bedtime == AlarmTime(hour: 22, minute: 30) })
    }

    @Test func lateAlarmsNudgeAfterMidnightTheSameDay() {
        let nudges = SleepPlan.weeklyNudges([
            .init(wake: AlarmTime(hour: 10, minute: 0), weekdays: [.saturday], goalMinutes: 480, label: "Lazy"),
        ])
        #expect(nudges.count == 1)
        #expect(nudges[0].weekday == 7)
        #expect(nudges[0].time == AlarmTime(hour: 1, minute: 15))
    }

    @Test func sharedNightKeepsTheEarlierBedtime() {
        let nudges = SleepPlan.weeklyNudges([
            .init(wake: AlarmTime(hour: 7, minute: 30), weekdays: [.tuesday], goalMinutes: 480, label: "Late"),
            .init(wake: AlarmTime(hour: 5, minute: 30), weekdays: [.tuesday], goalMinutes: 420, label: "Gym"),
        ])
        #expect(nudges.count == 1)
        #expect(nudges[0].weekday == 2)
        #expect(nudges[0].time == AlarmTime(hour: 21, minute: 45))   // 5:30 − 7 h − 15 − 30
        #expect(nudges[0].label == "Gym")
    }

    @Test func oneNudgeAcrossMidnight() {
        // Sunday 11:15 PM and Monday 12:15 AM are the same night: only the earlier one stays.
        let nudges = SleepPlan.weeklyNudges([
            .init(wake: AlarmTime(hour: 9, minute: 0), weekdays: [.monday], goalMinutes: 480, label: "Late"),
            .init(wake: AlarmTime(hour: 8, minute: 0), weekdays: [.monday], goalMinutes: 480, label: "Early"),
        ])
        #expect(nudges.count == 1)
        #expect(nudges[0].label == "Early")
        #expect(nudges[0].weekday == 1)
        #expect(nudges[0].time == AlarmTime(hour: 23, minute: 15))
    }
}

@Suite("Smart wake chain")
struct SmartWakeChainTests {
    let planner = ChainPlanner(calendar: Fixtures.calendar)
    let monday0600 = Fixtures.date(2026, 11, 2, 6, 0)

    func spec(gentle: Int? = nil, revision: Int = 1) -> AlarmSpec {
        AlarmSpec(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, time: AlarmTime(hour: 7, minute: 0),
                  weekdays: .weekdays, label: "Wake", soundID: "system", chainLength: 15, kind: .wake, isEnabled: true,
                  revision: revision, modifiedAt: Fixtures.date(2026, 10, 1), gentleMinutes: gentle)
    }

    func requests(_ operations: [ChainOperation]) -> [RingRequest] {
        operations.compactMap { operation -> RingRequest? in
            if case .scheduleRing(let request) = operation { return request }
            return nil
        }
    }

    func cancelled(_ operations: [ChainOperation]) -> Set<UUID> {
        Set(operations.compactMap { operation -> UUID? in
            if case .cancel(let id) = operation { return id }
            return nil
        })
    }

    func snapshot(_ operations: [ChainOperation]) -> [AlarmSnapshot] {
        operations.compactMap { operation -> AlarmSnapshot? in
            switch operation {
            case .schedulePrimary(let spec): AlarmSnapshot(id: spec.id, isAlerting: false)
            case .scheduleRing(let request): AlarmSnapshot(id: request.ring.id, isAlerting: false)
            default: nil
            }
        }
    }

    @Test func gentleStartArmsASoftRingBeforeTheAlarm() {
        let plan = planner.resync(ChainState(specs: [spec(gentle: 10)]), existing: [], now: monday0600)
        let gentle = requests(plan.operations).filter { $0.style == .gentle }
        #expect(gentle.count == 1)
        #expect(gentle.first?.ring.fireDate == Fixtures.date(2026, 11, 2, 6, 50))
        #expect(plan.state.occurrences.first?.gentle?.fireDate == Fixtures.date(2026, 11, 2, 6, 50))
        #expect(requests(plan.operations).filter { $0.style == .standard }.count == 15)
        // Ringing early never makes the occurrence "active".
        #expect(planner.activeOccurrence(in: plan.state, now: Fixtures.date(2026, 11, 2, 6, 51)) == nil)
    }

    @Test func gentleRingIsFoundAndCancelledWithItsOccurrence() {
        let plan = planner.resync(ChainState(specs: [spec(gentle: 10)]), existing: [], now: monday0600)
        let gentleID = plan.state.occurrences[0].gentle!.id
        #expect(plan.state.occurrence(owning: gentleID)?.id == plan.state.occurrences[0].id)
        let (_, operations) = planner.complete(plan.state.occurrences[0], state: plan.state,
                                               existing: snapshot(plan.operations), now: Fixtures.date(2026, 11, 2, 6, 55))
        #expect(operations.contains(.cancel(gentleID)))
    }

    @Test func noGentleRingWhenItsTimeHasPassed() {
        let plan = planner.resync(ChainState(specs: [spec(gentle: 10)]), existing: [], now: Fixtures.date(2026, 11, 2, 6, 55))
        #expect(plan.state.occurrences.first?.gentle == nil)
        #expect(requests(plan.operations).allSatisfy { $0.style == .standard })
    }

    @Test func editingTheAlarmRearmsItsChain() {
        let first = planner.resync(ChainState(specs: [spec(revision: 1)]), existing: [], now: monday0600)
        var state = first.state
        state.specs = [spec(gentle: 10, revision: 2)]
        let second = planner.resync(state, existing: snapshot(first.operations), now: monday0600)
        let oldRings = Set(first.state.occurrences[0].rings.map(\.id))
        #expect(cancelled(second.operations).intersection(oldRings).count == 15)
        #expect(second.state.occurrences.count == 1)
        #expect(second.state.occurrences[0].specRevision == 2)
        #expect(second.state.occurrences[0].gentle != nil)
    }

    @Test func wakeUpCheckIsAShortChainThatBecomesActive() {
        let alarm = spec()
        let base = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)
        let wake = base.state.occurrences[0]
        let finished = Fixtures.date(2026, 11, 2, 7, 4)
        let (done, _) = planner.complete(wake, state: base.state, existing: [], now: finished)
        let fire = finished.addingTimeInterval(ChainPlanner.checkDelay)
        let (state, check, operations) = planner.armCheck(after: wake, spec: alarm, at: fire, state: done)

        #expect(check.isCheck && check.isOneOff)
        #expect(check.checkOf == wake.id)
        let armed = requests(operations)
        #expect(armed.count == 1 + ChainPlanner.checkRingCount)
        #expect(armed.allSatisfy { $0.style == .check })
        #expect(armed.first?.ring.fireDate == fire)

        #expect(planner.activeOccurrence(in: state, now: fire.addingTimeInterval(-30)) == nil)
        #expect(planner.activeOccurrence(in: state, now: fire.addingTimeInterval(5))?.id == check.id)

        // A resync keeps it, and deferral re-arms rings in the check style.
        let resynced = planner.resync(state, existing: snapshot(operations), now: fire.addingTimeInterval(-60))
        #expect(resynced.state.occurrence(check.id) != nil)
        let (_, deferral) = planner.deferChain(of: check.id, state: resynced.state, now: fire.addingTimeInterval(70))
        #expect(!requests(deferral).isEmpty)
        #expect(requests(deferral).allSatisfy { $0.style == .check })
    }

    @Test func cancellingACheckRemovesEverythingItArmed() {
        let alarm = spec()
        let wake = Occurrence(alarmID: alarm.id, fireDate: Fixtures.date(2026, 11, 2, 7, 0), kind: .wake,
                              chainLength: 15, primaryID: alarm.id)
        let (state, check, operations) = planner.armCheck(after: wake, spec: alarm, at: Fixtures.date(2026, 11, 2, 7, 10),
                                                          state: ChainState(specs: [alarm]))
        let (after, cancels) = planner.cancelOccurrence(check.id, state: state, existing: snapshot(operations))
        #expect(after.occurrence(check.id) == nil)
        #expect(cancels.count == 1 + ChainPlanner.checkRingCount)
    }
}
