import SwiftUI

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = Metrics.gutter
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                    .fill(Palette.surface)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                                .fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.02)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                    .strokeBorder(tint?.opacity(0.22) ?? Palette.hairline, lineWidth: 1)
            }
    }
}

extension View {
    func card(padding: CGFloat = Metrics.gutter, tint: Color? = nil) -> some View {
        modifier(CardModifier(padding: padding, tint: tint))
    }
}

// MARK: - Buttons

/// The one big action on a screen. Solid, warm, impossible to miss at 6 AM.
struct BigButtonStyle: ButtonStyle {
    var tint: Color = Palette.dawn
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(isEnabled ? Palette.ink : Palette.textTertiary)
            .frame(maxWidth: .infinity, minHeight: Metrics.bigTap)
            .background {
                Capsule().fill(isEnabled
                               ? AnyShapeStyle(LinearGradient(colors: [tint, tint.mix(with: .white, by: 0.12)],
                                                              startPoint: .bottom, endPoint: .top))
                               : AnyShapeStyle(Palette.surfaceRaised))
            }
            .shadow(color: isEnabled ? tint.opacity(0.35) : .clear, radius: 18, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Quiet secondary action on glass.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 20)
            .frame(minHeight: 50)
            .glassEffect(.regular.interactive(), in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == BigButtonStyle {
    static var big: BigButtonStyle { BigButtonStyle() }
    static func big(_ tint: Color) -> BigButtonStyle { BigButtonStyle(tint: tint) }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

// MARK: - Progress

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 14
    var tint: Color = Palette.dawn

    var body: some View {
        ZStack {
            Circle().stroke(Palette.text.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(AngularGradient(colors: [tint.opacity(0.55), tint], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(progress, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.4), radius: 10)
        }
        .animation(.spring(duration: 0.35), value: progress)
        .accessibilityElement()
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// Thin bar that fills toward a goal and turns mint when it's met.
struct GoalBar: View {
    var progress: Double
    var tint: Color = Palette.dawn
    var marksCompletion = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.text.opacity(0.08))
                Capsule()
                    .fill(marksCompletion && progress >= 1 ? Palette.mint : tint)
                    .frame(width: max(proxy.size.width * min(progress, 1), progress > 0 ? 8 : 0))
            }
        }
        .frame(height: 6)
        .animation(.spring(duration: 0.4), value: progress)
    }
}

// MARK: - Bits

struct SectionHeader: View {
    var title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct Chip: View {
    var text: String
    var symbol: String?
    var tint: Color = Palette.iris

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.semibold)) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.13), in: Capsule())
    }
}

/// Seven round day toggles in the calendar's order.
struct DayPicker: View {
    @Binding var selection: WeekdaySet
    var tint: Color = Palette.iris
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WeekdaySet.displayOrder(for: calendar), id: \.self) { weekday in
                let day = WeekdaySet(calendarWeekday: weekday)
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.callout.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(isOn ? Palette.ink : Palette.textSecondary)
                        .background(Circle().fill(isOn ? tint : Palette.surfaceRaised))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(calendar.standaloneWeekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Large clock face "7:00 AM" with a smaller period.
struct ClockText: View {
    var main: String
    var period: String?
    var size: CGFloat = 54

    init(_ time: AlarmTime, size: CGFloat = 54) {
        self.init(date: time.date(), size: size)
    }

    init(date: Date, size: CGFloat = 54) {
        let parts = ClockFormat.parts(date)
        main = parts.main
        period = parts.period
        self.size = size
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(main)
                .font(.clock(size))
                .monospacedDigit()
            if let period {
                Text(period)
                    .font(.system(size: size * 0.34, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
