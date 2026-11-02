import SwiftData
import SwiftUI
import UIKit

/// A bedside display. Best on iPhone Duo standing like a laptop on the nightstand: a dim,
/// warm clock on the upper half, bedtime controls on the lower half. Tap to dim further.
struct NightstandView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var alarms: [WakeAlarm]
    @State private var dimmed = false
    @State private var tonight: Occurrence?
    @State private var night = NightSession.shared

    /// Warm, dim light at night is easier on sleepiness than bright blue-white.
    private let glow = Color(hex: 0xFF8A6B)

    private var nextAlarm: (alarm: WakeAlarm, date: Date)? {
        alarms.filter(\.isEnabled)
            .compactMap { alarm in
                OccurrenceMath.next(alarm.time, weekdays: alarm.weekdays, after: .now, calendar: .current).map { (alarm, $0) }
            }
            .min { $0.1 < $1.1 }
    }

    private var wbtbPlan: WakeAlarm? { alarms.first { $0.kind == .wbtb } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            FoldAwareSplit {
                clock
            } secondary: {
                controls
            }
            .opacity(dimmed ? 0.45 : 1)
        }
        .contentShape(.rect)
        .onTapGesture { withAnimation(.easeInOut(duration: 0.6)) { dimmed.toggle() } }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            // Stay on only while charging; otherwise let the phone sleep as usual.
            UIApplication.shared.isIdleTimerDisabled = [.charging, .full].contains(UIDevice.current.batteryState)
            tonight = wbtbPlan.flatMap { model.coordinator.upcomingOneOff(for: $0.id) }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                ClockText(date: context.date, size: 104)
                    .foregroundStyle(glow.opacity(0.85))
                    .minimumScaleFactor(0.5)
                Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.title3)
                    .foregroundStyle(glow.opacity(0.45))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if let next = nextAlarm {
                Label {
                    Text("\(next.alarm.displayLabel) · \(next.date.formatted(date: .omitted, time: .shortened)) · in \(ClockFormat.countdown(to: next.date))")
                } icon: {
                    Image(systemName: next.alarm.kind == .wbtb ? "moon.stars.fill" : "alarm.fill")
                }
                .font(.headline)
                .foregroundStyle(glow.opacity(0.7))
            } else {
                Text("No alarm set")
                    .font(.headline)
                    .foregroundStyle(glow.opacity(0.5))
            }

            if let plan = night.plan {
                HStack(spacing: 14) {
                    Label(nightSummary(plan), systemImage: plan.soundscape == .off ? "bell.and.waves.left.and.right" : plan.soundscape.symbol)
                        .font(.subheadline)
                        .foregroundStyle(glow.opacity(0.6))
                    Button("Stop") { night.stop() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(glow.opacity(0.8))
                }
            }

            if let plan = wbtbPlan {
                if let tonight {
                    Button {
                        Task {
                            await model.coordinator.cancelOneOffs(for: plan.id)
                            self.tonight = nil
                        }
                    } label: {
                        Label("Lucid window at \(tonight.fireDate.formatted(date: .omitted, time: .shortened)) · Cancel", systemImage: "moon.stars")
                    }
                    .buttonStyle(NightButtonStyle(glow: glow))
                } else {
                    Button {
                        let fire = Date.now.addingTimeInterval(Double(plan.wbtbOffsetMinutes) * 60)
                        Task { tonight = await model.coordinator.armOneOff(spec: plan.spec, at: fire, isTest: false) }
                    } label: {
                        Label("Going to bed now", systemImage: "bed.double.fill")
                    }
                    .buttonStyle(NightButtonStyle(glow: glow))
                }
            }

            Button("Close") { dismiss() }
                .buttonStyle(NightButtonStyle(glow: glow, quiet: true))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.gutter)
    }
}

extension NightstandView {
    fileprivate func nightSummary(_ plan: NightPlan) -> String {
        var parts: [String] = []
        if plan.soundscape != .off {
            if let rise = plan.riseInto {
                parts.append(String(localized: "\(plan.soundscape.title) · rises into \(rise.formatted(date: .omitted, time: .shortened))"))
            } else if plan.sleepTimerMinutes > 0 {
                parts.append(String(localized: "\(plan.soundscape.title) · \(plan.sleepTimerMinutes) min"))
            } else {
                parts.append(plan.soundscape.title)
            }
        }
        if let cues = plan.cues {
            parts.append(String(localized: "cues from \(cues.start.formatted(date: .omitted, time: .shortened))"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Low-glare buttons for a dark bedroom.
private struct NightButtonStyle: ButtonStyle {
    var glow: Color
    var quiet = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(glow.opacity(quiet ? 0.5 : 0.85))
            .padding(.horizontal, 22)
            .frame(minHeight: 54)
            .background(Capsule().strokeBorder(glow.opacity(quiet ? 0.2 : 0.4), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
    }
}
