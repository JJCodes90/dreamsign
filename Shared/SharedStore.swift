import Foundation
import Observation

/// What the app shows on widgets: written by the app, read by the widget extension, through
/// the App Group. Without the group (some sideloaded builds) each side keeps its own copy and
/// the widgets fall back to a friendly placeholder.
struct WidgetSnapshot: Codable, Hashable, Sendable {
    var nextAlarm: Date?
    var nextAlarmLabel: String = ""
    var nextAlarmChallenges: [String] = []
    var bedtime: Date?
    var tonightSign: String?
    var lucidWindow: Date?
    var recallStreak: Int = 0
    var updatedAt: Date = .now

    static let sample = WidgetSnapshot(
        nextAlarm: Calendar.current.date(bySettingHour: 6, minute: 45, second: 0, of: .now.addingTimeInterval(86_400)),
        nextAlarmLabel: "Work", nextAlarmChallenges: ["Shake", "Journal"],
        bedtime: Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now),
        tonightSign: "Old school",
        lucidWindow: Calendar.current.date(bySettingHour: 4, minute: 45, second: 0, of: .now.addingTimeInterval(86_400)),
        recallStreak: 12)
}

/// Where a widget, control or shortcut wants the app to go.
enum AppRoute: String, Codable, Sendable {
    case tonight, recordDream, realityCheck, journal
}

enum SharedStore {
    static let groupID = "group.com.jjcodes.dreamsign"

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static var snapshot: WidgetSnapshot? {
        get {
            guard let data = defaults.data(forKey: "widget.snapshot") else { return nil }
            return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "widget.snapshot")
        }
    }

    static var pendingRoute: AppRoute? {
        get { defaults.string(forKey: "route.pending").flatMap(AppRoute.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: "route.pending") }
    }

    // MARK: Reality checks (shared by the app and the interactive widget)

    static func realityChecksToday(now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let day = defaults.object(forKey: "realityChecks.day") as? Date,
              calendar.isDate(day, inSameDayAs: now)
        else { return 0 }
        return defaults.integer(forKey: "realityChecks.today")
    }

    static func logRealityCheck(now: Date = .now, calendar: Calendar = .current) {
        let count = realityChecksToday(now: now, calendar: calendar) + 1
        defaults.set(now, forKey: "realityChecks.day")
        defaults.set(count, forKey: "realityChecks.today")
    }
}

/// Routes requested by intents while the app is running.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var route: AppRoute?

    func open(_ route: AppRoute) {
        self.route = route
        SharedStore.pendingRoute = route
    }

    /// The route to handle now, if any; clears it.
    func take() -> AppRoute? {
        let next = route ?? SharedStore.pendingRoute
        route = nil
        SharedStore.pendingRoute = nil
        return next
    }
}
