import Foundation

/// Journal statistics as pure functions over plain values.
enum JournalStats {
    struct EntryFact: Hashable, Sendable {
        var date: Date
        var recalled: Bool
        var lucid = false
    }

    struct WeekBucket: Identifiable, Hashable, Sendable {
        var start: Date
        var count: Int
        var id: Date { start }
    }

    struct SignCount: Identifiable, Hashable, Sendable {
        var name: String
        var count: Int
        var id: String { name }
    }

    /// The morning an entry belongs to. 6 PM–6 PM windows, so a 3 AM WBTB entry and a
    /// 7 AM entry land on the same morning.
    static func morning(of date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(6 * 3600))
    }

    /// Consecutive mornings with a recalled dream, up to today (or yesterday, if today has
    /// no entry yet — the streak isn't broken until the morning is over).
    static func recallStreak(_ facts: [EntryFact], now: Date, calendar: Calendar) -> Int {
        let days = Set(facts.filter(\.recalled).map { morning(of: $0.date, calendar: calendar) })
        var day = morning(of: now, calendar: calendar)
        if !days.contains(day) { day = previousDay(day, calendar) }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = previousDay(day, calendar)
        }
        return streak
    }

    static func longestRecallStreak(_ facts: [EntryFact], calendar: Calendar) -> Int {
        let days = Set(facts.filter(\.recalled).map { morning(of: $0.date, calendar: calendar) }).sorted()
        var longest = 0, current = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.isDate(previousDay(day, calendar), inSameDayAs: previous) {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = day
        }
        return longest
    }

    /// Entry counts for the last `weeks` weeks, oldest first, including empty weeks.
    static func entriesPerWeek(_ dates: [Date], weeks: Int, now: Date, calendar: Calendar) -> [WeekBucket] {
        guard weeks > 0, let current = calendar.dateInterval(of: .weekOfYear, for: morning(of: now, calendar: calendar))?.start
        else { return [] }
        let starts = (0..<weeks).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: current) }
        var counts: [Date: Int] = [:]
        for date in dates {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: morning(of: date, calendar: calendar))?.start
            else { continue }
            counts[start, default: 0] += 1
        }
        return starts.map { WeekBucket(start: $0, count: counts[$0] ?? 0) }
    }

    /// Share of mornings-with-entries that had a recalled dream.
    static func recallRate(_ facts: [EntryFact], calendar: Calendar) -> Double? {
        let mornings = Dictionary(grouping: facts) { morning(of: $0.date, calendar: calendar) }
        guard !mornings.isEmpty else { return nil }
        let recalled = mornings.values.filter { $0.contains(where: \.recalled) }.count
        return Double(recalled) / Double(mornings.count)
    }

    static func topSigns(_ counts: [SignCount], limit: Int) -> [SignCount] {
        Array(counts
            .filter { $0.count > 0 }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCompare($1.name) == .orderedAscending }
            .prefix(limit))
    }

    private static func previousDay(_ day: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -1, to: day) ?? day.addingTimeInterval(-86_400)
    }
}
