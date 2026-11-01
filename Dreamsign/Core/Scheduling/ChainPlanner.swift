import Foundation

/// Pure planning for the alarm chain. Given the persisted state, what AlarmKit holds and
/// the current time, it returns the next state plus the AlarmKit operations to get there.
/// No side effects, so every rule is unit-testable.
struct ChainPlanner {
    /// Time between rings in a chain.
    static let ringInterval: TimeInterval = 60
    /// How long an occurrence stays "active" after its last ring.
    static let activeGrace: TimeInterval = 180
    /// How far rings are pushed out while someone is working through challenges.
    static let deferral: TimeInterval = 120
    /// Rings re-armed on each deferral.
    static let deferredRingCount = 10
    /// A pending wake (Wake Up tapped) is honored for this long.
    static let pendingWakeLifetime: TimeInterval = 30 * 60
    /// Completed occurrences are remembered this long, so an inferred wake never repeats.
    static let completedRetention: TimeInterval = 48 * 3600

    var calendar: Calendar
    /// AlarmKit has no fixed cap but throws `maximumLimitReached` under pressure, so we budget.
    var maxArmedRings = 40
    var makeID: () -> UUID = { UUID() }

    struct Plan {
        var state: ChainState
        var operations: [ChainOperation] = []
        var truncated = false
        /// One-shot alarms that already fired and should be switched off in the UI.
        var firedOneShots: [UUID] = []
    }

    // MARK: - Resync

    func resync(_ input: ChainState, existing: [AlarmSnapshot], now: Date) -> Plan {
        var plan = Plan(state: input)
        let existingIDs = Set(existing.map(\.id))
        let specIDs = Set(input.specs.map { $0.id.uuidString })

        // 1. Primaries: one repeating (or one-shot) relative alarm per enabled spec.
        for spec in input.specs {
            let key = spec.id.uuidString
            let present = existingIDs.contains(spec.id)
            guard spec.isEnabled else {
                if present { plan.operations.append(.cancel(spec.id)) }
                plan.state.primaries[key] = nil
                continue
            }
            if let record = input.primaries[key], record.fingerprint == spec.fingerprint {
                guard !present else { continue }
                if spec.weekdays.isOneShot, let fire = record.expectedFire, fire <= now {
                    plan.firedOneShots.append(spec.id)   // it rang and was stopped
                    continue
                }
                // Lost (e.g. reinstall or permission reset): schedule again.
            } else if present {
                plan.operations.append(.cancel(spec.id))
            }
            plan.operations.append(.schedulePrimary(spec))
            plan.state.primaries[key] = PrimaryRecord(
                fingerprint: spec.fingerprint,
                scheduledAt: now,
                expectedFire: OccurrenceMath.next(spec.time, weekdays: spec.weekdays, after: now, calendar: calendar))
        }
        for key in input.primaries.keys where !specIDs.contains(key) {
            if let id = UUID(uuidString: key), existingIDs.contains(id) { plan.operations.append(.cancel(id)) }
            plan.state.primaries[key] = nil
        }

        // 2. Occurrences: drop stale future ones, keep active and recently completed ones.
        var kept: [Occurrence] = []
        for occurrence in input.occurrences {
            if occurrence.isCompleted {
                if now.timeIntervalSince(occurrence.fireDate) < Self.completedRetention { kept.append(occurrence) }
            } else if occurrence.fireDate > now {
                if isStillWanted(occurrence, in: input, now: now) {
                    kept.append(occurrence)
                } else {
                    plan.operations += occurrence.ownedAlarmIDs.map { .cancel($0) }
                }
            } else if now <= occurrence.windowEnd {
                kept.append(occurrence)
            }
        }

        // 3. Arm the next occurrence of each enabled spec, soonest first, within budget.
        var budget = maxArmedRings - kept
            .filter { !$0.isCompleted }
            .reduce(0) { $0 + $1.pendingRings(after: now).count }

        let upcoming = input.specs
            .filter { $0.isEnabled && !plan.firedOneShots.contains($0.id) }
            .compactMap { spec -> (AlarmSpec, Date)? in
                guard let next = nextFire(of: spec, primaries: plan.state.primaries, after: now) else { return nil }
                return (spec, next)
            }
            .sorted { $0.1 < $1.1 }

        for (spec, fireDate) in upcoming {
            let key = Occurrence.key(alarmID: spec.id, fireDate: fireDate)
            if let index = kept.firstIndex(where: { $0.id == key }) {
                // Top up a chain that an earlier budget cut short.
                let missing = spec.chainLength - kept[index].rings.count
                guard missing > 0 else { continue }
                let count = min(missing, max(budget, 0))
                if count < missing { plan.truncated = true }
                let start = kept[index].rings.count + 1
                let rings = makeRings(after: fireDate, indices: start..<(start + count))
                kept[index].rings += rings
                plan.operations += ringOperations(rings, startIndex: start, occurrence: kept[index], spec: spec)
                budget -= count
                continue
            }
            let count = min(spec.chainLength, max(budget, 0))
            if count < spec.chainLength { plan.truncated = true }
            let rings = makeRings(after: fireDate, indices: 1..<(1 + count))
            let occurrence = Occurrence(alarmID: spec.id, fireDate: fireDate, kind: spec.kind,
                                        chainLength: spec.chainLength, rings: rings, primaryID: spec.id)
            kept.append(occurrence)
            plan.operations += ringOperations(rings, startIndex: 1, occurrence: occurrence, spec: spec)
            budget -= count
        }
        plan.state.occurrences = kept.sorted { $0.fireDate < $1.fireDate }

        // 4. Orphans: anything AlarmKit holds that we no longer expect.
        var expected = Set(input.specs.filter(\.isEnabled).map(\.id))
        for occurrence in kept where !occurrence.isCompleted {
            expected.formUnion(occurrence.allAlarmIDs)
        }
        let alreadyCancelled = Set(plan.operations.compactMap { op -> UUID? in
            if case .cancel(let id) = op { return id } else { return nil }
        })
        for snapshot in existing where !expected.contains(snapshot.id) && !alreadyCancelled.contains(snapshot.id) {
            plan.operations.append(.cancel(snapshot.id))
        }

        // 5. Housekeeping.
        if let pending = plan.state.pendingWake, now.timeIntervalSince(pending.requestedAt) > Self.pendingWakeLifetime {
            plan.state.pendingWake = nil
        }
        if plan.truncated { plan.state.truncatedAt = now }
        return plan
    }

    private func isStillWanted(_ occurrence: Occurrence, in state: ChainState, now: Date) -> Bool {
        if occurrence.isOneOff { return true }
        guard let spec = state.spec(occurrence.alarmID), spec.isEnabled,
              spec.chainLength == occurrence.chainLength,
              let next = nextFire(of: spec, primaries: state.primaries, after: now)
        else { return false }
        return next == occurrence.fireDate
    }

    /// Next fire date of a spec's primary. A one-shot only ever fires at the date it was
    /// scheduled for, never "tomorrow at the same time".
    func nextFire(of spec: AlarmSpec, primaries: [String: PrimaryRecord], after now: Date) -> Date? {
        if spec.weekdays.isOneShot {
            guard let record = primaries[spec.id.uuidString], record.fingerprint == spec.fingerprint,
                  let fire = record.expectedFire, fire > now
            else { return nil }
            return fire
        }
        return OccurrenceMath.next(spec.time, weekdays: spec.weekdays, after: now, calendar: calendar)
    }

    /// Most recent fire date at or before `now`, with the same one-shot rule.
    func previousFire(of spec: AlarmSpec, primaries: [String: PrimaryRecord], atOrBefore now: Date) -> Date? {
        if spec.weekdays.isOneShot {
            guard let record = primaries[spec.id.uuidString], record.fingerprint == spec.fingerprint,
                  let fire = record.expectedFire, fire <= now
            else { return nil }
            return fire
        }
        return OccurrenceMath.previous(spec.time, weekdays: spec.weekdays, atOrBefore: now, calendar: calendar)
    }

    // MARK: - Active occurrence

    /// The occurrence the wake flow should handle right now, if any.
    func activeOccurrence(in state: ChainState, now: Date) -> Occurrence? {
        if let pending = state.pendingWake,
           now.timeIntervalSince(pending.requestedAt) <= Self.pendingWakeLifetime,
           let occurrence = state.occurrence(pending.occurrenceID), !occurrence.isCompleted {
            return occurrence
        }
        if let stored = state.occurrences
            .filter({ !$0.isCompleted && $0.fireDate <= now && now <= $0.windowEnd })
            .max(by: { $0.fireDate < $1.fireDate }) {
            return stored
        }
        return inferredOccurrences(in: state, now: now).max { $0.fireDate < $1.fireDate }
    }

    /// Occurrences that must have fired from the schedule alone, even if no intent ever ran.
    func inferredOccurrences(in state: ChainState, now: Date) -> [Occurrence] {
        state.specs.filter(\.isEnabled).compactMap { spec in
            guard let fireDate = previousFire(of: spec, primaries: state.primaries, atOrBefore: now),
                  spec.modifiedAt < fireDate
            else { return nil }
            let occurrence = Occurrence(alarmID: spec.id, fireDate: fireDate, kind: spec.kind,
                                        chainLength: spec.chainLength, primaryID: spec.id)
            guard now <= occurrence.windowEnd, state.occurrence(occurrence.id) == nil else { return nil }
            return occurrence
        }
    }

    // MARK: - Ring interaction (Stop / Wake Up tapped on the system alert)

    struct Interaction {
        var state: ChainState
        var operations: [ChainOperation]
        var occurrence: Occurrence?
    }

    /// Quiets sibling rings of the same occurrence so they never stack, and records a pending
    /// wake when the person asked to open the app. The chain itself keeps going.
    func interaction(with alarmKitID: UUID, openApp: Bool, state input: ChainState,
                     existing: [AlarmSnapshot], now: Date) -> Interaction {
        var state = input
        var occurrence = state.occurrence(owning: alarmKitID)
        if occurrence == nil, state.spec(alarmKitID) != nil {
            // The repeating primary rang: find (or infer) the occurrence it started.
            occurrence = state.occurrences
                .filter { $0.alarmID == alarmKitID && !$0.isCompleted && !$0.isOneOff && $0.fireDate <= now && now <= $0.windowEnd }
                .max { $0.fireDate < $1.fireDate }
                ?? inferredOccurrences(in: state, now: now).first { $0.alarmID == alarmKitID }
        }
        guard var current = occurrence else { return Interaction(state: state, operations: [], occurrence: nil) }

        var operations: [ChainOperation] = []
        if state.occurrence(current.id) == nil {
            // Fallback when the chain was never armed: arm it now, from this moment.
            if let spec = state.spec(current.alarmID) {
                let count = min(current.chainLength, Self.deferredRingCount)
                current.rings = makeRings(after: now, indices: 1..<(1 + count))
                operations += ringOperations(current.rings, startIndex: 1, occurrence: current, spec: spec)
            }
            state.occurrences.append(current)
        }

        let alerting = Set(existing.filter(\.isAlerting).map(\.id))
        for id in current.allAlarmIDs where id != alarmKitID && alerting.contains(id) {
            operations.append(.stop(id))
        }
        if openApp {
            state.pendingWake = PendingWake(occurrenceID: current.id, requestedAt: now)
        }
        return Interaction(state: state, operations: operations, occurrence: current)
    }

    // MARK: - Wake flow

    /// Pushes pending rings out while someone is actively doing challenges. Returns no
    /// operations when the chain was already pushed recently (natural throttle).
    func deferChain(of occurrenceID: String, state input: ChainState, now: Date,
                    spec fallbackSpec: AlarmSpec? = nil) -> (ChainState, [ChainOperation]) {
        var state = input
        guard let index = state.occurrences.firstIndex(where: { $0.id == occurrenceID }),
              !state.occurrences[index].isCompleted
        else { return (state, []) }

        let occurrence = state.occurrences[index]
        let pending = occurrence.pendingRings(after: now)
        if let first = pending.map(\.fireDate).min(), first.timeIntervalSince(now) > Self.deferral - 30 {
            return (state, [])
        }
        guard let spec = state.spec(occurrence.alarmID) ?? fallbackSpec else { return (state, []) }

        var operations: [ChainOperation] = pending.map { .cancel($0.id) }
        let count = min(max(occurrence.chainLength, 1), Self.deferredRingCount)
        let start = now.addingTimeInterval(Self.deferral - Self.ringInterval)
        let rings = makeRings(after: start, indices: 1..<(1 + count))
        state.occurrences[index].rings = occurrence.rings.filter { $0.fireDate <= now } + rings
        operations += ringOperations(rings, startIndex: 1, occurrence: state.occurrences[index], spec: spec)
        return (state, operations)
    }

    /// Ends the chain: cancels what's pending, stops what's ringing, remembers completion.
    func complete(_ occurrence: Occurrence, state input: ChainState, existing: [AlarmSnapshot],
                  now: Date) -> (ChainState, [ChainOperation]) {
        var state = input
        let current = state.occurrence(occurrence.id) ?? occurrence
        let alerting = Set(existing.filter(\.isAlerting).map(\.id))
        let present = Set(existing.map(\.id))
        let pending = Set(current.pendingRings(after: now).map(\.id))
        var operations: [ChainOperation] = []
        for id in current.allAlarmIDs {
            if alerting.contains(id) {
                operations.append(.stop(id))
            } else if current.ownedAlarmIDs.contains(id), pending.contains(id) || present.contains(id) {
                operations.append(.cancel(id))
            }
        }
        var done = current
        done.completedAt = now
        done.rings = current.rings.filter { $0.fireDate <= now }
        if let index = state.occurrences.firstIndex(where: { $0.id == current.id }) {
            state.occurrences[index] = done
        } else {
            state.occurrences.append(done)
        }
        if state.pendingWake?.occurrenceID == current.id { state.pendingWake = nil }
        return (state, operations)
    }

    // MARK: - One-offs (tests, "going to bed now")

    func armOneOff(spec: AlarmSpec, at fireDate: Date, isTest: Bool, state input: ChainState) -> (ChainState, Occurrence, [ChainOperation]) {
        var state = input
        let primary = ArmedRing(id: makeID(), fireDate: fireDate)
        let count = isTest ? min(spec.chainLength, 3) : spec.chainLength
        let rings = makeRings(after: fireDate, indices: 1..<(1 + count))
        let occurrence = Occurrence(alarmID: spec.id, fireDate: fireDate, kind: spec.kind, chainLength: count,
                                    rings: rings, primaryID: primary.id, isOneOff: true, isTest: isTest)
        state.occurrences.removeAll { $0.id == occurrence.id }
        state.occurrences.append(occurrence)
        let first = RingRequest(ring: primary, alarmID: spec.id, occurrenceID: occurrence.id, kind: spec.kind,
                                label: spec.label, soundID: spec.soundID, index: 0)
        let operations = [ChainOperation.scheduleRing(first)]
            + ringOperations(rings, startIndex: 1, occurrence: occurrence, spec: spec)
        return (state, occurrence, operations)
    }

    func cancelOneOffs(for alarmID: UUID, state input: ChainState, now: Date) -> (ChainState, [ChainOperation]) {
        var state = input
        let targets = state.occurrences.filter { $0.alarmID == alarmID && $0.isOneOff && !$0.isCompleted && $0.fireDate > now }
        state.occurrences.removeAll { target in targets.contains { $0.id == target.id } }
        return (state, targets.flatMap { $0.ownedAlarmIDs.map { ChainOperation.cancel($0) } })
    }

    // MARK: - Helpers

    private func makeRings(after fireDate: Date, indices: Range<Int>) -> [ArmedRing] {
        indices.map { ArmedRing(id: makeID(), fireDate: fireDate.addingTimeInterval(Double($0) * Self.ringInterval)) }
    }

    private func ringOperations(_ rings: [ArmedRing], startIndex: Int, occurrence: Occurrence, spec: AlarmSpec) -> [ChainOperation] {
        rings.enumerated().map { offset, ring in
            .scheduleRing(RingRequest(ring: ring, alarmID: spec.id, occurrenceID: occurrence.id, kind: spec.kind,
                                      label: spec.label, soundID: spec.soundID, index: startIndex + offset))
        }
    }
}
