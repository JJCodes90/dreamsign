import AVFoundation
import SwiftUI
import UIKit

/// Plays the cue sound at a given volume (setup and training).
@MainActor
final class CuePreview {
    private var player: AVAudioPlayer?

    func play(volume: Double) {
        guard !Showcase.isActive, let url = Bundle.main.url(forResource: "Cue", withExtension: "wav") else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        if player == nil { player = try? AVAudioPlayer(contentsOf: url) }
        player?.volume = Float(volume)
        player?.currentTime = 0
        player?.play()
    }
}

/// Setup for lucidity cues: hear the sound, set a whisper volume, train the association.
struct CuesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var volume = CueSettings.volume
    @State private var trained = CueSettings.isTrained
    @State private var training = false
    @State private var preview = CuePreview()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Chip(text: String(localized: "Experimental"), symbol: "flask", tint: Palette.dawn)
                Text("Learn a soft sound before bed. Heard again in late-night REM, it can remind you that you're dreaming.")
                    .font(.title3)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    stepRow(number: 1, done: true, title: "Your cue", detail: "Glass chime · three notes") {
                        Button("Play") { preview.play(volume: max(volume, 0.35)) }
                            .buttonStyle(.borderless)
                    }
                    Divider().overlay(Palette.hairline)
                    VStack(alignment: .leading, spacing: 10) {
                        stepRow(number: 2, done: trained, title: "Set a whisper volume",
                                detail: "Phone volume where it'll be tonight, then slide down until you can barely hear it") {
                            Button("Test") { preview.play(volume: volume) }
                                .buttonStyle(.borderless)
                        }
                        Slider(value: $volume, in: 0.02...0.5, onEditingChanged: { editing in
                            if !editing { preview.play(volume: volume) }
                        })
                        .tint(Palette.iris)
                        .padding(.leading, 46)
                        .onChange(of: volume) { _, value in CueSettings.volume = value }
                    }
                    Divider().overlay(Palette.hairline)
                    stepRow(number: 3, done: trained, title: "Train it · 15 min",
                            detail: trained ? "Trained \(CueSettings.sessions)× · last \(CueSettings.lastTrained?.formatted(.relative(presentation: .named)) ?? "")"
                                            : "At bedtime: each time it chimes, do a reality check") {
                        EmptyView()
                    }
                }
                .card(padding: 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("How it works")
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                    Text("Tonight's cues play in short bursts during the last two hours before your alarm, when REM is longest, and go quiet for 10 minutes whenever you move. Train again every few nights to keep the link strong.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Based on targeted lucidity reactivation (Carr et al., 2020). In the lab, cues were timed with brain sensors; here they follow your schedule, so results vary.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
            .padding(Metrics.gutter)
            .readableWidth(620)
        }
        .safeAreaInset(edge: .bottom) {
            Button(trained ? "Train again" : "Start training") { training = true }
                .buttonStyle(.big(Palette.iris))
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 8)
                .readableWidth(520)
        }
        .background(NightBackground())
        .navigationTitle("Lucidity cues")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .close) { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $training, onDismiss: { trained = CueSettings.isTrained }) {
            CueTrainingView(volume: volume)
        }
    }

    private func stepRow<Accessory: View>(number: Int, done: Bool, title: LocalizedStringKey, detail: LocalizedStringKey,
                                          @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? Palette.mint : Palette.iris.opacity(0.18))
                if done {
                    Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Palette.ink)
                } else {
                    Text("\(number)").font(.footnote.weight(.bold)).foregroundStyle(Palette.iris)
                }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                Text(detail).font(.subheadline).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.vertical, 12)
    }
}

/// Fifteen minutes of pairing the cue with a lucid mindset: each chime, a reality check.
struct CueTrainingView: View {
    let volume: Double
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt = Date.now
    @State private var cues = 0
    @State private var prompt = 0
    @State private var preview = CuePreview()

    static let length: TimeInterval = 15 * 60

    private let prompts: [LocalizedStringKey] = [
        "Look at your hands. Do they look normal?",
        "Am I dreaming? Look around, then look again.",
        "Pinch your nose and try to breathe through it.",
        "How did you get here? Trace back the last few minutes.",
        "Notice your body, your breath, the room. Is this a dream?",
    ]

    var body: some View {
        ZStack {
            DawnBackground(progress: 0, stayNight: true)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                VStack(spacing: 24) {
                    Text("Each chime: a reality check")
                        .font(.headline)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, 40)
                    Spacer(minLength: 0)
                    ZStack {
                        ProgressRing(progress: elapsed / Self.length, lineWidth: 10, tint: Palette.iris)
                        VStack(spacing: 10) {
                            Image(systemName: "bell.and.waves.left.and.right")
                                .font(.system(size: 34))
                                .foregroundStyle(Palette.iris)
                                .symbolEffect(.bounce, value: cues)
                            Text(prompts[prompt % prompts.count])
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.text)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                                .contentTransition(.opacity)
                        }
                    }
                    .frame(maxWidth: 320, maxHeight: 320)
                    .aspectRatio(1, contentMode: .fit)
                    Text("\(cues) cues · \(Int(max(Self.length - elapsed, 0) / 60)) min left")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                    Button(elapsed >= Self.length ? "Done" : "Finish early") { finish() }
                        .buttonStyle(.quiet)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, Metrics.gutter)
            }
        }
        .task { await run() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func run() async {
        guard !Showcase.isActive else { return }
        try? await Task.sleep(for: .seconds(4))
        while !Task.isCancelled, Date.now.timeIntervalSince(startedAt) < Self.length {
            preview.play(volume: volume)
            withAnimation(.easeInOut(duration: 0.4)) {
                cues += 1
                prompt += 1
            }
            try? await Task.sleep(for: .seconds(Double.random(in: 40...80)))
        }
    }

    private func finish() {
        if cues >= 5 || Date.now.timeIntervalSince(startedAt) >= Self.length {
            CueSettings.lastTrained = .now
            CueSettings.sessions += 1
        }
        dismiss()
    }
}
