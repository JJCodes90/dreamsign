import Foundation
import UserNotifications

/// "Time to wind down" reminders, rebuilt from the alarms on every sync.
@MainActor
enum BedtimeNudges {
    private static let prefix = "bedtime-nudge-"
    private static var center: UNUserNotificationCenter { .current() }

    /// Asks for notification permission; returns whether nudges can be shown.
    static func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func sync(_ alarms: [WakeAlarm], calendar: Calendar = .current) async {
        guard !Showcase.isActive else { return }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let wanted = alarms.filter { $0.kind == .wake && $0.isEnabled && $0.bedtimeNudge }
        guard !wanted.isEmpty else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let weekly = SleepPlan.weeklyNudges(wanted.filter { !$0.weekdays.isOneShot }.map {
            SleepPlan.NudgeInput(wake: $0.time, weekdays: $0.weekdays, goalMinutes: $0.sleepGoalMinutes, label: $0.displayLabel)
        })
        for nudge in weekly {
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: nudge.time.hour, minute: nudge.time.minute, weekday: nudge.weekday),
                repeats: true)
            await add("\(prefix)w\(nudge.weekday)", content(bedtime: nudge.bedtime, wake: nudge.wake, goal: nudge.goalMinutes),
                      trigger: trigger)
        }

        for alarm in wanted where alarm.weekdays.isOneShot {
            guard let fire = OccurrenceMath.next(alarm.time, weekdays: alarm.weekdays, after: .now, calendar: calendar) else { continue }
            let date = SleepPlan.oneShotNudge(fire: fire, goalMinutes: alarm.sleepGoalMinutes)
            guard date > .now else { continue }
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            await add("\(prefix)\(alarm.id.uuidString)",
                      content(bedtime: alarm.bedtimeForGoal, wake: alarm.time, goal: alarm.sleepGoalMinutes),
                      trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        }
    }

    private static func content(bedtime: AlarmTime, wake: AlarmTime, goal: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to wind down")
        content.body = String(localized: "In bed by \(ClockFormat.string(bedtime)) for \(SleepPlan.goalTitle(goal)) of sleep before your \(ClockFormat.string(wake)) alarm.")
        content.interruptionLevel = .active
        content.sound = .default
        return content
    }

    private static func add(_ identifier: String, _ content: UNMutableNotificationContent, trigger: UNNotificationTrigger) async {
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
