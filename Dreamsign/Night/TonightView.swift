import SwiftData
import SwiftUI

/// The evening hub: when to sleep for whole cycles, what plays, tonight's intention, and one
/// button to start the night.
struct TonightView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var alarms: [WakeAlarm]
    @Query private var signs: [DreamSign]
    @State private var night = NightSession.shared
    @State private var soundscape = NightPreferences.soundscape
    @State private var timer = NightPreferences.sleepTimerMinutes
    @State private var cues = NightPreferences.cuesTonight && CueSettings.isTrained
    @State private var lucidWindow = NightPreferences.lucidWindowTonight
    @State private var intention = NightPreferences.intentionSign
    @State private var showingNightstand = false
    @State private var settingUpCues = false
    @State private var tonightWindow: Occurrence?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let wake = nextWake {
                        bedtimeCard(wake)
                        nightCard(wake)
                    } else {
                        noAlarmCard
                    }
                    soundCard
                    intentionCard
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
                .readableWidth(640)
            }
            .safeAreaInset(edge: .bottom) { goButton }
            .scrollContentBackground(.hidden)
            .background(NightBackground())
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showingNightstand) { NightstandView() }
            .sheet(isPresented: $settingUpCues, onDismiss: { cues = CueSettings.isTrained && cues }) {
                NavigationStack { CuesView() }
            }
            .onAppear { tonightWindow = wbtbPlan.flatMap { model.coordinator.upcomingOneOff(for: $0.id) } }
        }
    }

    // MARK: Data

    /// The first wake alarm in the next 20 hours: tomorrow morning's.
    private var nextWake: (alarm: WakeAlarm, date: Date)? {
        let limit = Showcase.isActive ? Date.distantFuture : Date.now.addingTimeInterval(20 * 3600)
        return alarms.filter { $0.isEnabled && $0.kind == .wake }
            .compactMap { alarm in
                OccurrenceMath.next(alarm.time, weekdays: alarm.weekdays, after: .now, calendar: .current).map { (alarm, $0) }
            }
            .filter { $0.1 <= limit }
            .min { $0.1 < $1.1 }
    }

    private var wbtbPlan: WakeAlarm? { alarms.first { $0.kind == .wbtb } }

    /// A scheduled lucid window in the next 12 hours, if the regular plan covers tonight.
    private var scheduledWindow: Date? {
        guard let plan = wbtbPlan, plan.isEnabled,
              let next = OccurrenceMath.next(plan.time, weekdays: plan.weekdays, after: .now, calendar: .current),
              next.timeIntervalSinceNow < 12 * 3600
        else { return nil }
        return next
    }

    private var topSigns: [DreamSign] {
        signs.filter { !$0.entries.isEmpty }
            .sorted { ($0.entries.count, $1.name) > ($1.entries.count, $0.name) }
            .prefix(4)
            .map { $0 }
    }

    private var chosenSign: DreamSign? {
        topSigns.first { $0.key == intention } ?? topSigns.first
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Date.now.formatted(.dateTime.weekday(.wide))) night")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                Text("Tonight")
                    .font(.screenTitle)
                    .foregroundStyle(Palette.text)
            }
            Spacer()
            if let wake = nextWake {
                Text("Up at \(wake.date.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.top, 12)
    }

    private func bedtimeCard(_ wake: (alarm: WakeAlarm, date: Date)) -> some View {
        let options = SleepPlan.options(forWake: wake.alarm.time)
        let best = SleepPlan.closestOption(forWake: wake.alarm.time, goalMinutes: wake.alarm.sleepGoalMinutes)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Go to bed by"))
            HStack(spacing: 8) {
                ForEach(options) { option in
                    let selected = option.cycles == best.cycles
                    Button {
                        wake.alarm.sleepGoalMinutes = option.sleepMinutes
                        try? context.save()
                        Task { await model.syncAlarms(context) }
                    } label: {
                        VStack(spacing: 2) {
                            Text(ClockFormat.string(option.bedtime))
                                .font(.title3.weight(selected ? .bold : .semibold).monospacedDigit())
                                .foregroundStyle(selected ? Palette.iris : Palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("\(option.cycles) cycles · \(SleepPlan.goalTitle(option.sleepMinutes))")
                                .font(.caption)
                                .foregroundStyle(selected ? Palette.iris : Palette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(selected ? Palette.iris.opacity(0.16) : Palette.surfaceRaised,
                                    in: .rect(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(selected ? Palette.iris : .clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("Includes 15 minutes to fall asleep. Waking between cycles tends to feel lighter.")
                .font(.footnote)
                .foregroundStyle(Palette.textTertiary)
        }
        .card()
        .sensoryFeedback(.selection, trigger: wake.alarm.sleepGoalMinutes)
    }

    private func nightCard(_ wake: (alarm: WakeAlarm, date: Date)) -> some View {
        let option = SleepPlan.closestOption(forWake: wake.alarm.time, goalMinutes: wake.alarm.sleepGoalMinutes)
        let bedtime = wake.date.addingTimeInterval(-Double(option.sleepMinutes + SleepPlan.latencyMinutes) * 60)
        let lucidAt = scheduledWindow ?? tonightWindow?.fireDate
            ?? (lucidWindow ? Date.now.addingTimeInterval(Double(wbtbPlan?.wbtbOffsetMinutes ?? 300) * 60) : nil)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Your night"))
            NightTimeline(bedtime: bedtime, wake: wake.date, lucidAt: lucidAt,
                          cues: cues ? CuePlan.window(beforeWake: wake.date) : nil)
                .frame(height: 96)
            if let scheduledWindow {
                Label("Lucid window at \(scheduledWindow.formatted(date: .omitted, time: .shortened))", systemImage: "moon.stars.fill")
                    .font(.subheadline)
                    .foregroundStyle(Palette.dawn)
            } else if let tonightWindow {
                Label("Lucid window at \(tonightWindow.fireDate.formatted(date: .omitted, time: .shortened))", systemImage: "moon.stars.fill")
                    .font(.subheadline)
                    .foregroundStyle(Palette.dawn)
            } else {
                Toggle(isOn: $lucidWindow) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lucid window").foregroundStyle(Palette.text)
                        Text("Wake gently about 5 hours in, for MILD or SSILD")
                            .font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                }
                .tint(Palette.iris)
                .onChange(of: lucidWindow) { _, on in NightPreferences.lucidWindowTonight = on }
            }
            Divider().overlay(Palette.hairline)
            if CueSettings.isTrained {
                Toggle(isOn: $cues) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Lucidity cues").foregroundStyle(Palette.text)
                            Chip(text: String(localized: "Experimental"), tint: Palette.dawn)
                        }
                        let window = CuePlan.window(beforeWake: wake.date)
                        Text("\(window.start.formatted(date: .omitted, time: .shortened)) – \(window.end.formatted(date: .omitted, time: .shortened)), at a whisper")
                            .font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                }
                .tint(Palette.iris)
                .onChange(of: cues) { _, on in NightPreferences.cuesTonight = on }
            } else {
                Button { settingUpCues = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set up lucidity cues").foregroundStyle(Palette.text)
                            Text("A soft sound that can remind you you're dreaming")
                                .font(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.textTertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var noAlarmCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No alarm for the morning", systemImage: "alarm")
                .font(.headline)
                .foregroundStyle(Palette.text)
            Text("Set one to plan your bedtime around full sleep cycles.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            Button("Go to Alarms") { model.tab = .alarms }
                .buttonStyle(.quiet)
        }
        .card()
    }

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Sleep sounds"))
            HStack(spacing: 8) {
                ForEach(Soundscape.allCases) { kind in
                    let selected = soundscape == kind
                    Button {
                        soundscape = kind
                        NightPreferences.soundscape = kind
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.symbol).font(.title3)
                            Text(kind.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(selected ? Palette.ink : Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(selected ? Palette.iris : Palette.surfaceRaised, in: .rect(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if soundscape != .off {
                if let wake = nextWake {
                    Toggle(isOn: Binding(get: { wake.alarm.sleepSounds }, set: { on in
                        wake.alarm.sleepSounds = on
                        try? context.save()
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rise into my alarm").foregroundStyle(Palette.text)
                            Text("Plays all night, then softly rises into \(wake.date.formatted(date: .omitted, time: .shortened))")
                                .font(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .tint(Palette.iris)
                }
                if !(nextWake?.alarm.sleepSounds ?? false) {
                    Picker("Fade out after", selection: $timer) {
                        ForEach(NightPreferences.timerOptions, id: \.self) { Text(NightPreferences.timerTitle($0)).tag($0) }
                    }
                    .tint(Palette.iris)
                    .onChange(of: timer) { _, value in NightPreferences.sleepTimerMinutes = value }
                }
            }
        }
        .card()
        .sensoryFeedback(.selection, trigger: soundscape)
    }

    private var intentionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Tonight's intention"))
            Text(Self.intention(for: chosenSign))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if !topSigns.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(topSigns) { sign in
                        let selected = sign.key == chosenSign?.key
                        Button {
                            intention = sign.key
                            NightPreferences.intentionSign = sign.key
                        } label: {
                            Text("\(sign.name) · \(sign.entries.count)×")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selected ? Palette.iris : Palette.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selected ? Palette.iris.opacity(0.16) : Palette.surfaceRaised, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Tag dream signs in your journal and your most common one shows up here.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .card(tint: Palette.iris)
    }

    @ViewBuilder
    private var goButton: some View {
        Group {
            if night.isRunning {
                HStack(spacing: 12) {
                    Button("Stop sounds") { night.stop() }
                        .buttonStyle(.quiet)
                    Button { showingNightstand = true } label: {
                        Label("Nightstand", systemImage: "bed.double.fill")
                    }
                    .buttonStyle(.big(Palette.iris))
                }
            } else {
                Button { Task { await goToBed() } } label: {
                    Label("I'm going to bed", systemImage: "moon.fill")
                }
                .buttonStyle(.big(Palette.iris))
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 8)
        .readableWidth(520)
    }

    // MARK: Actions

    static func intention(for sign: DreamSign?) -> String {
        guard let sign else { return String(localized: "Next time something feels strange, I'll realize I'm dreaming.") }
        switch sign.category {
        case .person: return String(localized: "Next time I see \(sign.name), I'll realize I'm dreaming.")
        case .place: return String(localized: "Next time I'm back at \(sign.name.lowercased()), I'll realize I'm dreaming.")
        case .theme: return String(localized: "Next time I notice \(sign.name.lowercased()), I'll realize I'm dreaming.")
        }
    }

    private func goToBed() async {
        let wake = nextWake
        if lucidWindow, scheduledWindow == nil, tonightWindow == nil {
            let plan = wbtbPlan ?? model.wbtbPlan(context)
            let fire = Date.now.addingTimeInterval(Double(plan.wbtbOffsetMinutes) * 60)
            tonightWindow = await model.coordinator.armOneOff(spec: plan.spec, at: fire, isTest: false)
        }
        var cuePlan: CuePlan?
        if cues, let wake {
            let window = CuePlan.window(beforeWake: wake.date)
            cuePlan = CuePlan(start: window.start, end: window.end, volume: CueSettings.volume)
        }
        let rises = (wake?.alarm.sleepSounds ?? false) && soundscape != .off
        let plan = NightPlan(soundscape: soundscape, sleepTimerMinutes: rises ? 0 : timer,
                             riseInto: rises ? wake?.date : nil, cues: cuePlan)
        if plan.soundscape != .off || plan.cues != nil || plan.riseInto != nil {
            night.start(plan)
        }
        UserDefaults.standard.set(Date.now, forKey: "night.lastBedtime")
        showingNightstand = true
    }
}

/// A sketch of the night: sleep cycles getting lighter toward morning, with the lucid window
/// and cue window marked.
struct NightTimeline: View {
    let bedtime: Date
    let wake: Date
    var lucidAt: Date?
    var cues: (start: Date, end: Date)?

    var body: some View {
        Canvas { context, size in
            let start = min(bedtime, wake.addingTimeInterval(-3600))
            let total = max(wake.timeIntervalSince(start), 1)
            func x(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(start) / total) * size.width }
            let top: CGFloat = 8, bottom = size.height - 24

            if let cues {
                let rect = CGRect(x: x(cues.start), y: top, width: max(x(cues.end) - x(cues.start), 2), height: bottom - top)
                context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(Palette.iris.opacity(0.12)))
            }
            if let lucidAt, lucidAt > start, lucidAt < wake {
                let rect = CGRect(x: x(lucidAt) - 14, y: top - 4, width: 28, height: bottom - top + 8)
                context.fill(Path(roundedRect: rect, cornerRadius: 10), with: .color(Palette.dawn.opacity(0.18)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 10), with: .color(Palette.dawn.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // Cycles: deep early in the night, mostly light and REM toward morning.
            var path = Path()
            let cycles = max(Int((total / 5400).rounded()), 1)
            let steps = 120
            for index in 0...steps {
                let t = Double(index) / Double(steps)
                let phase = t * Double(cycles) * 2 * .pi
                let depth = (1 - cos(phase)) / 2 * (1 - 0.65 * t)
                let point = CGPoint(x: CGFloat(t) * size.width, y: top + CGFloat(depth) * (bottom - top))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(Palette.textTertiary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: -4, y: top - 4, width: 9, height: 9)), with: .color(Palette.iris))
            context.fill(Path(ellipseIn: CGRect(x: size.width - 5, y: top - 4, width: 9, height: 9)), with: .color(Palette.mint))

            let font = Font.caption2.weight(.semibold)
            context.draw(Text(start.formatted(date: .omitted, time: .shortened)).font(font).foregroundStyle(Palette.textSecondary),
                         at: CGPoint(x: 0, y: size.height - 6), anchor: .leading)
            context.draw(Text(wake.formatted(date: .omitted, time: .shortened)).font(font).foregroundStyle(Palette.textSecondary),
                         at: CGPoint(x: size.width, y: size.height - 6), anchor: .trailing)
            if let lucidAt, lucidAt > start, lucidAt < wake {
                context.draw(Text(lucidAt.formatted(date: .omitted, time: .shortened)).font(font).foregroundStyle(Palette.dawn),
                             at: CGPoint(x: x(lucidAt), y: size.height - 6), anchor: .center)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Sleep from \(bedtime.formatted(date: .omitted, time: .shortened)) to \(wake.formatted(date: .omitted, time: .shortened))"))
    }
}
