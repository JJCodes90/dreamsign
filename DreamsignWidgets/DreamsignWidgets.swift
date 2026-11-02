import AppIntents
import SwiftUI
import WidgetKit

@main
struct DreamsignWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
        TonightWidget()
        RealityCheckWidget()
        GoToBedControl()
        RecordDreamControl()
        RealityCheckControl()
    }
}

// MARK: - Look

enum WidgetPalette {
    static let ink = Color(red: 0.027, green: 0.031, blue: 0.059)
    static let surface = Color(red: 0.075, green: 0.086, blue: 0.157)
    static let text = Color(red: 0.933, green: 0.925, blue: 0.973)
    static let secondary = Color(red: 0.651, green: 0.643, blue: 0.753)
    static let iris = Color(red: 0.663, green: 0.612, blue: 1.0)
    static let dawn = Color(red: 1.0, green: 0.702, blue: 0.541)
    static let mint = Color(red: 0.494, green: 0.886, blue: 0.769)

    static let background = LinearGradient(colors: [Color(red: 0.165, green: 0.133, blue: 0.388), surface],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
    var realityChecks: Int = 0
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample, realityChecks: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = current()
        // Refresh after the alarm passes, and at least every few hours.
        var next = Date.now.addingTimeInterval(3 * 3600)
        if let alarm = entry.snapshot?.nextAlarm, alarm > .now { next = min(next, alarm.addingTimeInterval(60)) }
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func current() -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: SharedStore.snapshot, realityChecks: SharedStore.realityChecksToday())
    }
}

// MARK: - Next alarm

struct NextAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "next-alarm", provider: SnapshotProvider()) { entry in
            NextAlarmView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.background }
        }
        .configurationDisplayName("Next alarm")
        .description("Your next wake-up, how you'll turn it off, and when to be in bed.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextAlarmView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var alarm: Date? {
        guard let date = entry.snapshot?.nextAlarm, date > entry.date else { return nil }
        return date
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "alarm.fill").font(.caption)
                if let alarm {
                    Text(alarm, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.6)
                } else {
                    Text("—").font(.body.weight(.bold))
                }
            }
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let alarm {
                    Label {
                        Text(alarm, format: .dateTime.hour().minute())
                    } icon: {
                        Image(systemName: "alarm.fill")
                    }
                    .font(.headline)
                    .widgetAccentable()
                    Text(entry.snapshot?.nextAlarmLabel ?? "")
                        .font(.caption)
                    if let bedtime = entry.snapshot?.bedtime, bedtime > entry.date {
                        Text("Bed by \(bedtime.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                    }
                } else {
                    Label("No alarm set", systemImage: "alarm")
                        .font(.headline)
                    Text("Open Dreamsign").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            if let alarm {
                Label("\(alarm.formatted(date: .omitted, time: .shortened)) · \(entry.snapshot?.nextAlarmLabel ?? "")",
                      systemImage: "alarm.fill")
            } else {
                Label("No alarm", systemImage: "alarm")
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                Text("DREAMSIGN")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(WidgetPalette.iris)
                Spacer(minLength: 4)
                if let alarm {
                    Text(alarm, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetPalette.text)
                        .minimumScaleFactor(0.6)
                    Text((entry.snapshot?.nextAlarmChallenges ?? []).prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let bedtime = entry.snapshot?.bedtime, bedtime > entry.date {
                        Text("Bed by \(bedtime.formatted(date: .omitted, time: .shortened))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetPalette.dawn)
                    }
                } else {
                    Text("No alarm set")
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.text)
                    Text("Open Dreamsign to set one.")
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Tonight

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tonight", provider: SnapshotProvider()) { entry in
            TonightWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.background }
                .widgetURL(URL(string: "dreamsign://tonight"))
        }
        .configurationDisplayName("Tonight")
        .description("Tonight's dream sign, your lucid window, and your recall streak.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct TonightWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("\(entry.snapshot?.recallStreak ?? 0)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("streak").font(.caption2)
            }
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("TONIGHT'S SIGN").font(.caption2.weight(.semibold)).widgetAccentable()
                Text(entry.snapshot?.tonightSign ?? String(localized: "Anything strange"))
                    .font(.headline)
                    .lineLimit(1)
                if let window = entry.snapshot?.lucidWindow, window > entry.date {
                    Text("Lucid window \(window.formatted(date: .omitted, time: .shortened))").font(.caption)
                } else {
                    Text("Ask: am I dreaming?").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("Tonight", systemImage: "moon.stars.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(WidgetPalette.iris)
                Spacer(minLength: 2)
                Text(entry.snapshot?.tonightSign ?? String(localized: "Anything strange"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("is your dream sign")
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondary)
                Spacer(minLength: 2)
                HStack {
                    if let window = entry.snapshot?.lucidWindow, window > entry.date {
                        Label(window.formatted(date: .omitted, time: .shortened), systemImage: "moon.fill")
                    }
                    Spacer()
                    if let streak = entry.snapshot?.recallStreak, streak > 0 {
                        Label("\(streak)", systemImage: "flame.fill")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.dawn)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Reality check (interactive)

struct RealityCheckWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "reality-check", provider: SnapshotProvider()) { entry in
            RealityCheckWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.surface }
        }
        .configurationDisplayName("Reality check")
        .description("A prompt to ask if you're dreaming, with a button to log it.")
        .supportedFamilies([.systemSmall])
    }
}

struct RealityCheckWidgetView: View {
    let entry: SnapshotEntry

    private static let prompts: [LocalizedStringKey] = [
        "Look at your hands. Count your fingers.",
        "Read something, look away, read it again.",
        "How did you get here?",
        "Pinch your nose. Can you still breathe?",
    ]

    var body: some View {
        let hour = Calendar.current.component(.hour, from: entry.date)
        VStack(alignment: .leading, spacing: 6) {
            Text("REALITY CHECK")
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(WidgetPalette.mint)
            Text(Self.prompts[hour % Self.prompts.count])
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WidgetPalette.text)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            Button(intent: LogRealityCheckIntent()) {
                Text(entry.realityChecks > 0 ? "Done · \(entry.realityChecks) today" : "Done")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WidgetPalette.mint.opacity(0.3))
            .foregroundStyle(WidgetPalette.mint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Controls (Control Center, Lock Screen, Action button)

struct GoToBedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jjcodes.dreamsign.go-to-bed") {
            ControlWidgetButton(action: OpenTonightIntent()) {
                Label("Going to bed", systemImage: "moon.fill")
            }
        }
        .displayName("Going to bed")
        .description("Open Tonight and start your night.")
    }
}

struct RecordDreamControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jjcodes.dreamsign.record-dream") {
            ControlWidgetButton(action: RecordDreamIntent()) {
                Label("Record a dream", systemImage: "mic.fill")
            }
        }
        .displayName("Record a dream")
        .description("Start a voice journal entry.")
    }
}

struct RealityCheckControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jjcodes.dreamsign.reality-check") {
            ControlWidgetButton(action: RealityCheckIntent()) {
                Label("Reality check", systemImage: "hand.raised.fill")
            }
        }
        .displayName("Reality check")
        .description("Ask: am I dreaming?")
    }
}
