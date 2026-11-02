import CoreMotion
import SwiftUI

/// Streams user acceleration from CoreMotion into `ShakeDetector`.
@MainActor
@Observable
final class ShakeMonitor {
    private(set) var count = 0
    let isAvailable: Bool

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var detector: ShakeDetector

    init(initialCount: Int = 0, sensitivity: Double = ShakeDetector.defaultSensitivity) {
        detector = ShakeDetector(sensitivity: sensitivity)
        isAvailable = manager.isDeviceMotionAvailable || manager.isAccelerometerAvailable
        count = initialCount
    }

    func start() {
        if manager.isDeviceMotionAvailable {
            guard !manager.isDeviceMotionActive else { return }
            manager.deviceMotionUpdateInterval = 1.0 / 60.0
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion else { return }
                let a = motion.userAcceleration
                let magnitude = ShakeDetector.magnitude(x: a.x, y: a.y, z: a.z)
                let timestamp = motion.timestamp
                MainActor.assumeIsolated { self?.ingest(magnitude, at: timestamp) }
            }
        } else if manager.isAccelerometerAvailable {
            guard !manager.isAccelerometerActive else { return }
            manager.accelerometerUpdateInterval = 1.0 / 60.0
            manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                let a = data.acceleration
                // Raw accelerometer includes gravity (≈1 g at rest).
                let magnitude = abs(ShakeDetector.magnitude(x: a.x, y: a.y, z: a.z) - 1)
                let timestamp = data.timestamp
                MainActor.assumeIsolated { self?.ingest(magnitude, at: timestamp) }
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        manager.stopAccelerometerUpdates()
    }

    /// Simulator and accessibility fallback.
    func registerManualShake() {
        count += 1
    }

    private func ingest(_ magnitude: Double, at timestamp: TimeInterval) {
        if detector.process(magnitude: magnitude, at: timestamp) { count += 1 }
    }
}

struct ShakeChallengeView: View {
    let target: Int
    var sensitivity: Double = ShakeDetector.defaultSensitivity
    var onActivity: () -> Void
    var onComplete: () -> Void

    @State private var monitor: ShakeMonitor
    @State private var finished = false
    @State private var bump = false

    init(target: Int, sensitivity: Double = ShakeDetector.defaultSensitivity,
         onActivity: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.target = target
        self.sensitivity = sensitivity
        self.onActivity = onActivity
        self.onComplete = onComplete
        _monitor = State(initialValue: ShakeMonitor(initialCount: Showcase.isActive ? 34 : 0, sensitivity: sensitivity))
    }

    private var remaining: Int { max(target - monitor.count, 0) }
    private var progress: Double { Double(min(monitor.count, target)) / Double(max(target, 1)) }

    var body: some View {
        FoldAvoiding(tabletop: .top) {
            content
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: monitor.count)
        .sensoryFeedback(.success, trigger: finished)
        .onChange(of: monitor.count) { _, count in
            onActivity()
            withAnimation(.spring(duration: 0.12)) { bump = true }
            withAnimation(.spring(duration: 0.3).delay(0.1)) { bump = false }
            guard count >= target, !finished else { return }
            withAnimation(.spring(duration: 0.4)) { finished = true }
            monitor.stop()
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                onComplete()
            }
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private var content: some View {
        VStack(spacing: 24) {
            ChallengeHeader(title: "Shake it awake", subtitle: "Shake your phone, hard.")
            Spacer(minLength: 8)
            ZStack {
                ProgressRing(progress: progress, lineWidth: 18, tint: finished ? Palette.mint : Palette.dawn)
                VStack(spacing: 0) {
                    if finished {
                        Image(systemName: "checkmark")
                            .font(.system(size: 72, weight: .semibold))
                            .foregroundStyle(Palette.mint)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("\(remaining)")
                            .font(.clock(96, weight: .regular))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText(countsDown: true))
                            .foregroundStyle(Palette.text)
                        Text("to go")
                            .font(.title3)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .frame(maxWidth: 280, maxHeight: 280)
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 12)
            .scaleEffect(bump ? 1.035 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(finished ? Text("Done") : Text("\(remaining) shakes to go"))
            Spacer(minLength: 8)
            if showsManualButton {
                Button("Count a shake") { monitor.registerManualShake() }
                    .buttonStyle(.quiet)
            }
        }
        .readableWidth()
    }

    private var showsManualButton: Bool {
        #if targetEnvironment(simulator)
        return !Showcase.isActive
        #else
        return !monitor.isAvailable
        #endif
    }
}
