import Foundation

/// Wall-clock time of day, independent of time zone.
struct AlarmTime: Codable, Hashable, Comparable, Sendable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.init(minutesSinceMidnight: hour * 60 + minute)
    }

    init(minutesSinceMidnight: Int) {
        let wrapped = ((minutesSinceMidnight % 1440) + 1440) % 1440
        hour = wrapped / 60
        minute = wrapped % 60
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }

    /// Adds minutes, wrapping past midnight.
    func adding(minutes: Int) -> AlarmTime {
        AlarmTime(minutesSinceMidnight: minutesSinceMidnight + minutes)
    }

    /// Whether adding `minutes` crosses midnight (used for WBTB nights → mornings).
    func crossesMidnight(adding minutes: Int) -> Bool {
        minutesSinceMidnight + minutes >= 1440
    }

    static func < (lhs: AlarmTime, rhs: AlarmTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    /// A date today at this time — handy for `DatePicker` bindings.
    func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

/// Occurrence math for relative alarms (time of day + optional weekly repeat).
enum OccurrenceMath {
    /// The first occurrence strictly after `date`.
    static func next(_ time: AlarmTime, weekdays: WeekdaySet, after date: Date, calendar: Calendar) -> Date? {
        if weekdays.isEmpty {
            return calendar.nextDate(after: date,
                                     matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
                                     matchingPolicy: .nextTime)
        }
        return weekdays.calendarWeekdays.compactMap { weekday in
            calendar.nextDate(after: date,
                              matching: DateComponents(hour: time.hour, minute: time.minute, second: 0, weekday: weekday),
                              matchingPolicy: .nextTime)
        }.min()
    }

    /// The most recent occurrence at or before `date`.
    static func previous(_ time: AlarmTime, weekdays: WeekdaySet, atOrBefore date: Date, calendar: Calendar) -> Date? {
        let probe = date.addingTimeInterval(1)
        if weekdays.isEmpty {
            return calendar.nextDate(after: probe,
                                     matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
                                     matchingPolicy: .nextTime,
                                     direction: .backward)
        }
        return weekdays.calendarWeekdays.compactMap { weekday in
            calendar.nextDate(after: probe,
                              matching: DateComponents(hour: time.hour, minute: time.minute, second: 0, weekday: weekday),
                              matchingPolicy: .nextTime,
                              direction: .backward)
        }.max()
    }
}
