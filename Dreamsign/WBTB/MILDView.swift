import SwiftUI
import UIKit

/// Mnemonic Induction of Lucid Dreams (LaBerge): recall the dream, set the intention,
/// visualize becoming lucid in it — then fall asleep quickly.
struct MILDView: View {
    static let intention = String(localized: "Next time I'm dreaming, I'll recognize I'm dreaming.")
    static let phaseLength: TimeInterval = 20

    let minutes: Int
    let dreamText: String?
    var onFinish: () -> Void

    @State private var start = Date.now

    private var total: TimeInterval { TimeInterval(max(minutes, 1) * 60) }

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let phase = MILDPhase.allCases[Int(elapsed / Self.phaseLength) % MILDPhase.allCases.count]
            let remaining = max(total - elapsed, 0)

            VStack(spacing: 22) {
                Text(title(phase))
                    .font(.caption.weight(.bold))
                    .tracking(2.5)
                    .foregroundStyle(Palette.iris)
                    .padding(.top, 28)
                    .contentTransition(.opacity)

                Spacer(minLength: 8)

                BreathingOrb(progress: min(elapsed / total, 1))
                    .frame(width: 210, height: 210)

                VStack(spacing: 14) {
                    cue(phase)
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .top)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.8), value: phase)

                Spacer(minLength: 8)

                Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
                Button("I'm ready to sleep", action: finish)
                    .buttonStyle(.quiet)
            }
            .onChange(of: phase) { _, newPhase in SleepAudio.shared.mildPhaseChanged(to: newPhase) }
        }
        .task {
            SleepAudio.shared.beginMILDGuidance()
            try? await Task.sleep(for: .seconds(total))
            if !Task.isCancelled { finish() }
        }
    }

    private func finish() {
        onFinish()
    }

    private func title(_ phase: MILDPhase) -> LocalizedStringKey {
        switch phase {
        case .recall: "RECALL"
        case .intend: "INTEND"
        case .visualize: "VISUALIZE"
        }
    }

    @ViewBuilder
    private func cue(_ phase: MILDPhase) -> some View {
        switch phase {
        case .recall:
            Text("Replay the dream you just had, in as much detail as you can.")
                .font(.title3.weight(.medium))
                .foregroundStyle(Palette.text)
            if let dreamText, !dreamText.isEmpty {
                Text("“\(String(dreamText.prefix(140)))\(dreamText.count > 140 ? "…" : "")”")
                    .font(.body.italic())
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(4)
            }
        case .intend:
            Text(Self.intention)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text("Say it to yourself, slowly. Mean it.")
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
        case .visualize:
            Text("Picture yourself back in that dream. Notice something odd, and realize: this is a dream.")
                .font(.title3.weight(.medium))
                .foregroundStyle(Palette.text)
        }
    }
}

/// A slow breathing guide: ~5.5 s in, ~5.5 s out, ringed by the session's progress.
struct BreathingOrb: View {
    var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breath = reduceMotion ? 0.5 : 0.5 - 0.5 * cos(2 * .pi * t / 11)
            ZStack {
                ProgressRing(progress: progress, lineWidth: 3, tint: Palette.iris.opacity(0.7))
                Circle()
                    .fill(RadialGradient(colors: [Palette.iris.opacity(0.85), Palette.irisDeep.opacity(0.35), .clear],
                                         center: .center, startRadius: 4, endRadius: 100))
                    .scaleEffect(0.62 + 0.26 * breath)
                    .blur(radius: 2)
                    .shadow(color: Palette.iris.opacity(0.5), radius: 30)
            }
        }
        .accessibilityHidden(true)
    }
}

struct BackToSleepView: View {
    var onDone: () -> Void
    @State private var dimmed = false

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Palette.iris.opacity(0.75))
                Text("Back to sleep")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Palette.text.opacity(0.85))
                Text(MILDView.intention)
                    .font(.body.italic())
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.quiet)
            }
            Color.black
                .opacity(dimmed ? 0.7 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            SleepAudio.shared.beginSleepSoundscape()
            UIApplication.shared.isIdleTimerDisabled = false
            withAnimation(.easeInOut(duration: 10).delay(3)) { dimmed = true }
        }
        .onDisappear { SleepAudio.shared.stopAll() }
    }
}
