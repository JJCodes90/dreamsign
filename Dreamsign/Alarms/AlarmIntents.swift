import AlarmKit
import AppIntents

/// Runs when Stop is tapped on any Dreamsign alarm. It quiets sibling rings of the same
/// wake-up so they never stack — but the chain keeps going until challenges are done.
struct StopRingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Ring"
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var alarmKitID: String

    init() {}

    init(alarmKitID: UUID) {
        self.alarmKitID = alarmKitID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmKitID) {
            await AlarmCoordinator.shared.ringInteraction(alarmKitID: id, openApp: false)
        }
        return .result()
    }
}

/// The alert's secondary button: opens Dreamsign straight into the wake-up challenges.
struct WakeUpIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Wake Up"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Alarm ID")
    var alarmKitID: String

    init() {}

    init(alarmKitID: UUID) {
        self.alarmKitID = alarmKitID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmKitID) {
            await AlarmCoordinator.shared.ringInteraction(alarmKitID: id, openApp: true)
        }
        return .result()
    }
}
