import Foundation

enum AlarmKind: String, Codable, Hashable, Sendable {
    case wake
    case wbtb
}

/// Everything the alarm layer needs to know about an alarm — a snapshot of `WakeAlarm`
/// that the App Intents can read without touching SwiftData.
struct AlarmSpec: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var time: AlarmTime
    var weekdays: WeekdaySet
    var label: String
    var soundID: String
    /// Follow-up rings, one per `ChainPlanner.ringInterval`.
    var chainLength: Int
    var kind: AlarmKind
    var isEnabled: Bool
    var revision: Int
    var modifiedAt: Date
    /// Minutes before the alarm for a soft "gentle start" ring; nil or 0 = off.
    var gentleMinutes: Int? = nil

    /// Changes whenever the scheduled primary alarm must be replaced.
    var fingerprint: String {
        "\(time.minutesSinceMidnight)|\(weekdays.rawValue)|\(kind.rawValue)|\(soundID)|\(label)|r\(revision)"
    }
}

struct ArmedRing: Codable, Hashable, Sendable {
    var id: UUID
    var fireDate: Date
}

/// One firing of an alarm and its chain of follow-up rings.
struct Occurrence: Codable, Hashable, Identifiable, Sendable {
    var alarmID: UUID
    var fireDate: Date
    var kind: AlarmKind
    var chainLength: Int
    var rings: [ArmedRing] = []
    /// AlarmKit id of the alarm that starts this occurrence. For regular alarms it's the
    /// repeating primary (`alarmID`); for one-offs (tests, "going to bed now") it's its own id.
    var primaryID: UUID?
    var isOneOff = false
    var isTest = false
    var completedAt: Date?
    /// Soft ring before `fireDate` (gentle start). Never starts the wake flow by itself.
    var gentle: ArmedRing?
    /// Set on a wake-up check: the id of the occurrence it follows.
    var checkOf: String?
    /// The spec revision this occurrence was armed for; an edit re-arms it.
    var specRevision: Int?

    var id: String { Occurrence.key(alarmID: alarmID, fireDate: fireDate) }

    static func key(alarmID: UUID, fireDate: Date) -> String {
        "\(alarmID.uuidString)@\(Int(fireDate.timeIntervalSince1970.rounded()))"
    }

    var isCompleted: Bool { completedAt != nil }
    var isCheck: Bool { checkOf != nil }

    /// After this moment the occurrence can no longer be "active".
    var windowEnd: Date {
        let nominal = fireDate.addingTimeInterval(Double(max(chainLength, 1)) * ChainPlanner.ringInterval)
        let lastRing = rings.map(\.fireDate).max() ?? fireDate
        return max(nominal, lastRing).addingTimeInterval(ChainPlanner.activeGrace)
    }

    /// Every AlarmKit id this occurrence owns. A repeating primary is shared with
    /// future occurrences, so it's only included for one-offs.
    var ownedAlarmIDs: [UUID] {
        (isOneOff ? [primaryID].compactMap { $0 } : []) + [gentle?.id].compactMap { $0 } + rings.map(\.id)
    }

    /// Every AlarmKit id that can ring for this occurrence.
    var allAlarmIDs: [UUID] {
        [primaryID, gentle?.id].compactMap { $0 } + rings.map(\.id)
    }

    func pendingRings(after now: Date) -> [ArmedRing] {
        rings.filter { $0.fireDate > now }
    }

    /// Follow-up rings plus a gentle start that hasn't fired yet — what counts against the budget.
    func pendingAlarmCount(after now: Date) -> Int {
        pendingRings(after: now).count + ((gentle?.fireDate ?? .distantPast) > now ? 1 : 0)
    }
}

struct PrimaryRecord: Codable, Hashable, Sendable {
    var fingerprint: String
    var scheduledAt: Date
    /// First fire date at the time of scheduling — lets us tell a fired one-shot from a lost one.
    var expectedFire: Date?
}

struct PendingWake: Codable, Hashable, Sendable {
    var occurrenceID: String
    var requestedAt: Date
}

/// Persisted alarm-layer state (JSON in UserDefaults).
struct ChainState: Codable, Hashable, Sendable {
    var specs: [AlarmSpec] = []
    var occurrences: [Occurrence] = []
    /// Keyed by spec id string.
    var primaries: [String: PrimaryRecord] = [:]
    var pendingWake: PendingWake?
    /// Set when the ring budget cut a chain short.
    var truncatedAt: Date?

    func spec(_ id: UUID) -> AlarmSpec? { specs.first { $0.id == id } }

    func occurrence(_ id: String) -> Occurrence? { occurrences.first { $0.id == id } }

    func occurrence(owning alarmKitID: UUID) -> Occurrence? {
        occurrences.first {
            $0.rings.contains { $0.id == alarmKitID } || $0.gentle?.id == alarmKitID
                || ($0.isOneOff && $0.primaryID == alarmKitID)
        }
    }
}

/// What AlarmKit currently holds for us.
struct AlarmSnapshot: Hashable, Sendable {
    var id: UUID
    var isAlerting: Bool
}

/// How a ring presents itself.
enum RingStyle: Hashable, Sendable {
    /// The alarm, or a follow-up ring of its chain.
    case standard
    /// A soft ring shortly before the alarm.
    case gentle
    /// "Still up?" — a few minutes after the challenges were finished.
    case check
}

/// Everything the scheduler needs to configure one fixed ring.
struct RingRequest: Hashable, Sendable {
    var ring: ArmedRing
    var alarmID: UUID
    var occurrenceID: String
    var kind: AlarmKind
    var label: String
    var soundID: String
    /// 0 = the occurrence's first ring (one-offs), 1… = follow-ups.
    var index: Int
    var style: RingStyle = .standard
}

enum ChainOperation: Hashable, Sendable {
    case schedulePrimary(AlarmSpec)
    case scheduleRing(RingRequest)
    case cancel(UUID)
    case stop(UUID)

    var alarmID: UUID {
        switch self {
        case .schedulePrimary(let spec): spec.id
        case .scheduleRing(let request): request.ring.id
        case .cancel(let id), .stop(let id): id
        }
    }
}
