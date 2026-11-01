import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    @Environment(AppModel.self) private var model
    @State private var requesting = false
    @State private var appeared = false

    private let points: [(symbol: String, title: String, detail: String)] = [
        ("alarm.waves.left.and.right.fill", String(localized: "Alarms that don't take no"),
         String(localized: "Rings through Silent and Focus, and keeps coming back until you've done your wake-up tasks.")),
        ("moon.stars.fill", String(localized: "Catch the dream"),
         String(localized: "Write it down while it's fresh. Keyboard mashing won't count.")),
        ("sparkles", String(localized: "Learn to know you're dreaming"),
         String(localized: "Spot your dream signs, and try wake-back-to-bed with MILD.")),
    ]

    var body: some View {
        ZStack {
            NightBackground()
            FoldAwareSplit(minimumSideWidth: 320) {
                brand
                    .frame(maxHeight: .infinity)
            } secondary: {
                ScrollView {
                    VStack(spacing: 32) {
                        pointsList
                        action
                    }
                    .padding(.vertical, 24)
                    .readableWidth(460)
                }
                .scrollBounceBehavior(.basedOnSize)
            } stacked: {
                ScrollView {
                    VStack(spacing: 40) {
                        brand
                        pointsList
                        action
                    }
                    .padding(.vertical, 32)
                    .readableWidth(520)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(.horizontal, 28)
        }
        .onAppear { appeared = true }
    }

    private var brand: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(LinearGradient(colors: [Palette.text, Palette.iris], startPoint: .top, endPoint: .bottom))
                .shadow(color: Palette.iris.opacity(0.6), radius: 24)
                .padding(.bottom, 14)
            Text("Dreamsign")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.text)
            Text("Wake up. Remember. Become lucid.")
                .font(.title3)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var pointsList: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: point.symbol)
                        .font(.title2)
                        .foregroundStyle(Palette.iris)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(point.title).font(.headline).foregroundStyle(Palette.text)
                        Text(point.detail).font(.subheadline).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.6).delay(0.15 * Double(index) + 0.2), value: appeared)
            }
        }
        .padding(.horizontal, 8)
    }

    private var action: some View {
        VStack(spacing: 14) {
            Button {
                requesting = true
                Task {
                    await model.coordinator.requestAuthorization()
                    requesting = false
                    onFinish()
                }
            } label: {
                if requesting { ProgressView().tint(Palette.ink) } else { Text("Allow alarms") }
            }
            .buttonStyle(.big)
            .disabled(requesting)

            Text("Everything stays on this iPhone. No accounts, no tracking.")
                .font(.footnote)
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    OnboardingView {}
        .environment(AppModel())
        .preferredColorScheme(.dark)
}
