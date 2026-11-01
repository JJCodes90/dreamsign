import Foundation
import Observation

/// Owns the alarm chain. Applies `ChainPlanner` decisions to AlarmKit, persists state, and
/// answers "is someone waking up right now?". Shared by the app and the App Intents, which
/// run in the same process. Every mutation is serialized.
@MainActor
@Observable
final class AlarmCoordinator {
    static let shared = AlarmCoordinator()

    private(set) var authorization: AlarmAuthorization
    private(set) var state: ChainState
    /// Our alarms that are ringing right now (foreground only — fed by `alarmUpdates`).
    private(set) var alertingIDs: Set<UUID> = []
    /// One-shot alarms that already fired; the app switches them off in SwiftData.
    private(set) var firedOneShots: [UUID] = []
    private(set) var lastError: String?

    var chainWasTruncated: Bool {
        guard let at = state.truncatedAt else { return false }
        return Date.now.timeIntervalSince(at) < 24 * 3600
    }

    var armedRingCount: Int {
        state.occurrences.filter { !$0.isCompleted }.reduce(0) { $0 + $1.pendingRings(after: .now).count }
    }

    @ObservationIgnored private let client = AlarmKitClient()
    @ObservationIgnored private let store = ChainStore()
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var observing = false

    private var planner: ChainPlanner { ChainPlanner(calendar: .autoupdatingCurrent) }

    private init() {
        state = store.load()
        authorization = client.authorization
    }

    // MARK: Authorization & observation

    @discardableResult
    func requestAuthorization() async -> AlarmAuthorization {
        authorization = await client.requestAuthorization()
        if authorization == .authorized { await resync() }
        return authorization
    }

    func startObserving() {
        guard !observing else { return }
        observing = true
        let client = client
        Task { [weak self] in
            for await state in client.authorizationUpdates() {
                guard let self else { return }
                let updated = AlarmAuthorization(state)
                if updated != self.authorization {
                    self.authorization = updated
                    if updated == .authorized { await self.resync() }
                }
            }
        }
        Task { [weak self] in
            for await alarms in client.alarmUpdates() {
                guard let self else { return }
                self.alertingIDs = Set(alarms.filter { $0.state == .alerting }.map(\.id))
            }
        }
    }

    // MARK: Sync

    func update(specs: [AlarmSpec]) async {
        await serialized {
            self.state.specs = specs
            await self.performResync()
        }
    }

    func resync() async {
        await serialized { await self.performResync() }
    }

    /// Marks one-shot alarms as handled once the app has switched them off.
    func acknowledgeFiredOneShots(_ ids: [UUID]) {
        firedOneShots.removeAll { ids.contains($0) }
    }

    // MARK: Wake-up lifecycle

    func activeOccurrence(now: Date = .now) -> Occurrence? {
        planner.activeOccurrence(in: state, now: now)
    }

    /// Stop / Wake Up tapped on the system alert.
    func ringInteraction(alarmKitID: UUID, openApp: Bool) async {
        await serialized {
            let result = self.planner.interaction(with: alarmKitID, openApp: openApp, state: self.state,
                                                  existing: self.client.snapshot(), now: .now)
            self.state = result.state
            let applied = await self.client.apply(result.operations)
            self.absorb(applied)
            self.save()
            await self.performResync()
        }
    }

    /// The wake flow is on screen: quiet anything ringing and push the chain out.
    func beginWake(_ occurrence: Occurrence) async {
        await serialized {
            if self.state.occurrence(occurrence.id) == nil { self.state.occurrences.append(occurrence) }
            let alerting = Set(self.client.snapshot().filter(\.isAlerting).map(\.id))
            let ringing = occurrence.allAlarmIDs.filter(alerting.contains)
            _ = await self.client.apply(ringing.map { .stop($0) })
            await self.performDefer(occurrence.id)
        }
    }

    /// Someone is interacting: keep the chain at arm's length (throttled by the planner).
    func noteActivity(_ occurrenceID: String) async {
        await serialized { await self.performDefer(occurrenceID) }
    }

    /// All enforced challenges are done — end the chain.
    func completeWake(_ occurrence: Occurrence) async {
        await serialized {
            let (state, operations) = self.planner.complete(occurrence, state: self.state,
                                                            existing: self.client.snapshot(), now: .now)
            self.state = state
            _ = await self.client.apply(operations)
            self.save()
            await self.performResync()
        }
    }

    // MARK: One-offs

    /// Fires `spec` once at `date` (tests, "going to bed now").
    @discardableResult
    func armOneOff(spec: AlarmSpec, at date: Date, isTest: Bool) async -> Occurrence? {
        var armed: Occurrence?
        await serialized {
            if self.authorization != .authorized {
                self.authorization = await self.client.requestAuthorization()
            }
            let (state, occurrence, operations) = self.planner.armOneOff(spec: spec, at: date, isTest: isTest, state: self.state)
            self.state = state
            let applied = await self.client.apply(operations)
            self.absorb(applied)
            self.save()
            armed = applied.failedSchedules.contains(occurrence.primaryID ?? UUID()) ? nil : occurrence
        }
        return armed
    }

    func cancelOneOffs(for alarmID: UUID) async {
        await serialized {
            let (state, operations) = self.planner.cancelOneOffs(for: alarmID, state: self.state, now: .now)
            self.state = state
            _ = await self.client.apply(operations)
            self.save()
        }
    }

    func upcomingOneOff(for alarmID: UUID) -> Occurrence? {
        state.occurrences.first { $0.alarmID == alarmID && $0.isOneOff && !$0.isTest && !$0.isCompleted && $0.fireDate > .now }
    }

    // MARK: Internals

    private func performResync() async {
        let plan = planner.resync(state, existing: client.snapshot(), now: .now)
        state = plan.state
        let applied = await client.apply(plan.operations)
        absorb(applied)
        if !plan.firedOneShots.isEmpty {
            firedOneShots = Array(Set(firedOneShots).union(plan.firedOneShots))
        }
        authorization = client.authorization
        save()
    }

    private func performDefer(_ occurrenceID: String) async {
        let spec = self.state.occurrence(occurrenceID).flatMap { self.state.spec($0.alarmID) }
        let (deferred, operations) = planner.deferChain(of: occurrenceID, state: self.state, now: .now, spec: spec)
        guard !operations.isEmpty else { return }
        self.state = deferred
        let applied = await client.apply(operations)
        absorb(applied)
        save()
    }

    /// Reflects AlarmKit failures back into state so nothing is believed armed that isn't.
    private func absorb(_ result: AlarmKitClient.ApplyResult) {
        if let error = result.lastError { lastError = error }
        guard !result.failedSchedules.isEmpty else { return }
        for index in state.occurrences.indices {
            state.occurrences[index].rings.removeAll { result.failedSchedules.contains($0.id) }
        }
        for id in result.failedSchedules {
            state.primaries[id.uuidString] = nil
        }
        if result.limitReached { state.truncatedAt = .now }
    }

    private func save() {
        store.save(state)
    }

    /// Runs `work` after everything queued before it, so awaits never interleave mutations.
    private func serialized(_ work: @escaping @MainActor () async -> Void) async {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        tail = task
        await task.value
    }
}

/// `ChainState` persisted as JSON in UserDefaults.
struct ChainStore {
    private let key = "dreamsign.chain-state.v1"

    func load() -> ChainState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(ChainState.self, from: data)
        else { return ChainState() }
        return state
    }

    func save(_ state: ChainState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
