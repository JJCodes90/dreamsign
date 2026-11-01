import SwiftData
import SwiftUI
import UIKit

struct AlarmsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\WakeAlarm.hour), SortDescriptor(\WakeAlarm.minute)]) private var allAlarms: [WakeAlarm]

    @State private var editing: EditorTarget?
    @State private var showingWBTB = false
    @State private var showingSettings = false

    private var alarms: [WakeAlarm] { allAlarms.filter { $0.kind == .wake } }
    private var wbtb: WakeAlarm? { allAlarms.first { $0.kind == .wbtb } }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    NextAlarmHeader(alarms: allAlarms.filter(\.isEnabled))
                        .padding(.top, 4)
                        .padding(.bottom, 8)

                    if model.coordinator.authorization == .denied {
                        PermissionBanner()
                    }
                    if model.coordinator.chainWasTruncated {
                        Label("iOS limited how many follow-up rings could be scheduled. The soonest alarms are fully covered.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Palette.dawn)
                            .card(padding: 14, tint: Palette.dawn)
                    }

                    WBTBCard(plan: wbtb) { showingWBTB = true }

                    if alarms.isEmpty {
                        EmptyAlarms { editing = .new }
                    } else {
                        SectionHeader("Alarms").padding(.top, 10)
                        ForEach(alarms) { alarm in
                            AlarmCard(alarm: alarm) { toggled in
                                alarm.isEnabled = toggled
                                alarm.touch()
                                save()
                            }
                            .contentShape(.rect(cornerRadius: Metrics.corner))
                            .onTapGesture { editing = .existing(alarm) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { delete(alarm) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .contextMenu {
                                Button { editing = .existing(alarm) } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) { delete(alarm) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: Metrics.gutter, bottom: 6, trailing: Metrics.gutter))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NightBackground())
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add alarm")
                }
            }
            .sheet(item: $editing) { target in
                AlarmEditorView(alarm: target.alarm)
            }
            .sheet(isPresented: $showingWBTB) {
                WBTBSettingsView(plan: model.wbtbPlan(context))
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private func delete(_ alarm: WakeAlarm) {
        withAnimation {
            context.delete(alarm)
            save()
        }
    }

    private func save() {
        try? context.save()
        Task { await model.syncAlarms(context) }
    }
}

enum EditorTarget: Identifiable {
    case new
    case existing(WakeAlarm)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let alarm): alarm.id.uuidString
        }
    }

    var alarm: WakeAlarm? {
        if case .existing(let alarm) = self { return alarm }
        return nil
    }
}

// MARK: - Header

private struct NextAlarmHeader: View {
    let alarms: [WakeAlarm]

    var body: some View {
        TimelineView(.everyMinute) { context in
            let next = alarms
                .compactMap { alarm in
                    OccurrenceMath.next(alarm.time, weekdays: alarm.weekdays, after: context.date, calendar: .current)
                        .map { (alarm, $0) }
                }
                .min { $0.1 < $1.1 }

            VStack(alignment: .leading, spacing: 6) {
                if let next {
                    let alarm = next.0, date = next.1
                    Text(alarm.kind == .wbtb ? "Lucid window in" : "Next alarm in")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textSecondary)
                    Text(ClockFormat.countdown(to: date, from: context.date))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                    Text("\(date.formatted(.dateTime.weekday(.wide))) · \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    Text("No alarms on")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.text)
                    Text("Sleep in — or add one below.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Cards

private struct AlarmCard: View {
    let alarm: WakeAlarm
    var onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                ClockText(alarm.time, size: 54)
                    .foregroundStyle(Palette.text)
                Text("\(alarm.displayLabel) · \(alarm.weekdays.summary())")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(alarm.challenges) { challenge in
                        Chip(text: challenge.summary, symbol: challenge.kind.symbol, tint: Palette.dawn)
                    }
                }
            }
            Spacer(minLength: 0)
            Toggle("Enabled", isOn: Binding(get: { alarm.isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(Palette.iris)
        }
        .card()
        .opacity(alarm.isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.2), value: alarm.isEnabled)
    }
}

private struct WBTBCard: View {
    let plan: WakeAlarm?
    var onOpen: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var tonight: Occurrence?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Lucid window", systemImage: "moon.stars.fill")
                            .font(.headline)
                            .foregroundStyle(Palette.iris)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    if let plan, plan.isEnabled {
                        HStack(spacing: 10) {
                            timeColumn("Bed", plan.bedtime)
                            Image(systemName: "arrow.right").foregroundStyle(Palette.textTertiary)
                            timeColumn("Wake", plan.time)
                        }
                        Text(plan.wbtbNights.summary())
                            .font(.footnote)
                            .foregroundStyle(Palette.textTertiary)
                    } else if let tonight {
                        Text("Waking you at \(tonight.fireDate.formatted(date: .omitted, time: .shortened)) for a lucid window.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        Text("A gentle alarm a few hours after bed. Journal, set an intention, drift back into REM.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            HStack {
                if tonight != nil {
                    Button("Cancel tonight", role: .destructive) { cancelTonight() }
                        .buttonStyle(.quiet)
                } else {
                    Button { startTonight() } label: {
                        Label("Going to bed now", systemImage: "bed.double.fill")
                    }
                    .buttonStyle(.quiet)
                }
                Spacer()
            }
        }
        .card(tint: Palette.iris)
        .onAppear { tonight = model.coordinator.upcomingOneOff(for: plan?.id ?? UUID()) }
    }

    private func timeColumn(_ title: LocalizedStringKey, _ time: AlarmTime) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.textTertiary)
            ClockText(time, size: 30).foregroundStyle(Palette.text)
        }
    }

    private func startTonight() {
        let plan = plan ?? model.wbtbPlan(context)
        let fire = Date.now.addingTimeInterval(Double(plan.wbtbOffsetMinutes) * 60)
        Task {
            tonight = await model.coordinator.armOneOff(spec: plan.spec, at: fire, isTest: false)
        }
    }

    private func cancelTonight() {
        guard let plan else { return }
        Task {
            await model.coordinator.cancelOneOffs(for: plan.id)
            tonight = nil
        }
    }
}

private struct EmptyAlarms: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "alarm")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.dawn)
            Text("No alarms yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text("Set one, choose how you'll prove you're awake, and Dreamsign keeps ringing until you do.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add alarm", action: onAdd)
                .buttonStyle(.big)
                .padding(.top, 6)
        }
        .padding(.vertical, 12)
        .card()
    }
}

private struct PermissionBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Alarms are turned off for Dreamsign", systemImage: "alarm.waves.left.and.right")
                .font(.headline)
                .foregroundStyle(Palette.ember)
            Text("Nothing will ring until you allow alarms in Settings.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.quiet)
        }
        .card(tint: Palette.ember)
    }
}

#Preview {
    AlarmsView()
        .environment(AppModel())
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
