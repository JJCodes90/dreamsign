import Foundation

/// Sleep-cycle math for bedtimes and nudges. Cycles average about 90 minutes and REM grows
/// longer toward morning, so waking between cycles tends to feel lighter.
enum SleepPlan {
    static let cycleMinutes = 90
    /// Typical time to fall asleep.
    static let latencyMinutes = 15
    /// How far ahead of bedtime the nudge arrives.
    static let nudgeLeadMinutes = 30
    static let goalOptions = [360, 420, 450, 480, 540]

    struct Option: Hashable, Sendable, Identifiable {
        var cycles: Int
        var bedtime: AlarmTime
        var sleepMinutes: Int { cycles * SleepPlan.cycleMinutes }
        var id: Int { cycles }
    }

    /// Bedtimes that land the alarm at the end of a cycle, shortest night first.
    static func options(forWake wake: AlarmTime, cycles: ClosedRange<Int> = 4...6) -> [Option] {
        cycles.map { Option(cycles: $0, bedtime: bedtime(forWake: wake, sleepMinutes: $0 * cycleMinutes)) }
    }

    /// When to get into bed to sleep `sleepMinutes` before `wake`.
    static func bedtime(forWake wake: AlarmTime, sleepMinutes: Int) -> AlarmTime {
        wake.adding(minutes: -(sleepMinutes + latencyMinutes))
    }

    /// The cycle option closest to a sleep goal.
    static func closestOption(forWake wake: AlarmTime, goalMinutes: Int) -> Option {
        let all = options(forWake: wake, cycles: 3...7)
        return all.min { abs($0.sleepMinutes - goalMinutes) < abs($1.sleepMinutes - goalMinutes) } ?? all[0]
    }

    /// Lucid window: about 4½–6 hours after falling asleep, when REM periods get long.
    static func lucidWindow(bedtime: AlarmTime, offsetMinutes: Int = 300) -> AlarmTime {
        bedtime.adding(minutes: latencyMinutes + offsetMinutes)
    }

    static func goalTitle(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
    }

    // MARK: Nudges

    struct NudgeInput: Hashable, Sendable {
        var wake: AlarmTime
        var weekdays: WeekdaySet
        var goalMinutes: Int
        var label: String
    }

    /// One weekly reminder: on `weekday` (Calendar numbering) at `time`.
    struct Nudge: Hashable, Sendable {
        var weekday: Int
        var time: AlarmTime
        var bedtime: AlarmTime
        var wake: AlarmTime
        var goalMinutes: Int
        var label: String
    }

    /// Weekly reminders for repeating alarms: the evening before each alarm day, or the same
    /// day when bedtime falls after midnight. When two alarms share a night, the earlier
    /// reminder wins, so a night never gets two.
    static func weeklyNudges(_ inputs: [NudgeInput]) -> [Nudge] {
        var byNight: [Int: Nudge] = [:]
        for input in inputs where !input.weekdays.isOneShot {
            let bed = bedtime(forWake: input.wake, sleepMinutes: input.goalMinutes)
            let remind = bed.adding(minutes: -nudgeLeadMinutes)
            let minutesBefore = input.goalMinutes + latencyMinutes + nudgeLeadMinutes
            // Days back from the alarm day to the reminder (0 = same day, 1 = the evening before).
            let daysBack = Int((Double(minutesBefore - input.wake.minutesSinceMidnight) / 1440).rounded(.up))
            for weekday in input.weekdays.calendarWeekdays {
                let day = ((weekday - 1 - max(daysBack, 0)) % 7 + 7) % 7 + 1
                let nudge = Nudge(weekday: day, time: remind, bedtime: bed, wake: input.wake,
                                  goalMinutes: input.goalMinutes, label: input.label)
                // Small hours belong to the night that started the evening before.
                let night = remind.minutesSinceMidnight < 18 * 60 ? (day + 5) % 7 + 1 : day
                if let existing = byNight[night], nightOrder(existing.time) <= nightOrder(nudge.time) { continue }
                byNight[night] = nudge
            }
        }
        return byNight.values.sorted { ($0.weekday, $0.time) < ($1.weekday, $1.time) }
    }

    /// Orders evening times before after-midnight times (6 PM … 5:59 PM next day).
    private static func nightOrder(_ time: AlarmTime) -> Int {
        (time.minutesSinceMidnight - 18 * 60 + 1440) % 1440
    }

    /// The single reminder date for a one-shot alarm that next fires at `fire`.
    static func oneShotNudge(fire: Date, goalMinutes: Int) -> Date {
        fire.addingTimeInterval(-Double(goalMinutes + latencyMinutes + nudgeLeadMinutes) * 60)
    }
}
