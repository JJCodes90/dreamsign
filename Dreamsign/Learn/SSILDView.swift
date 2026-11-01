import SwiftUI

/// Senses Initiated Lucid Dream: a few quick cycles through sight, sound and touch, then a few
/// slow ones, then let go. Fold-aware: senses on one side, instruction on the other.
struct SSILDView: View {
    var onFinish: () -> Void

    struct Beat: Equatable {
        let sense: SSILDSense
        let slow: Bool
        let cycle: Int
        let duration: TimeInterval
    }

    static let quickCycles = 4
    static let slowCycles = 3
    static let plan: [Beat] = {
        var beats: [Beat] = []
        for cycle in 1...quickCycles {
            beats += SSILDSense.allCases.map { Beat(sense: $0, slow: false, cycle: cycle, duration: 5) }
        }
        for cycle in 1...slowCycles {
            beats += SSILDSense.allCases.map { Beat(sense: $0, slow: true, cycle: cycle, duration: 30) }
        }
        return beats
    }()
    static let total = plan.reduce(0) { $0 + $1.duration }

    @State private var start = Date.now
    @State private var finished = false

    var body: some View {
        TimelineView(.periodic(from: start, by: 0.5)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let current = Self.beat(at: elapsed)
            let beat = current.beat
            let index = current.index

            FoldAwareSplit {
                VStack(spacing: 26) {
                    Text(beat.slow ? "SLOW CYCLE \(beat.cycle) OF \(Self.slowCycles)" : "QUICK CYCLE \(beat.cycle) OF \(Self.quickCycles)")
                        .font(.caption.weight(.bold))
                        .tracking(2.5)
                        .foregroundStyle(Palette.iris)
                        .padding(.top, 28)
                        .contentTransition(.opacity)
                    Spacer(minLength: 8)
                    senses(active: finished ? nil : beat.sense)
                    Spacer(minLength: 8)
                }
            } secondary: {
                VStack(spacing: 18) {
                    Spacer(minLength: 8)
                    instruction(finished ? nil : beat)
                    Spacer(minLength: 8)
                    footer(elapsed)
                }
                .readableWidth(460)
            } stacked: {
                VStack(spacing: 22) {
                    Text(beat.slow ? "SLOW CYCLE \(beat.cycle) OF \(Self.slowCycles)" : "QUICK CYCLE \(beat.cycle) OF \(Self.quickCycles)")
                        .font(.caption.weight(.bold))
                        .tracking(2.5)
                        .foregroundStyle(Palette.iris)
                        .padding(.top, 28)
                    Spacer(minLength: 8)
                    senses(active: finished ? nil : beat.sense)
                    instruction(finished ? nil : beat)
                    Spacer(minLength: 8)
                    footer(elapsed)
                }
            }
            .onChange(of: index) { _, _ in
                if !finished { SleepAudio.shared.ssildCue(beat.sense, slow: beat.slow) }
            }
            .animation(.easeInOut(duration: 0.6), value: index)
        }
        .task {
            TechniqueLog.record(.ssild)
            SleepAudio.shared.beginSSILDGuidance()
            try? await Task.sleep(for: .seconds(Self.total))
            guard !Task.isCancelled else { return }
            withAnimation { finished = true }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { onFinish() }
        }
    }

    static func beat(at elapsed: TimeInterval) -> (index: Int, beat: Beat) {
        var time: TimeInterval = 0
        for (index, beat) in plan.enumerated() {
            time += beat.duration
            if elapsed < time { return (index, beat) }
        }
        return (plan.count - 1, plan[plan.count - 1])
    }

    private func senses(active: SSILDSense?) -> some View {
        HStack(spacing: 22) {
            ForEach(SSILDSense.allCases, id: \.self) { sense in
                let isActive = sense == active
                VStack(spacing: 10) {
                    Image(systemName: sense.symbol)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(isActive ? Palette.ink : Palette.iris.opacity(0.7))
                        .frame(width: 78, height: 78)
                        .background(Circle().fill(isActive ? Palette.iris : Palette.iris.opacity(0.1)))
                        .shadow(color: isActive ? Palette.iris.opacity(0.6) : .clear, radius: 24)
                        .scaleEffect(isActive ? 1.08 : 1)
                    Text(sense.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isActive ? Palette.text : Palette.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func instruction(_ beat: Beat?) -> some View {
        if let beat {
            Text(beat.slow ? beat.sense.slowPrompt : beat.sense.quickPrompt)
                .font(.title3.weight(.medium))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .frame(minHeight: 90, alignment: .top)
                .contentTransition(.opacity)
        } else {
            VStack(spacing: 8) {
                Text("Now let go.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.text)
                Text("Fall asleep the way you normally would.")
                    .font(.body)
                    .foregroundStyle(Palette.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(minHeight: 90, alignment: .top)
        }
    }

    private func footer(_ elapsed: TimeInterval) -> some View {
        VStack(spacing: 12) {
            GoalBar(progress: min(elapsed / Self.total, 1), tint: Palette.iris, marksCompletion: false)
                .frame(maxWidth: 260)
            Button("I'm drifting off", action: onFinish)
                .buttonStyle(.quiet)
        }
    }
}

extension SSILDSense {
    var symbol: String {
        switch self {
        case .sight: "eye"
        case .sound: "ear"
        case .touch: "hand.raised"
        }
    }

    var title: String {
        switch self {
        case .sight: String(localized: "Sight")
        case .sound: String(localized: "Sound")
        case .touch: String(localized: "Touch")
        }
    }

    var quickPrompt: String {
        switch self {
        case .sight: String(localized: "Eyes closed. The darkness.")
        case .sound: String(localized: "What can you hear?")
        case .touch: String(localized: "Feel your body.")
        }
    }

    var slowPrompt: String {
        switch self {
        case .sight: String(localized: "Notice the darkness behind your eyelids — colors, patterns, or nothing at all.")
        case .sound: String(localized: "Listen to whatever is there: the room, your breath, the hum of silence.")
        case .touch: String(localized: "Feel your weight, the warmth, any tingling or unusual sensations.")
        }
    }
}
