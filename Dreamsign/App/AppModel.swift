import BackgroundTasks
import Foundation
import Observation
import SwiftData

/// App-level routing: which tab, and whether a wake-up is in progress.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable { case alarms, journal, insights, learn }

    nonisolated static let refreshTaskID = "com.jjcodes.dreamsign.resync"

    var tab: Tab = Showcase.tab ?? .alarms
    var wake: WakeSession?
    /// Set once the wake flow's enforced steps are done (MILD / back-to-sleep may still be showing).
    var wakeFinishedAt: Date?
    /// The armed wake-up check, shown on the finish screen.
    var pendingCheck: Occurrence?
    let coordinator = AlarmCoordinator.shared
    @ObservationIgnored private var checkSkipTask: Task<Void, Never>?

    /// Pushes the current alarms to the alarm layer and reconciles AlarmKit.
    func syncAlarms(_ context: ModelContext) async {
        await coordinator.update(specs: allAlarms(context).map(\.spec))
        if disableFiredOneShots(context) {
            await coordinator.update(specs: allAlarms(context).map(\.spec))
        }
        await BedtimeNudges.sync(allAlarms(context))
    }

    /// Shows the wake flow if an alarm is (or just was) ringing. A finished flow left on screen
    /// (e.g. WBTB's back-to-sleep at 3 AM) gives way to the next wake-up, or quietly expires.
    func presentWakeIfNeeded(_ context: ModelContext) {
        let active = coordinator.activeOccurrence()
        if let current = wake, let finished = wakeFinishedAt {
            if let active, active.id != current.id {
                startWake(active, context)
            } else if Date.now.timeIntervalSince(finished) > 20 * 60 {
                endWake()
            }
            return
        }
        guard wake == nil, let active else { return }
        startWake(active, context)
    }

    func endWake() {
        wake = nil
        wakeFinishedAt = nil
    }

    private func startWake(_ occurrence: Occurrence, _ context: ModelContext) {
        wakeFinishedAt = nil
        wake = WakeSession(occurrence: occurrence, alarm: alarm(occurrence.alarmID, context))
    }

    // MARK: Wake-up check

    /// Arms "Still up?" and, while the app stays open and in use, quietly calls it off: the
    /// person is plainly awake. Leaving the app keeps it armed.
    func armCheck(after occurrence: Occurrence) async {
        guard let check = await coordinator.armCheck(after: occurrence) else { return }
        pendingCheck = check
        checkSkipTask?.cancel()
        checkSkipTask = Task { [weak self] in
            let wait = check.fireDate.timeIntervalSinceNow - 20
            try? await Task.sleep(for: .seconds(max(wait, 0)))
            guard !Task.isCancelled, let self else { return }
            if TouchTracker.shared.touchedRecently(within: 120) {
                await self.coordinator.cancelCheck(check.id)
                if self.pendingCheck?.id == check.id { self.pendingCheck = nil }
            }
        }
    }

    /// The app went to the background: the check stays armed.
    func leftApp() {
        checkSkipTask?.cancel()
        checkSkipTask = nil
    }

    func becameActive(_ context: ModelContext) async {
        guard !Showcase.isActive else { return }
        await syncAlarms(context)
        presentWakeIfNeeded(context)
    }

    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date.now.addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Helpers

    func allAlarms(_ context: ModelContext) -> [WakeAlarm] {
        (try? context.fetch(FetchDescriptor<WakeAlarm>())) ?? []
    }

    func alarm(_ id: UUID, _ context: ModelContext) -> WakeAlarm? {
        var descriptor = FetchDescriptor<WakeAlarm>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The single WBTB plan, created on first use.
    func wbtbPlan(_ context: ModelContext) -> WakeAlarm {
        if let existing = allAlarms(context).first(where: { $0.kind == .wbtb }) { return existing }
        let plan = WakeAlarm(time: AlarmTime(hour: 4, minute: 0), weekdays: .everyDay, kind: .wbtb)
        plan.applyWBTB(bedtime: AlarmTime(hour: 23, minute: 0), offsetMinutes: 300, nights: .everyDay)
        context.insert(plan)
        try? context.save()
        return plan
    }

    /// One-shot alarms switch themselves off after they ring.
    @discardableResult
    private func disableFiredOneShots(_ context: ModelContext) -> Bool {
        let fired = coordinator.firedOneShots
        guard !fired.isEmpty else { return false }
        var changed = false
        for id in fired {
            if let alarm = alarm(id, context), alarm.isEnabled {
                alarm.isEnabled = false
                changed = true
            }
        }
        if changed { try? context.save() }
        coordinator.acknowledgeFiredOneShots(fired)
        return changed
    }
}

/// Everything the wake flow needs, captured when it starts.
struct WakeSession: Identifiable {
    enum Step: Hashable, Identifiable {
        case challenge(Challenge)
        /// Used when an alarm has no challenges: one tap to confirm.
        case confirm
        /// The wake-up check: tap dots in order.
        case stillUp
        case technique(WBTBTechnique)
        case backToSleep

        var id: String {
            switch self {
            case .challenge(let challenge): challenge.id.uuidString
            case .confirm: "confirm"
            case .stillUp: "still-up"
            case .technique(let technique): technique.rawValue
            case .backToSleep: "sleep"
            }
        }

        var isEnforced: Bool {
            switch self {
            case .challenge, .confirm, .stillUp: true
            case .technique, .backToSleep: false
            }
        }
    }

    let occurrence: Occurrence
    let kind: AlarmKind
    let label: String
    let steps: [Step]
    let mildMinutes: Int
    /// A non-repeating, non-test alarm — switched off once completed.
    let disablesAlarm: Bool
    /// Arm "Still up?" after the challenges.
    let armsCheck: Bool

    var id: String { occurrence.id }

    init(occurrence: Occurrence, alarm: WakeAlarm?) {
        self.occurrence = occurrence
        kind = occurrence.kind
        label = alarm?.displayLabel ?? String(localized: "Alarm")
        mildMinutes = alarm?.mildMinutes ?? 3
        disablesAlarm = (alarm?.weekdays.isOneShot ?? false) && !occurrence.isOneOff
        armsCheck = occurrence.kind == .wake && !occurrence.isCheck && (alarm?.wakeCheck ?? false)
        if occurrence.isCheck {
            steps = [.stillUp]
            return
        }
        switch occurrence.kind {
        case .wake:
            let challenges = alarm?.challenges ?? Challenge.defaults
            steps = challenges.isEmpty ? [.confirm] : challenges.map(Step.challenge)
        case .wbtb:
            var journal = Challenge(kind: .journal)
            journal.journalWords = alarm?.wbtbJournalWords ?? JournalRequirement.quick.minimumWords
            steps = [.challenge(journal), .technique(alarm?.wbtbTechnique ?? .mild), .backToSleep]
        }
    }
}
