import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var syncing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Permission") {
                        Text(permissionText).foregroundStyle(permissionColor)
                    }
                    if model.coordinator.authorization != .authorized {
                        Button(model.coordinator.authorization == .denied ? "Open Settings" : "Allow Alarms") {
                            if model.coordinator.authorization == .denied {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            } else {
                                Task { await model.coordinator.requestAuthorization() }
                            }
                        }
                    }
                    LabeledContent("Follow-up rings armed", value: "\(model.coordinator.armedRingCount)")
                    Button {
                        syncing = true
                        Task {
                            await model.syncAlarms(context)
                            syncing = false
                        }
                    } label: {
                        HStack {
                            Text("Re-sync alarms")
                            if syncing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(syncing)
                } header: {
                    Text("Alarms")
                } footer: {
                    if let error = model.coordinator.lastError {
                        Text("Last scheduling error: \(error)")
                    }
                }

                Section {
                    explainer("speaker.wave.3", "Turn Ringer and Alerts up high: Settings › Sounds & Haptics. Alarms play at that volume, and iOS doesn't let apps change it.")
                    explainer("hand.tap", "Turn off \"Change with Buttons\" there too, so the volume buttons can't quietly lower your alarm.")
                    explainer("bell.badge", "Use the Classic sound for anything you must wake to. Custom sounds can play only once, or quietly, on some iOS versions.")
                    explainer("lock.iphone", "Use \"Test in 10 seconds\" on an alarm with Silent mode on and the phone locked to check it.")
                } header: {
                    Text("Make sure you hear it")
                }

                Section("How it works") {
                    explainer("bell.and.waves.left.and.right", "iOS always shows a Stop button on alarms. Dreamsign schedules a follow-up ring every minute, so Stop only buys a minute.")
                    explainer("checkmark.seal", "Finishing your challenges in the app ends the chain.")
                    explainer("hand.tap", "While you're working on a challenge, the next ring waits. Put the phone down for two minutes and it rings again.")
                }

                Section {
                    ForEach(Research.sources) { source in
                        Link(destination: source.url) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.title).foregroundStyle(Palette.text)
                                Text(source.citation).font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                } header: {
                    Text("The science")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                } footer: {
                    Text("No accounts, no analytics, no network. Your dreams never leave this iPhone.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(NightBackground(stars: false))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            }
        }
    }

    private var permissionText: String {
        switch model.coordinator.authorization {
        case .authorized: String(localized: "Allowed")
        case .denied: String(localized: "Off")
        case .notDetermined: String(localized: "Not asked yet")
        }
    }

    private var permissionColor: Color {
        model.coordinator.authorization == .authorized ? Palette.mint : Palette.ember
    }

    private func explainer(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(.subheadline).foregroundStyle(Palette.textSecondary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Palette.iris)
        }
        .padding(.vertical, 2)
    }
}

/// Sources behind the app's design choices.
enum Research {
    struct Source: Identifiable {
        let title: String
        let citation: String
        let url: URL
        var id: String { title }
    }

    static let sources: [Source] = [
        Source(title: String(localized: "MILD and wake-back-to-bed"),
               citation: "Aspy, D. J. (2020). Findings from the International Lucid Dream Induction Study. Frontiers in Psychology, 11, 1746.",
               url: URL(string: "https://doi.org/10.3389/fpsyg.2020.01746")!),
        Source(title: String(localized: "Reality testing vs. MILD"),
               citation: "Aspy, D. J., Delfabbro, P., Proeve, M., & Mohr, P. (2017). Reality testing and the mnemonic induction of lucid dreams. Dreaming, 27(3), 206–231.",
               url: URL(string: "https://doi.org/10.1037/drm0000059")!),
        Source(title: String(localized: "Dream journals boost recall"),
               citation: "Aspy, D. J., Delfabbro, P., & Proeve, M. (2015). Is dream recall underestimated by retrospective measures and enhanced by keeping a logbook? Consciousness and Cognition, 33, 364–374.",
               url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/25725324/")!),
        Source(title: String(localized: "Induction techniques reviewed"),
               citation: "Stumbrys, T., Erlacher, D., Schädlich, M., & Schredl, M. (2012). Induction of lucid dreams: A systematic review of evidence. Consciousness and Cognition, 21(3), 1456–1475.",
               url: URL(string: "https://doi.org/10.1016/j.concog.2012.07.003")!),
        Source(title: String(localized: "Waking grogginess (sleep inertia)"),
               citation: "Hilditch, C. J., & McHill, A. W. (2019). Sleep inertia: current insights. Nature and Science of Sleep, 11, 155–165.",
               url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC6710480/")!),
        Source(title: String(localized: "Dream signs and MILD, from the source"),
               citation: "LaBerge, S., & Rheingold, H. (1990). Exploring the World of Lucid Dreaming. Ballantine.",
               url: URL(string: "https://www.lucidity.com/")!),
    ]
}
