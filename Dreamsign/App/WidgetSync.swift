import Foundation
import SwiftData
import WidgetKit

/// Writes what the widgets show and asks WidgetKit to refresh.
@MainActor
enum WidgetSync {
    static func update(_ context: ModelContext, coordinator: AlarmCoordinator, now: Date = .now) {
        guard !Showcase.isActive else { return }
        let alarms = (try? context.fetch(FetchDescriptor<WakeAlarm>())) ?? []
        let calendar = Calendar.current

        let nextWake = alarms.filter { $0.isEnabled && $0.kind == .wake }
            .compactMap { alarm in
                OccurrenceMath.next(alarm.time, weekdays: alarm.weekdays, after: now, calendar: calendar).map { (alarm, $0) }
            }
            .min { $0.1 < $1.1 }

        var snapshot = WidgetSnapshot()
        if let next = nextWake {
            let (alarm, date) = next
            snapshot.nextAlarm = date
            snapshot.nextAlarmLabel = alarm.displayLabel
            snapshot.nextAlarmChallenges = alarm.challenges.map(\.kind.title)
            let option = SleepPlan.closestOption(forWake: alarm.time, goalMinutes: alarm.sleepGoalMinutes)
            snapshot.bedtime = date.addingTimeInterval(-Double(option.sleepMinutes + SleepPlan.latencyMinutes) * 60)
        }

        if let plan = alarms.first(where: { $0.kind == .wbtb }) {
            if let tonight = coordinator.upcomingOneOff(for: plan.id) {
                snapshot.lucidWindow = tonight.fireDate
            } else if plan.isEnabled,
                      let next = OccurrenceMath.next(plan.time, weekdays: plan.weekdays, after: now, calendar: calendar),
                      next.timeIntervalSince(now) < 20 * 3600 {
                snapshot.lucidWindow = next
            }
        }

        let signs = (try? context.fetch(FetchDescriptor<DreamSign>())) ?? []
        let chosen = signs.first { $0.key == NightPreferences.intentionSign }
            ?? signs.filter { !$0.entries.isEmpty }.max { $0.entries.count < $1.entries.count }
        snapshot.tonightSign = chosen?.name

        let entries = (try? context.fetch(FetchDescriptor<DreamEntry>())) ?? []
        let facts = entries.map { JournalStats.EntryFact(date: $0.createdAt, recalled: !$0.isNoRecall) }
        snapshot.recallStreak = JournalStats.recallStreak(facts, now: now, calendar: calendar)
        snapshot.updatedAt = now

        guard snapshot.withoutTimestamp != SharedStore.snapshot?.withoutTimestamp else { return }
        SharedStore.snapshot = snapshot
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private extension WidgetSnapshot {
    var withoutTimestamp: WidgetSnapshot {
        var copy = self
        copy.updatedAt = .distantPast
        return copy
    }
}
