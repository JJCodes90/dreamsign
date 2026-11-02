import CoreMotion
import SwiftUI

/// Live step count from the motion coprocessor, starting at zero when the challenge opens.
@MainActor
@Observable
final class StepCounter {
    private(set) var steps = 0
    private(set) var isAvailable: Bool

    @ObservationIgnored private let pedometer = CMPedometer()

    init(initialSteps: Int = 0) {
        steps = initialSteps
        let status = CMPedometer.authorizationStatus()
        isAvailable = CMPedometer.isStepCountingAvailable() && status != .denied && status != .restricted
    }

    func start() {
        guard isAvailable, !Showcase.isActive else { return }
        pedometer.startUpdates(from: .now) { [weak self] data, error in
            let count = data?.numberOfSteps.intValue
            let failed = error != nil
            Task { @MainActor in
                guard let self else { return }
                if let count { self.steps = max(self.steps, count) }
                if failed, self.steps == 0, CMPedometer.authorizationStatus() == .denied { self.isAvailable = false }
            }
        }
    }

    func stop() {
        pedometer.stopUpdates()
    }
}

struct StepsChallengeView: View {
    let target: Int
    var onActivity: () -> Void
    var onComplete: () -> Void

    @State private var counter = StepCounter(initialSteps: Showcase.isActive ? 18 : 0)
    @State private var finished = false

    private var progress: Double { Double(min(counter.steps, target)) / Double(max(target, 1)) }
    private var remaining: Int { max(target - counter.steps, 0) }

    var body: some View {
        Group {
            if counter.isAvailable {
                FoldAvoiding(tabletop: .top) { content }
            } else {
                // No motion access (or no pedometer): shaking keeps the body-first idea.
                ShakeChallengeView(target: max(target, 30), onActivity: onActivity, onComplete: onComplete)
            }
        }
        .onAppear { counter.start() }
        .onDisappear { counter.stop() }
        .onChange(of: counter.steps) { _, steps in
            onActivity()
            guard steps >= target, !finished else { return }
            withAnimation(.spring(duration: 0.4)) { finished = true }
            counter.stop()
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                onComplete()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: counter.steps)
        .sensoryFeedback(.success, trigger: finished)
    }

    private var content: some View {
        VStack(spacing: 24) {
            ChallengeHeader(title: "Take a walk", subtitle: "Out of bed, phone in hand. Head for the kitchen.")
            Spacer(minLength: 8)
            ZStack {
                ProgressRing(progress: progress, lineWidth: 18, tint: finished ? Palette.mint : Palette.dawn)
                VStack(spacing: 2) {
                    if finished {
                        Image(systemName: "checkmark")
                            .font(.system(size: 72, weight: .semibold))
                            .foregroundStyle(Palette.mint)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "figure.walk")
                            .font(.title)
                            .foregroundStyle(Palette.dawn)
                            .symbolEffect(.bounce, value: counter.steps)
                        Text("\(remaining)")
                            .font(.clock(88, weight: .regular))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText(countsDown: true))
                            .foregroundStyle(Palette.text)
                        Text("steps to go")
                            .font(.title3)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .frame(maxWidth: 280, maxHeight: 280)
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(finished ? Text("Done") : Text("\(remaining) steps to go"))
            Spacer(minLength: 8)
            Text("Steps can take a few seconds to show up.")
                .font(.footnote)
                .foregroundStyle(Palette.textTertiary)
        }
        .readableWidth()
    }
}
