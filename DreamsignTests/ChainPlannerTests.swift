import Foundation
import Testing
@testable import Dreamsign

@Suite("Alarm chain planner")
struct ChainPlannerTests {
    let planner = ChainPlanner(calendar: Fixtures.calendar)
    let monday0600 = Fixtures.date(2026, 11, 2, 6, 0)

    func spec(_ hour: Int = 7, _ minute: Int = 0, days: WeekdaySet = .weekdays, chain: Int = 15,
              modified: Date = Fixtures.date(2026, 10, 1)) -> AlarmSpec {
        AlarmSpec(id: UUID(), time: AlarmTime(hour: hour, minute: minute), weekdays: days, label: "Wake",
                  soundID: "system", chainLength: chain, kind: .wake, isEnabled: true, revision: 1, modifiedAt: modified)
    }

    /// Simulates AlarmKit applying the operations.
    func apply(_ operations: [ChainOperation], to snapshot: [AlarmSnapshot]) -> [AlarmSnapshot] {
        var ids = snapshot
        for operation in operations {
            switch operation {
            case .schedulePrimary(let spec): ids.append(AlarmSnapshot(id: spec.id, isAlerting: false))
            case .scheduleRing(let request): ids.append(AlarmSnapshot(id: request.ring.id, isAlerting: false))
            case .cancel(let id), .stop(let id): ids.removeAll { $0.id == id }
            }
        }
        return ids
    }

    func rings(_ operations: [ChainOperation]) -> [RingRequest] {
        operations.compactMap { operation -> RingRequest? in
            if case .scheduleRing(let request) = operation { return request }
            return nil
        }
    }

    func cancelCount(_ operations: [ChainOperation]) -> Int {
        operations.filter { operation in
            if case .cancel = operation { return true }
            return false
        }.count
    }

    @Test func newAlarmSchedulesPrimaryAndArmsChain() {
        let alarm = spec()
        let plan = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)

        #expect(plan.operations.first == .schedulePrimary(alarm))
        let armed = rings(plan.operations)
        #expect(armed.count == 15)
        #expect(armed.first?.ring.fireDate == Fixtures.date(2026, 11, 2, 7, 1))
        #expect(armed.last?.ring.fireDate == Fixtures.date(2026, 11, 2, 7, 15))
        #expect(armed.map(\.index) == Array(1...15))
        #expect(plan.state.occurrences.count == 1)
        #expect(plan.state.occurrences[0].fireDate == Fixtures.date(2026, 11, 2, 7, 0))
        #expect(plan.state.primaries[alarm.id.uuidString]?.fingerprint == alarm.fingerprint)
        #expect(!plan.truncated)
    }

    @Test func resyncIsIdempotent() {
        let alarm = spec()
        let first = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)
        let snapshot = apply(first.operations, to: [])
        let second = planner.resync(first.state, existing: snapshot, now: monday0600.addingTimeInterval(60))
        #expect(second.operations.isEmpty)
        #expect(second.state.occurrences == first.state.occurrences)
    }

    @Test func disablingCancelsPrimaryAndChain() {
        var alarm = spec()
        let first = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)
        let snapshot = apply(first.operations, to: [])
        alarm.isEnabled = false
        var state = first.state
        state.specs = [alarm]
        let second = planner.resync(state, existing: snapshot, now: monday0600)
        #expect(apply(second.operations, to: snapshot).isEmpty)
        #expect(second.state.occurrences.isEmpty)
        #expect(second.state.primaries.isEmpty)
    }

    @Test func editingTimeReplacesPrimaryAndChain() {
        var alarm = spec()
        let first = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)
        let snapshot = apply(first.operations, to: [])
        alarm.time = AlarmTime(hour: 7, minute: 30)
        alarm.revision += 1
        var state = first.state
        state.specs = [alarm]
        let second = planner.resync(state, existing: snapshot, now: monday0600)
        #expect(second.operations.contains(.cancel(alarm.id)))
        #expect(second.operations.contains(.schedulePrimary(alarm)))
        let after = apply(second.operations, to: snapshot)
        #expect(after.count == 16)
        #expect(second.state.occurrences.map(\.fireDate) == [Fixtures.date(2026, 11, 2, 7, 30)])
    }

    @Test func ringBudgetFavoursTheSoonestAlarm() {
        var budgeted = planner
        budgeted.maxArmedRings = 40
        let early = spec(6, 30), mid = spec(7, 0), late = spec(8, 0)
        let plan = budgeted.resync(ChainState(specs: [late, early, mid]), existing: [], now: monday0600)
        let byAlarm = Dictionary(grouping: rings(plan.operations), by: \.alarmID)
        #expect(byAlarm[early.id]?.count == 15)
        #expect(byAlarm[mid.id]?.count == 15)
        #expect(byAlarm[late.id]?.count == 10)
        #expect(plan.truncated)
        #expect(plan.state.truncatedAt == monday0600)
    }

    @Test func truncatedChainIsToppedUpLater() {
        var budgeted = planner
        budgeted.maxArmedRings = 20
        let early = spec(6, 30), late = spec(8, 0)
        let first = budgeted.resync(ChainState(specs: [early, late]), existing: [], now: monday0600)
        var snapshot = apply(first.operations, to: [])
        // The 06:30 alarm finishes; its rings are gone and the occurrence completes.
        let occurrence = first.state.occurrences.first { $0.alarmID == early.id }!
        let (completed, completeOps) = budgeted.complete(occurrence, state: first.state, existing: snapshot,
                                                         now: Fixtures.date(2026, 11, 2, 6, 32))
        snapshot = apply(completeOps, to: snapshot)
        let second = budgeted.resync(completed, existing: snapshot, now: Fixtures.date(2026, 11, 2, 6, 33))
        let topUp = rings(second.operations).filter { $0.alarmID == late.id }
        #expect(topUp.count == 10)
        #expect(topUp.first?.index == 6)
    }

    @Test func firedOneShotIsReportedAndNotRearmed() {
        let alarm = spec(days: [], chain: 5)
        let first = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)
        // 07:20: the one-shot rang, was stopped and deleted by the system; its rings have fired.
        let later = Fixtures.date(2026, 11, 2, 7, 20)
        let second = planner.resync(first.state, existing: [], now: later)
        #expect(second.firedOneShots == [alarm.id])
        #expect(rings(second.operations).isEmpty)
        #expect(!second.operations.contains(.schedulePrimary(alarm)))
    }

    @Test func lostPrimaryIsRescheduled() {
        let alarm = spec()
        let first = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)
        let snapshot = apply(first.operations, to: []).filter { $0.id != alarm.id }
        let second = planner.resync(first.state, existing: snapshot, now: monday0600)
        #expect(second.operations == [.schedulePrimary(alarm)])
    }

    @Test func orphansAreCancelled() {
        let stray = UUID()
        let plan = planner.resync(ChainState(), existing: [AlarmSnapshot(id: stray, isAlerting: false)], now: monday0600)
        #expect(plan.operations == [.cancel(stray)])
    }

    @Test func activeOccurrenceFromStoredChain() {
        let alarm = spec()
        let state = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600).state
        #expect(planner.activeOccurrence(in: state, now: Fixtures.date(2026, 11, 2, 6, 59)) == nil)
        #expect(planner.activeOccurrence(in: state, now: Fixtures.date(2026, 11, 2, 7, 0))?.alarmID == alarm.id)
        #expect(planner.activeOccurrence(in: state, now: Fixtures.date(2026, 11, 2, 7, 17))?.alarmID == alarm.id)
        #expect(planner.activeOccurrence(in: state, now: Fixtures.date(2026, 11, 2, 7, 19)) == nil)
    }

    @Test func activeOccurrenceIsInferredWhenNothingWasArmed() {
        let alarm = spec()
        let state = ChainState(specs: [alarm])          // app never ran since the alarm was saved
        let active = planner.activeOccurrence(in: state, now: Fixtures.date(2026, 11, 2, 7, 4))
        #expect(active?.fireDate == Fixtures.date(2026, 11, 2, 7, 0))
        #expect(active?.rings.isEmpty == true)
    }

    @Test func alarmsEditedAfterFiringAreNotInferred() {
        let alarm = spec(modified: Fixtures.date(2026, 11, 2, 7, 2))
        #expect(planner.activeOccurrence(in: ChainState(specs: [alarm]), now: Fixtures.date(2026, 11, 2, 7, 4)) == nil)
    }

    @Test func stopQuietsSiblingRingsButKeepsTheChain() {
        let alarm = spec()
        let first = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)
        var snapshot = apply(first.operations, to: [])
        let occurrence = first.state.occurrences[0]
        let ring1 = occurrence.rings[0].id
        // 07:01: the primary is still ringing when ring 1 starts, and Stop is tapped on ring 1.
        snapshot = snapshot.map { $0.id == alarm.id || $0.id == ring1 ? AlarmSnapshot(id: $0.id, isAlerting: true) : $0 }
        let result = planner.interaction(with: ring1, openApp: false, state: first.state, existing: snapshot,
                                         now: Fixtures.date(2026, 11, 2, 7, 1, 5))
        #expect(result.operations == [.stop(alarm.id)])
        #expect(result.occurrence?.id == occurrence.id)
        #expect(result.state.pendingWake == nil)
        #expect(result.state.occurrences[0].rings.count == 15)
    }

    @Test func wakeUpRecordsAPendingWake() {
        let alarm = spec()
        let first = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)
        let now = Fixtures.date(2026, 11, 2, 7, 0, 20)
        let result = planner.interaction(with: alarm.id, openApp: true, state: first.state,
                                         existing: [AlarmSnapshot(id: alarm.id, isAlerting: true)], now: now)
        #expect(result.state.pendingWake?.occurrenceID == first.state.occurrences[0].id)
        #expect(planner.activeOccurrence(in: result.state, now: now)?.id == first.state.occurrences[0].id)
    }

    @Test func unarmedOccurrenceGetsAChainOnFirstInteraction() {
        let alarm = spec()
        let now = Fixtures.date(2026, 11, 2, 7, 0, 30)
        let result = planner.interaction(with: alarm.id, openApp: false, state: ChainState(specs: [alarm]),
                                         existing: [AlarmSnapshot(id: alarm.id, isAlerting: true)], now: now)
        let armed = rings(result.operations)
        #expect(armed.count == ChainPlanner.deferredRingCount)
        #expect(armed.first?.ring.fireDate == now.addingTimeInterval(60))
        #expect(result.state.occurrences.count == 1)
    }

    @Test func deferringPushesRingsOutAndThrottles() {
        let alarm = spec()
        let first = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)
        let occurrenceID = first.state.occurrences[0].id
        let now = Fixtures.date(2026, 11, 2, 7, 0, 40)

        let (deferred, operations) = planner.deferChain(of: occurrenceID, state: first.state, now: now)
        #expect(cancelCount(operations) == 15)
        let armed = rings(operations)
        #expect(armed.count == ChainPlanner.deferredRingCount)
        #expect(armed.first?.ring.fireDate == now.addingTimeInterval(ChainPlanner.deferral))

        let (_, again) = planner.deferChain(of: occurrenceID, state: deferred, now: now.addingTimeInterval(10))
        #expect(again.isEmpty)
        let (_, later) = planner.deferChain(of: occurrenceID, state: deferred, now: now.addingTimeInterval(35))
        #expect(!later.isEmpty)
    }

    @Test func completingEndsTheChainAndArmsTomorrow() {
        let alarm = spec()
        let first = planner.resync(ChainState(specs: [alarm]), existing: [], now: monday0600)
        let now = Fixtures.date(2026, 11, 2, 7, 3, 30)
        let occurrence = first.state.occurrences[0]
        // Rings 1–3 already fired and were stopped, so the system deleted them; the primary still rings.
        let fired = Set(occurrence.rings.prefix(3).map(\.id))
        var snapshot = apply(first.operations, to: []).filter { !fired.contains($0.id) }
        snapshot = snapshot.map { $0.id == alarm.id ? AlarmSnapshot(id: $0.id, isAlerting: true) : $0 }

        let (done, operations) = planner.complete(occurrence, state: first.state, existing: snapshot, now: now)
        #expect(operations.contains(.stop(alarm.id)))
        #expect(cancelCount(operations) == 12)          // rings 4…15
        #expect(planner.activeOccurrence(in: done, now: now) == nil)

        snapshot = apply(operations, to: snapshot)
        let next = planner.resync(done, existing: snapshot + [AlarmSnapshot(id: alarm.id, isAlerting: false)], now: now)
        #expect(next.state.occurrences.contains { $0.fireDate == Fixtures.date(2026, 11, 3, 7, 0) && !$0.isCompleted })
        #expect(planner.activeOccurrence(in: next.state, now: now.addingTimeInterval(60)) == nil)
    }

    @Test func oneOffTestAlarmSurvivesResync() {
        let alarm = spec()
        let fire = monday0600.addingTimeInterval(10)
        let (state, occurrence, operations) = planner.armOneOff(spec: alarm, at: fire, isTest: true, state: ChainState())
        let armed = rings(operations)
        #expect(armed.count == 4)                       // first ring + 3 follow-ups for tests
        #expect(armed.first?.index == 0)
        #expect(armed.first?.ring.fireDate == fire)
        let snapshot = apply(operations, to: [])
        let plan = planner.resync(state, existing: snapshot, now: monday0600)
        #expect(plan.operations.isEmpty)
        #expect(plan.state.occurrence(occurrence.id) != nil)
        #expect(planner.activeOccurrence(in: plan.state, now: fire.addingTimeInterval(5))?.id == occurrence.id)
    }
}
