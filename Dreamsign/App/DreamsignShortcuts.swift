import AppIntents

/// Siri, Spotlight, the Shortcuts app and the Action button.
struct DreamsignShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordDreamIntent(),
                    phrases: ["Log a dream in \(.applicationName)",
                              "Record a dream in \(.applicationName)",
                              "\(.applicationName) dream journal"],
                    shortTitle: "Log a Dream",
                    systemImageName: "mic.fill")
        AppShortcut(intent: OpenTonightIntent(),
                    phrases: ["Going to bed in \(.applicationName)",
                              "Start my night in \(.applicationName)"],
                    shortTitle: "Going to Bed",
                    systemImageName: "moon.fill")
        AppShortcut(intent: RealityCheckIntent(),
                    phrases: ["Reality check in \(.applicationName)",
                              "Am I dreaming in \(.applicationName)"],
                    shortTitle: "Reality Check",
                    systemImageName: "hand.raised.fill")
    }
}
