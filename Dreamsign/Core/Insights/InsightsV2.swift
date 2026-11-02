import Foundation

// MARK: - Calendar

/// One day on the dream calendar.
enum RecallLevel: Int, Comparable, Sendable {
    case empty, fragment, full, lucid

    static func < (lhs: RecallLevel, rhs: RecallLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct DreamDay: Hashable, Identifiable, Sendable {
    var date: Date
    var level: RecallLevel
    var id: Date { date }
}

enum DreamCalendar {
    struct Fact: Hashable, Sendable {
        var date: Date
        var recalled: Bool
        var lucid: Bool
        var words: Int
    }

    /// A dream this long or longer counts as a full dream rather than a fragment.
    static let fullDreamWords = 30

    /// The month's days with leading blanks (`nil`) so the first day lands under its weekday.
    static func month(containing date: Date, facts: [Fact], calendar: Calendar) -> [DreamDay?] {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        var levels: [Date: RecallLevel] = [:]
        for fact in facts {
            let day = JournalStats.morning(of: fact.date, calendar: calendar)
            let level: RecallLevel = fact.lucid ? .lucid : !fact.recalled ? .fragment
                : fact.words >= fullDreamWords ? .full : .fragment
            levels[day] = max(levels[day] ?? .empty, level)
        }
        let first = interval.start
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var days: [DreamDay?] = Array(repeating: nil, count: leading)
        var day = first
        while day < interval.end {
            days.append(DreamDay(date: day, level: levels[calendar.startOfDay(for: day)] ?? .empty))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}

// MARK: - Milestones

struct Milestone: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var symbol: String
    var target: Int
    var current: Int
    var achievedAt: Date?

    var isAchieved: Bool { achievedAt != nil }
    var progress: Double { min(Double(current) / Double(max(target, 1)), 1) }
}

enum Milestones {
    /// Every milestone with progress; achieved ones carry the date they were reached.
    static func all(_ facts: [JournalStats.EntryFact], calendar: Calendar) -> [Milestone] {
        let sorted = facts.sorted { $0.date < $1.date }
        let dreams = sorted.filter(\.recalled)
        let lucid = sorted.filter(\.lucid)

        func countMilestone(_ id: String, _ title: String, _ symbol: String, _ items: [JournalStats.EntryFact], _ target: Int) -> Milestone {
            Milestone(id: id, title: title, symbol: symbol, target: target, current: min(items.count, target),
                      achievedAt: items.count >= target ? items[target - 1].date : nil)
        }

        var result: [Milestone] = [
            countMilestone("first-dream", String(localized: "First dream"), "moon.stars.fill", dreams, 1),
            countMilestone("first-lucid", String(localized: "First lucid"), "sparkle", lucid, 1),
        ]
        // Streaks: the date the run first reached the target.
        for target in [7, 30] {
            let (best, reachedAt) = streakProgress(dreams, target: target, calendar: calendar)
            result.append(Milestone(id: "streak-\(target)", title: String(localized: "\(target)-morning streak"),
                                    symbol: "flame.fill", target: target, current: min(best, target), achievedAt: reachedAt))
        }
        for target in [10, 25, 50, 100] {
            result.append(countMilestone("dreams-\(target)", String(localized: "\(target) dreams"), "book.closed.fill", dreams, target))
        }
        result.append(countMilestone("lucid-5", String(localized: "5 lucid dreams"), "sparkles", lucid, 5))
        return result
    }

    /// What to show: the latest achievements, then the next goals.
    static func highlights(_ facts: [JournalStats.EntryFact], calendar: Calendar, count: Int = 3) -> [Milestone] {
        let all = all(facts, calendar: calendar)
        let achieved = all.filter(\.isAchieved).sorted { ($0.achievedAt ?? .distantPast) > ($1.achievedAt ?? .distantPast) }
        let pending = all.filter { !$0.isAchieved }.sorted { $0.progress > $1.progress }
        // Recent wins first, always leaving room for the next goal.
        var result = Array(achieved.prefix(pending.isEmpty ? count : count - 1))
        result += pending.prefix(count - result.count)
        return result
    }

    private static func streakProgress(_ dreams: [JournalStats.EntryFact], target: Int, calendar: Calendar) -> (Int, Date?) {
        let days = Set(dreams.map { JournalStats.morning(of: $0.date, calendar: calendar) }).sorted()
        var best = 0, current = 0
        var previous: Date?
        var reachedAt: Date?
        for day in days {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), calendar.isDate(next, inSameDayAs: day) {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            if current >= target, reachedAt == nil { reachedAt = day }
            previous = day
        }
        return (best, reachedAt)
    }
}

// MARK: - Sleep (from Health)

enum SleepStage: Sendable {
    case asleep, rem, awake, inBed
}

struct SleepSample: Hashable, Sendable {
    var start: Date
    var end: Date
    var stage: SleepStage
}

struct SleepNight: Hashable, Identifiable, Sendable {
    var morning: Date
    var asleepMinutes: Double
    var remMinutes: Double
    var id: Date { morning }
}

enum SleepNights {
    /// Nights from raw samples. Overlapping samples (a watch and a phone) are merged, so time
    /// is never counted twice.
    static func summarize(_ samples: [SleepSample], calendar: Calendar) -> [SleepNight] {
        let grouped = Dictionary(grouping: samples) { JournalStats.morning(of: $0.end, calendar: calendar) }
        return grouped.map { morning, items in
            let asleep = union(items.filter { $0.stage == .asleep || $0.stage == .rem })
            let rem = union(items.filter { $0.stage == .rem })
            return SleepNight(morning: morning, asleepMinutes: asleep / 60, remMinutes: rem / 60)
        }
        .filter { $0.asleepMinutes >= 60 }
        .sorted { $0.morning < $1.morning }
    }

    /// Total seconds covered by the samples' intervals.
    static func union(_ samples: [SleepSample]) -> TimeInterval {
        let intervals = samples.map { ($0.start, $0.end) }.filter { $0.0 < $0.1 }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for interval in intervals {
            if let open = current, interval.0 <= open.1 {
                current = (open.0, max(open.1, interval.1))
            } else {
                if let open = current { total += open.1.timeIntervalSince(open.0) }
                current = interval
            }
        }
        if let open = current { total += open.1.timeIntervalSince(open.0) }
        return total
    }

    struct Comparison: Hashable, Sendable {
        var longRate: Double
        var shortRate: Double
        var longNights: Int
        var shortNights: Int
    }

    /// Recall rate on nights with at least `threshold` minutes of sleep vs fewer. Nil without
    /// at least three nights on each side.
    static func recallComparison(_ nights: [SleepNight], facts: [JournalStats.EntryFact], threshold: Double = 420,
                                 calendar: Calendar) -> Comparison? {
        let recalled = Set(facts.filter(\.recalled).map { JournalStats.morning(of: $0.date, calendar: calendar) })
        let long = nights.filter { $0.asleepMinutes >= threshold }
        let short = nights.filter { $0.asleepMinutes < threshold }
        guard long.count >= 3, short.count >= 3 else { return nil }
        func rate(_ group: [SleepNight]) -> Double {
            Double(group.filter { recalled.contains($0.morning) }.count) / Double(group.count)
        }
        return Comparison(longRate: rate(long), shortRate: rate(short), longNights: long.count, shortNights: short.count)
    }
}
