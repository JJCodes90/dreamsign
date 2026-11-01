import SwiftData
import SwiftUI
import UserNotifications

/// An interactive, mindful reality check — plus optional daytime reminders.
struct RealityCheckView: View {
    enum Step: Int, CaseIterable {
        case ask, text, hands, breath, context, done
    }

    @Environment(\.dismiss) private var dismiss
    @Query private var signs: [DreamSign]
    @State private var step: Step = .ask
    @State private var phrase = RealityCheckView.randomPhrase()
    @State private var lookingAway = false
    @State private var checkedText = false
    @State private var reminders = RealityCheckReminders.shared
    @AppStorage("realityChecks.total") private var total = 0

    private var topSigns: [String] {
        signs.sorted { $0.entries.count > $1.entries.count }.prefix(3).map(\.name)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NightBackground()
            VStack(spacing: 0) {
                HStack {
                    StepCapsules(total: Step.allCases.count, current: step.rawValue)
                    Spacer()
                    Button(role: .close) { dismiss() }
                        .buttonStyle(.glass)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)

                FoldAvoiding(tabletop: .top) {
                    VStack(spacing: 24) {
                        Spacer(minLength: 12)
                        content
                            .id(step)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 20)), removal: .opacity))
                        Spacer(minLength: 12)
                        nextButton
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 12)
                    .readableWidth(520)
                }
            }
        }
        .animation(.smooth(duration: 0.45), value: step)
        .sensoryFeedback(.selection, trigger: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .ask:
            prompt(symbol: "questionmark.circle", title: "Are you dreaming right now?",
                   body: "Stop for a moment and genuinely consider it. Look around. Is anything strange?")
        case .text:
            VStack(spacing: 22) {
                prompt(symbol: "text.viewfinder", title: "Read, look away, read again",
                       body: lookingAway ? "Look away from the screen…" : checkedText
                           ? "Still the same? In a dream, text rarely stays put."
                           : "Read this, then tap Look away.")
                Text(lookingAway ? " " : phrase)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.dawn)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .card(tint: Palette.dawn)
                    .contentTransition(.opacity)
                if !checkedText {
                    Button {
                        Task {
                            withAnimation { lookingAway = true }
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { lookingAway = false; checkedText = true }
                        }
                    } label: {
                        Label("Look away", systemImage: "eye.slash")
                    }
                    .buttonStyle(.quiet)
                    .disabled(lookingAway)
                }
            }
        case .hands:
            prompt(symbol: "hand.raised.fingers.spread", title: "Look at your hands",
                   body: "Count your fingers. Study the lines and nails. In dreams, hands often look wrong.")
        case .breath:
            prompt(symbol: "nose", title: "Pinch your nose and breathe",
                   body: "Try to breathe in through your pinched nose. If air still flows, you're dreaming.")
        case .context:
            VStack(spacing: 18) {
                prompt(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "How did you get here?",
                       body: "Trace back the last few minutes. Dreams start mid-scene, with no way in.")
                if !topSigns.isEmpty {
                    VStack(spacing: 10) {
                        Text("Your dream signs")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                        FlowLayout {
                            ForEach(topSigns, id: \.self) { Chip(text: $0, symbol: "sparkle", tint: Palette.iris) }
                        }
                        Text("Whenever you meet one awake, do a check.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        case .done:
            VStack(spacing: 20) {
                prompt(symbol: "sun.max", title: "You're awake.",
                       body: "Next time something feels odd, you might not be. That's the habit you're building.")
                Text("\(total) checks so far")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                RemindersCard(reminders: reminders, signs: topSigns)
            }
        }
    }

    private func prompt(symbol: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Palette.iris)
                .symbolEffect(.pulse, options: .repeating.speed(0.4))
            Text(title)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var nextButton: some View {
        if step == .done {
            Button("Done") { dismiss() }
                .buttonStyle(.big(Palette.iris))
        } else {
            Button(step == .context ? "Finish check" : "Next") {
                if step == .context { total += 1 }
                if let next = Step(rawValue: step.rawValue + 1) { step = next }
            }
            .buttonStyle(.big(Palette.iris))
            .disabled(step == .text && !checkedText)
        }
    }

    static func randomPhrase() -> String {
        let words = ["Silver", "Lantern", "Harbor", "Velvet", "Orbit", "Maple", "Comet", "Tidal", "Cobalt", "Ember"]
        return "\(words.randomElement()!) \(words.randomElement()!) \(Int.random(in: 1000...9999))"
    }
}

private struct StepCapsules: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < current ? Palette.iris : index == current ? Palette.text : Palette.text.opacity(0.2))
                    .frame(width: index == current ? 24 : 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.4), value: current)
        .accessibilityHidden(true)
    }
}

private struct RemindersCard: View {
    let reminders: RealityCheckReminders
    let signs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { reminders.enabled }, set: { on in Task { await reminders.setEnabled(on, signs: signs) } })) {
                Label("Daytime reminders", systemImage: "bell")
                    .foregroundStyle(Palette.text)
            }
            .tint(Palette.iris)
            if reminders.enabled {
                Picker("Per day", selection: Binding(get: { reminders.perDay }, set: { count in Task { await reminders.setPerDay(count, signs: signs) } })) {
                    ForEach([3, 5, 8], id: \.self) { Text("\($0) a day").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Text("Gentle prompts between 10 AM and 9 PM, sometimes using your dream signs.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
        }
        .card()
    }
}

/// Repeating local notifications that prompt a reality check.
@MainActor
@Observable
final class RealityCheckReminders {
    static let shared = RealityCheckReminders()

    private(set) var enabled = UserDefaults.standard.bool(forKey: "realityChecks.reminders")
    private(set) var perDay = UserDefaults.standard.object(forKey: "realityChecks.perDay") as? Int ?? 5

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "reality-check-"

    func setEnabled(_ on: Bool, signs: [String]) async {
        if on {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            enabled = granted
        } else {
            enabled = false
        }
        UserDefaults.standard.set(enabled, forKey: "realityChecks.reminders")
        await reschedule(signs: signs)
    }

    func setPerDay(_ count: Int, signs: [String]) async {
        perDay = count
        UserDefaults.standard.set(count, forKey: "realityChecks.perDay")
        await reschedule(signs: signs)
    }

    private func reschedule(signs: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: (0..<12).map { identifierPrefix + "\($0)" })
        guard enabled else { return }
        let prompts = [
            String(localized: "Are you dreaming? Look at your hands."),
            String(localized: "Read something, look away, read it again."),
            String(localized: "Pinch your nose and try to breathe."),
            String(localized: "How did you get here? Trace back the last few minutes."),
            String(localized: "Anything odd around you? Ask: is this a dream?"),
        ] + signs.map { String(localized: "Seen \($0) today? Do a reality check.") }

        let start = 10 * 60, end = 21 * 60
        let spacing = (end - start) / perDay
        for index in 0..<perDay {
            let minutes = start + spacing * index + (spacing / 3) * (index % 3)
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Reality check")
            content.body = prompts[index % prompts.count]
            content.interruptionLevel = .passive
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: identifierPrefix + "\(index)", content: content, trigger: trigger))
        }
    }
}
