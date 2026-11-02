import AppIntents
import Foundation

/// "Going to bed": opens Tonight.
struct OpenTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "Going to Bed"
    static let description = IntentDescription("Open Tonight in Dreamsign to plan your night and start sleep sounds.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.tonight)
        return .result()
    }
}

/// "Log a dream": opens a new journal entry, listening.
struct RecordDreamIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Dream"
    static let description = IntentDescription("Start a new dream journal entry by voice.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.recordDream)
        return .result()
    }
}

/// Opens the guided reality check.
struct RealityCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Reality Check"
    static let description = IntentDescription("Do a guided reality check.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.realityCheck)
        return .result()
    }
}

/// The widget's "Done" button: counts a reality check without opening the app.
struct LogRealityCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Reality Check"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        SharedStore.logRealityCheck()
        return .result()
    }
}
