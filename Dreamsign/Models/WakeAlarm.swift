import Foundation
import SwiftData

/// What you practice during a lucid window. Both had similar success in the International
/// Lucid Dream Induction Study (Aspy, 2020).
enum WBTBTechnique: String, Codable, CaseIterable, Identifiable, Sendable {
    case mild, ssild

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mild: "MILD"
        case .ssild: "SSILD"
        }
    }

    var detail: String {
        switch self {
        case .mild: String(localized: "Recall, intention, visualization")
        case .ssild: String(localized: "Cycle through sight, sound, touch")
        }
    }
}

/// A user alarm. The single WBTB plan is a `WakeAlarm` with `kind == .wbtb` whose time is
/// derived from bedtime + offset.
@Model
final class WakeAlarm {
    @Attribute(.unique) var id: UUID = UUID()
    var hour: Int = 7
    var minute: Int = 0
    var weekdaysRaw: Int = WeekdaySet.weekdays.rawValue
    var label: String = ""
    var soundRaw: String = AlarmSound.system.rawValue
    var isEnabled: Bool = true
    var chainMinutes: Int = 15
    var challengesData: Data = Data()
    var kindRaw: String = AlarmKind.wake.rawValue
    var revision: Int = 0
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now

    // WBTB only
    var bedtimeHour: Int = 23
    var bedtimeMinute: Int = 0
    var wbtbOffsetMinutes: Int = 300
    var mildMinutes: Int = 3
    var wbtbTechniqueRaw: String = WBTBTechnique.mild.rawValue
    var wbtbJournalWords: Int = JournalRequirement.quick.minimumWords

    init(time: AlarmTime = AlarmTime(hour: 7, minute: 0), weekdays: WeekdaySet = .weekdays, kind: AlarmKind = .wake) {
        id = UUID()
        hour = time.hour
        minute = time.minute
        weekdaysRaw = weekdays.rawValue
        kindRaw = kind.rawValue
        challenges = Challenge.defaults
        if kind == .wbtb {
            soundRaw = AlarmSound.dawn.rawValue
            chainMinutes = 10
            isEnabled = false
        }
    }

    var time: AlarmTime {
        get { AlarmTime(hour: hour, minute: minute) }
        set { hour = newValue.hour; minute = newValue.minute }
    }

    var weekdays: WeekdaySet {
        get { WeekdaySet(rawValue: weekdaysRaw) }
        set { weekdaysRaw = newValue.rawValue }
    }

    var sound: AlarmSound {
        get { AlarmSound(rawValue: soundRaw) ?? .system }
        set { soundRaw = newValue.rawValue }
    }

    var kind: AlarmKind { AlarmKind(rawValue: kindRaw) ?? .wake }

    var challenges: [Challenge] {
        get { (try? JSONDecoder().decode([Challenge].self, from: challengesData)) ?? [] }
        set { challengesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var displayLabel: String {
        if !label.isEmpty { return label }
        return kind == .wbtb ? String(localized: "Lucid window") : String(localized: "Alarm")
    }

    // MARK: WBTB

    var wbtbTechnique: WBTBTechnique {
        get { WBTBTechnique(rawValue: wbtbTechniqueRaw) ?? .mild }
        set { wbtbTechniqueRaw = newValue.rawValue }
    }

    var bedtime: AlarmTime {
        get { AlarmTime(hour: bedtimeHour, minute: bedtimeMinute) }
        set { bedtimeHour = newValue.hour; bedtimeMinute = newValue.minute }
    }

    /// Nights are chosen by bedtime; the alarm itself fires the morning after when it crosses midnight.
    var wbtbNights: WeekdaySet {
        get { bedtime.crossesMidnight(adding: wbtbOffsetMinutes) ? weekdays.shifted(by: -1) : weekdays }
        set { weekdays = bedtime.crossesMidnight(adding: wbtbOffsetMinutes) ? newValue.shifted(by: 1) : newValue }
    }

    /// Recomputes the fire time from bedtime + offset, keeping the chosen nights.
    func applyWBTB(bedtime newBedtime: AlarmTime, offsetMinutes: Int, nights: WeekdaySet) {
        bedtime = newBedtime
        wbtbOffsetMinutes = offsetMinutes
        time = newBedtime.adding(minutes: offsetMinutes)
        wbtbNights = nights
    }

    /// Call after any edit so the alarm layer reschedules.
    func touch() {
        revision += 1
        modifiedAt = .now
    }

    var spec: AlarmSpec {
        AlarmSpec(id: id, time: time, weekdays: weekdays, label: displayLabel, soundID: soundRaw,
                  chainLength: chainMinutes, kind: kind, isEnabled: isEnabled, revision: revision, modifiedAt: modifiedAt)
    }
}
