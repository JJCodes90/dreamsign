import Foundation
import Testing
@testable import Dreamsign

@Suite("Weekdays & occurrences")
struct SchedulingTests {
    let calendar = Fixtures.calendar
    let seven = AlarmTime(hour: 7, minute: 0)

    @Test func oneShotFiresNextMatchingTime() {
        let before = Fixtures.date(2026, 11, 2, 6, 59)
        #expect(OccurrenceMath.next(seven, weekdays: [], after: before, calendar: calendar) == Fixtures.date(2026, 11, 2, 7, 0))
        let exactly = Fixtures.date(2026, 11, 2, 7, 0)
        #expect(OccurrenceMath.next(seven, weekdays: [], after: exactly, calendar: calendar) == Fixtures.date(2026, 11, 3, 7, 0))
    }

    @Test func weeklyPicksTheSoonestDay() {
        let days: WeekdaySet = [.monday, .wednesday, .friday]
        // Monday 08:00 → Wednesday 07:00
        let next = OccurrenceMath.next(seven, weekdays: days, after: Fixtures.date(2026, 11, 2, 8, 0), calendar: calendar)
        #expect(next == Fixtures.date(2026, 11, 4, 7, 0))
        // Friday 07:30 → next Monday
        let afterFriday = OccurrenceMath.next(seven, weekdays: days, after: Fixtures.date(2026, 11, 6, 7, 30), calendar: calendar)
        #expect(afterFriday == Fixtures.date(2026, 11, 9, 7, 0))
    }

    @Test func previousIncludesTheExactMoment() {
        let at = Fixtures.date(2026, 11, 2, 7, 0)
        #expect(OccurrenceMath.previous(seven, weekdays: [], atOrBefore: at, calendar: calendar) == at)
        let later = Fixtures.date(2026, 11, 2, 7, 5)
        #expect(OccurrenceMath.previous(seven, weekdays: .weekdays, atOrBefore: later, calendar: calendar) == at)
        // Sunday: the last weekday 07:00 was Friday.
        let sunday = Fixtures.date(2026, 11, 8, 9, 0)
        #expect(OccurrenceMath.previous(seven, weekdays: .weekdays, atOrBefore: sunday, calendar: calendar) == Fixtures.date(2026, 11, 6, 7, 0))
    }

    @Test func springForwardGapMovesToNextExistingTime() {
        // 02:30 doesn't exist on Mar 8 2026 in New York.
        let next = OccurrenceMath.next(AlarmTime(hour: 2, minute: 30), weekdays: [],
                                       after: Fixtures.date(2026, 3, 8, 0, 0), calendar: calendar)
        let parts = calendar.dateComponents([.day, .hour], from: next!)
        #expect(parts.day == 8)
        #expect(parts.hour == 3)
    }

    @Test func weekdaySetBasics() {
        #expect(WeekdaySet(calendarWeekday: 1) == .sunday)
        #expect(WeekdaySet(calendarWeekday: 7) == .saturday)
        #expect(WeekdaySet.weekdays.calendarWeekdays == [2, 3, 4, 5, 6])
        #expect(WeekdaySet.saturday.shifted(by: 1) == .sunday)
        #expect(WeekdaySet.sunday.shifted(by: -1) == .saturday)
        #expect(WeekdaySet([.friday, .saturday]).shifted(by: 1) == [.saturday, .sunday])
        #expect(WeekdaySet().isOneShot)
        #expect(WeekdaySet(rawValue: 0xFF) == .everyDay)
    }

    @Test func weekdaySummaries() {
        #expect(WeekdaySet().summary(calendar: calendar) == "Once")
        #expect(WeekdaySet.everyDay.summary(calendar: calendar) == "Every day")
        #expect(WeekdaySet.weekdays.summary(calendar: calendar) == "Weekdays")
        #expect(WeekdaySet.weekends.summary(calendar: calendar) == "Weekends")
        #expect(WeekdaySet([.monday, .wednesday]).summary(calendar: calendar) == "Mon Wed")
    }

    @Test func displayOrderRespectsFirstWeekday() {
        var monday = calendar
        monday.firstWeekday = 2
        #expect(WeekdaySet.displayOrder(for: monday) == [2, 3, 4, 5, 6, 7, 1])
        #expect(WeekdaySet.displayOrder(for: calendar) == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func alarmTimeArithmetic() {
        let bedtime = AlarmTime(hour: 23, minute: 30)
        #expect(bedtime.adding(minutes: 300) == AlarmTime(hour: 4, minute: 30))
        #expect(bedtime.crossesMidnight(adding: 300))
        #expect(!AlarmTime(hour: 1, minute: 0).crossesMidnight(adding: 300))
        #expect(AlarmTime(hour: 25, minute: 0) == AlarmTime(hour: 1, minute: 0))
        #expect(AlarmTime(minutesSinceMidnight: -30) == AlarmTime(hour: 23, minute: 30))
    }
}
