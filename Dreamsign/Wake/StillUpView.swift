import SwiftUI

/// Places `count` targets in a unit square, spaced apart, away from the edges.
enum DotLayout {
    static func positions<R: RandomNumberGenerator>(count: Int, minimumDistance: Double = 0.34,
                                                    using random: inout R) -> [CGPoint] {
        var points: [CGPoint] = []
        var attempts = 0
        while points.count < count, attempts < 500 {
            attempts += 1
            let candidate = CGPoint(x: Double.random(in: 0.15...0.85, using: &random),
                                    y: Double.random(in: 0.15...0.85, using: &random))
            let distance = minimumDistance * (attempts > 300 ? 0.6 : 1)
            if points.allSatisfy({ hypot($0.x - candidate.x, $0.y - candidate.y) >= distance }) {
                points.append(candidate)
            }
        }
        while points.count < count {
            points.append(CGPoint(x: 0.2 + 0.3 * Double(points.count % 3), y: 0.5))
        }
        return points
    }
}

/// The wake-up check: tap three dots in order.
struct StillUpView: View {
    let occurrenceID: String
    var onActivity: () -> Void
    var onComplete: () -> Void

    @State private var points: [CGPoint]
    @State private var next = 0
    @State private var misses = 0
    @State private var done = false

    init(occurrenceID: String, onActivity: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.occurrenceID = occurrenceID
        self.onActivity = onActivity
        self.onComplete = onComplete
        let layout: [CGPoint]
        if Showcase.isActive {
            var random = SeededRandomNumberGenerator(seed: 9)
            layout = DotLayout.positions(count: 3, using: &random)
        } else {
            var random = SystemRandomNumberGenerator()
            layout = DotLayout.positions(count: 3, using: &random)
        }
        _points = State(initialValue: layout)
        _next = State(initialValue: Showcase.isActive ? 2 : 0)
    }

    var body: some View {
        FoldAvoiding(tabletop: .top) {
            VStack(spacing: 16) {
                ChallengeHeader(title: "Still up?", subtitle: "Tap the dots in order so we know you didn't drift back off.")
                GeometryReader { proxy in
                    ZStack {
                        ForEach(points.indices, id: \.self) { index in
                            dot(index)
                                .position(x: points[index].x * proxy.size.width, y: points[index].y * proxy.size.height)
                        }
                    }
                }
                .modifier(ShakeEffect(animatableData: CGFloat(misses)))
                .animation(.linear(duration: 0.4), value: misses)
                NextRingCountdown(occurrenceID: occurrenceID)
            }
            .readableWidth()
        }
        .sensoryFeedback(.error, trigger: misses)
        .sensoryFeedback(.success, trigger: done)
    }

    private func dot(_ index: Int) -> some View {
        let tapped = index < next
        return Button { tap(index) } label: {
            ZStack {
                Circle()
                    .fill(tapped ? Palette.mint : Palette.dawn.opacity(index == next ? 0.85 : 0.35))
                if tapped {
                    Image(systemName: "checkmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                } else {
                    Text("\(index + 1)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .frame(width: 76, height: 76)
            .overlay {
                if index == next {
                    Circle().strokeBorder(Palette.text.opacity(0.35), lineWidth: 2).padding(-10)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tapped ? Text("Dot \(index + 1), done") : Text("Dot \(index + 1)"))
    }

    private func tap(_ index: Int) {
        onActivity()
        guard !done else { return }
        guard index == next else {
            misses += 1
            next = 0
            return
        }
        withAnimation(.spring(duration: 0.3)) { next += 1 }
        guard next == points.count else { return }
        done = true
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            onComplete()
        }
    }
}

/// "Rings again in 1:42", from the chain's next pending ring.
struct NextRingCountdown: View {
    let occurrenceID: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let next = Showcase.isActive ? context.date.addingTimeInterval(42)
                : AlarmCoordinator.shared.nextRing(of: occurrenceID, after: context.date)
            if let next {
                let seconds = max(Int(next.timeIntervalSince(context.date)), 0)
                Label("Rings again in \(seconds / 60):\(String(format: "%02d", seconds % 60))", systemImage: "bell.fill")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }
}
