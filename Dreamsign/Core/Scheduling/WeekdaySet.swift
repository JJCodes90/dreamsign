import Foundation

/// Days of the week as a bitmask. Bit 0 = Sunday … bit 6 = Saturday, i.e. `Calendar` weekday − 1.
/// An empty set means a one-shot alarm.
struct WeekdaySet: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue & 0x7F }

    /// `calendarWeekday` uses `Calendar` numbering: 1 = Sunday … 7 = Saturday.
    init(calendarWeekday: Int) {
        let index = ((calendarWeekday - 1) % 7 + 7) % 7
        self.init(rawValue: 1 << index)
    }

    static let sunday    = WeekdaySet(rawValue: 1 << 0)
    static let monday    = WeekdaySet(rawValue: 1 << 1)
    static let tuesday   = WeekdaySet(rawValue: 1 << 2)
    static let wednesday = WeekdaySet(rawValue: 1 << 3)
    static let thursday  = WeekdaySet(rawValue: 1 << 4)
    static let friday    = WeekdaySet(rawValue: 1 << 5)
    static let saturday  = WeekdaySet(rawValue: 1 << 6)

    static let weekdays: WeekdaySet = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekends: WeekdaySet = [.saturday, .sunday]
    static let everyDay: WeekdaySet = [.weekdays, .weekends]

    var isOneShot: Bool { isEmpty }

    /// Member days as `Calendar` weekdays, ascending (1 = Sunday).
    var calendarWeekdays: [Int] {
        (1...7).filter { contains(WeekdaySet(calendarWeekday: $0)) }
    }

    /// Moves every day by `days`, e.g. bedtime nights → the mornings after them.
    func shifted(by days: Int) -> WeekdaySet {
        var result: WeekdaySet = []
        for day in calendarWeekdays {
            result.insert(WeekdaySet(calendarWeekday: day + days))
        }
        return result
    }

    /// Calendar weekdays in display order, starting at the calendar's first weekday.
    static func displayOrder(for calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    func summary(calendar: Calendar = .current) -> String {
        if isEmpty { return String(localized: "Once") }
        if self == .everyDay { return String(localized: "Every day") }
        if self == .weekdays { return String(localized: "Weekdays") }
        if self == .weekends { return String(localized: "Weekends") }
        let symbols = calendar.shortWeekdaySymbols
        return WeekdaySet.displayOrder(for: calendar)
            .filter { contains(WeekdaySet(calendarWeekday: $0)) }
            .map { symbols[$0 - 1] }
            .joined(separator: " ")
    }
}
