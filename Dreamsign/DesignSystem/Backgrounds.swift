import SwiftUI

/// App background: deep ink, a faint iris bloom from above, and a still star field.
struct NightBackground: View {
    var glow: Color = Palette.irisDeep
    var stars = true

    var body: some View {
        ZStack {
            Palette.ink
            RadialGradient(colors: [glow.opacity(0.26), glow.opacity(0.06), .clear],
                           center: UnitPoint(x: 0.5, y: -0.15), startRadius: 0, endRadius: 560)
            if stars { StarField().opacity(0.55) }
        }
        .ignoresSafeArea()
    }
}

/// A deterministic, motionless star field — calm, and identical every launch.
struct StarField: View {
    var count = 70
    var seed: UInt64 = 2026

    var body: some View {
        Canvas { context, size in
            var random = SeededRandomNumberGenerator(seed: seed)
            for _ in 0..<count {
                let x = Double.random(in: 0...1, using: &random) * size.width
                let y = pow(Double.random(in: 0...1, using: &random), 1.6) * size.height * 0.7
                let radius = Double.random(in: 0.5...1.4, using: &random)
                let alpha = Double.random(in: 0.15...0.7, using: &random)
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Palette.text.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Wake-flow sky. `progress` 0…1 carries it from night to sunrise as each challenge is done.
/// WBTB stays in the night.
struct DawnBackground: View {
    var progress: Double
    var stayNight = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let p = stayNight ? 0 : min(max(progress, 0), 1)
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors(p))
        }
        .overlay(StarField(count: 50).opacity(stayNight ? 0.6 : 0.6 * (1 - progress)))
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 2.4), value: progress)
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        let drift = Float(sin(t / 7) * 0.04)
        let sway = Float(cos(t / 9) * 0.05)
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.55 + drift], [0.5 + sway, 0.6 - drift], [1, 0.5 + drift],
            [0, 1], [0.5, 1], [1, 1],
        ]
    }

    private func colors(_ p: Double) -> [Color] {
        let top = Palette.ink
        let mid = mix(Color(hex: 0x15123A), Color(hex: 0x2A1F57), p)
        let low = mix(Color(hex: 0x1B1640), Color(hex: 0x8A4E6E), p)
        let horizon = mix(Color(hex: 0x241A47), Palette.dawnDeep, p)
        return [
            top, top, top,
            mid, mix(Palette.night, Color(hex: 0x3A2A66), p), mid,
            low, horizon, low,
        ]
    }

    private func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        a.mix(with: b, by: t)
    }
}

#Preview("Backgrounds") {
    TabView {
        NightBackground()
        DawnBackground(progress: 0)
        DawnBackground(progress: 0.5)
        DawnBackground(progress: 1)
    }
    .tabViewStyle(.page)
}
