import SwiftData
import SwiftUI

/// Editable copy of an alarm; written back only on Save.
struct AlarmDraft {
    var time = AlarmTime(hour: 7, minute: 0)
    var weekdays: WeekdaySet = .weekdays
    var label = ""
    var sound: AlarmSound = .system
    var challenges = Challenge.defaults
    var chainMinutes = 15
    var gentleStartMinutes = 0
    var wakeCheck = false
    var bedtimeNudge = false
    var sleepGoalMinutes = 480

    static let chainOptions = [5, 10, 15, 20, 30]
    static let gentleOptions = [5, 10, 15, 20]

    init(_ alarm: WakeAlarm?) {
        guard let alarm else { return }
        time = alarm.time
        weekdays = alarm.weekdays
        label = alarm.label
        sound = alarm.sound
        challenges = alarm.challenges
        chainMinutes = alarm.chainMinutes
        gentleStartMinutes = alarm.gentleStartMinutes
        wakeCheck = alarm.wakeCheck
        bedtimeNudge = alarm.bedtimeNudge
        sleepGoalMinutes = alarm.sleepGoalMinutes
    }

    var bedtime: AlarmTime { SleepPlan.bedtime(forWake: time, sleepMinutes: sleepGoalMinutes) }

    var timeDate: Date {
        get { time.date() }
        set { time = AlarmTime(date: newValue) }
    }

    var missingKinds: [Challenge.Kind] {
        Challenge.Kind.allCases.filter { kind in !challenges.contains { $0.kind == kind } }
    }

    /// Recall fades within minutes; math first eats into it.
    var mathBeforeJournal: Bool {
        guard let math = challenges.firstIndex(where: { $0.kind == .math }),
              let journal = challenges.firstIndex(where: { $0.kind == .journal })
        else { return false }
        return math < journal
    }

    func apply(to alarm: WakeAlarm) {
        alarm.time = time
        alarm.weekdays = weekdays
        alarm.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        alarm.sound = sound
        alarm.challenges = challenges
        alarm.chainMinutes = chainMinutes
        alarm.gentleStartMinutes = gentleStartMinutes
        alarm.wakeCheck = wakeCheck
        alarm.bedtimeNudge = bedtimeNudge
        alarm.sleepGoalMinutes = sleepGoalMinutes
        alarm.isEnabled = true
        alarm.touch()
    }
}

struct AlarmEditorView: View {
    let alarm: WakeAlarm?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model

    @State private var draft: AlarmDraft
    @State private var saved: WakeAlarm?
    @State private var testFire: Date?
    @State private var confirmDelete = false

    init(alarm: WakeAlarm?) {
        self.alarm = alarm
        _draft = State(initialValue: AlarmDraft(alarm))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $draft.timeDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                Section {
                    DayPicker(selection: $draft.weekdays)
                        .padding(.vertical, 6)
                } header: {
                    Text("Repeat")
                } footer: {
                    Text(draft.weekdays.isOneShot ? "Rings once, then switches off." : draft.weekdays.summary())
                }

                Section("Label") {
                    TextField("Alarm", text: $draft.label)
                        .submitLabel(.done)
                }

                Section {
                    NavigationLink {
                        SoundPickerView(selection: $draft.sound)
                    } label: {
                        LabeledContent("Sound", value: draft.sound.title)
                    }
                }

                smartWakeSection

                challengesSection

                Section {
                    Picker("Keep ringing for", selection: $draft.chainMinutes) {
                        ForEach(AlarmDraft.chainOptions, id: \.self) { Text("\($0) min").tag($0) }
                    }
                } footer: {
                    Text("Stopping it without finishing won't work — it rings again every minute, with the system alarm sound, until you're done.")
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        Label("Test in 10 seconds", systemImage: "play.circle.fill")
                    }
                } footer: {
                    if let testFire {
                        Text("Rings at \(testFire.formatted(date: .omitted, time: .standard)). Lock your phone to see it like you will in the morning.")
                    } else {
                        Text("Saves the alarm, then rings once with a short chain so you can try the whole flow.")
                    }
                }

                if alarm != nil {
                    Section {
                        Button("Delete Alarm", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NightBackground(stars: false))
            .navigationTitle(alarm == nil ? "New Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .prominentConfirm) {
                    Button(role: .confirm) {
                        persist()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete this alarm?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
        }
    }

    private var smartWakeSection: some View {
        Section {
            Toggle(isOn: Binding(get: { draft.gentleStartMinutes > 0 },
                                 set: { draft.gentleStartMinutes = $0 ? 10 : 0 })) {
                SmartWakeRow(symbol: "sunrise.fill", tint: Palette.dawn, title: "Gentle start",
                             detail: draft.gentleStartMinutes > 0
                                ? "A soft sound \(draft.gentleStartMinutes) min before"
                                : "A soft sound before the alarm")
            }
            if draft.gentleStartMinutes > 0 {
                Picker("Starts", selection: $draft.gentleStartMinutes) {
                    ForEach(AlarmDraft.gentleOptions, id: \.self) { Text("\($0) min before").tag($0) }
                }
            }
            Toggle(isOn: $draft.wakeCheck) {
                SmartWakeRow(symbol: "checkmark.circle.fill", tint: Palette.mint, title: "Wake-up check",
                             detail: "5 min after you finish, prove you're still up")
            }
            Toggle(isOn: Binding(get: { draft.bedtimeNudge }, set: { on in
                draft.bedtimeNudge = on
                if on { Task { if !(await BedtimeNudges.requestPermission()) { draft.bedtimeNudge = false } } }
            })) {
                SmartWakeRow(symbol: "moon.zzz.fill", tint: Palette.iris, title: "Bedtime nudge",
                             detail: "Bed by \(ClockFormat.string(draft.bedtime)) for \(SleepPlan.goalTitle(draft.sleepGoalMinutes))")
            }
            if draft.bedtimeNudge {
                Picker("Sleep goal", selection: $draft.sleepGoalMinutes) {
                    ForEach(SleepPlan.goalOptions, id: \.self) { Text(SleepPlan.goalTitle($0)).tag($0) }
                }
            }
        } header: {
            Text("Smart wake")
        } footer: {
            if draft.bedtimeNudge {
                Text("A reminder 30 minutes before bedtime, counting 15 minutes to fall asleep.")
            } else if draft.wakeCheck {
                Text("The check is skipped if you're still using Dreamsign when it's due.")
            }
        }
    }

    private var challengesSection: some View {
        Section {
            ForEach($draft.challenges) { $challenge in
                NavigationLink {
                    ChallengeSettingsView(challenge: $challenge)
                } label: {
                    ChallengeRow(challenge: challenge)
                }
                .contextMenu { moveButtons(for: challenge) }
            }
            .onDelete { draft.challenges.remove(atOffsets: $0) }
            .onMove { draft.challenges.move(fromOffsets: $0, toOffset: $1) }

            if !draft.missingKinds.isEmpty {
                Menu {
                    ForEach(draft.missingKinds) { kind in
                        Button {
                            withAnimation { draft.challenges.append(Challenge(kind: kind)) }
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                } label: {
                    Label("Add challenge", systemImage: "plus.circle.fill")
                }
            }
        } header: {
            Text("To turn it off")
        } footer: {
            if draft.challenges.contains(where: \.needsSetup) {
                Text("Register a code for Scan, or it switches to math in the morning.")
                    .foregroundStyle(Palette.ember)
            } else if draft.challenges.isEmpty {
                Text("With no challenges, one tap in the app turns it off.")
            } else if draft.mathBeforeJournal {
                Text("Tip: journal before math — dream recall fades within minutes.")
            } else {
                Text("Done in order. Long-press to reorder, swipe to remove.")
            }
        }
    }

    @ViewBuilder
    private func moveButtons(for challenge: Challenge) -> some View {
        if let index = draft.challenges.firstIndex(where: { $0.id == challenge.id }) {
            if index > 0 {
                Button { draft.challenges.swapAt(index, index - 1) } label: { Label("Move Up", systemImage: "arrow.up") }
            }
            if index < draft.challenges.count - 1 {
                Button { draft.challenges.swapAt(index, index + 1) } label: { Label("Move Down", systemImage: "arrow.down") }
            }
        }
    }

    @discardableResult
    private func persist() -> WakeAlarm {
        let target: WakeAlarm
        if let existing = alarm ?? saved {
            target = existing
        } else {
            target = WakeAlarm()
            context.insert(target)
            saved = target
        }
        draft.apply(to: target)
        try? context.save()
        Task { await model.syncAlarms(context) }
        return target
    }

    private func test() async {
        let target = persist()
        let fire = Date.now.addingTimeInterval(10)
        if await model.coordinator.armOneOff(spec: target.spec, at: fire, isTest: true) != nil {
            testFire = fire
        }
    }

    private func delete() {
        if let alarm {
            context.delete(alarm)
            try? context.save()
            Task { await model.syncAlarms(context) }
        }
        dismiss()
    }
}

struct ChallengeRow: View {
    let challenge: Challenge

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: challenge.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.dawn)
                .frame(width: 36, height: 36)
                .background(Palette.dawn.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.kind.title).foregroundStyle(Palette.text)
                Text(challenge.summary).font(.subheadline)
                    .foregroundStyle(challenge.needsSetup ? Palette.ember : Palette.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Icon + title + one line, for the Smart wake toggles.
struct SmartWakeRow: View {
    var symbol: String
    var tint: Color
    var title: LocalizedStringKey
    var detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Palette.text)
                Text(detail).font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ChallengeSettingsView: View {
    @Binding var challenge: Challenge
    @State private var registering = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: challenge.kind.symbol)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Palette.dawn)
                    Text(challenge.kind.pitch)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.text)
                }
                .padding(.vertical, 8)
            }

            switch challenge.kind {
            case .shake:
                Section {
                    Picker("Shakes", selection: $challenge.shakeCount) {
                        ForEach(Challenge.shakeOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Shakes")
                } footer: {
                    Text("Getting your body moving cuts through grogginess.")
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Slider(value: $challenge.shakeSensitivity, in: 0...1)
                            .tint(Palette.dawn)
                        HStack {
                            Text("Hard shake").font(.caption).foregroundStyle(Palette.textTertiary)
                            Spacer()
                            Text("Gentle wobble").font(.caption).foregroundStyle(Palette.textTertiary)
                        }
                    }
                    ShakeTester(sensitivity: challenge.shakeSensitivity)
                } header: {
                    Text("Sensitivity")
                } footer: {
                    Text("Try it: shake your phone and watch the count. Slide toward gentle if it feels like hard work.")
                }
            case .math:
                Section {
                    Picker("Difficulty", selection: $challenge.mathDifficulty) {
                        ForEach(MathDifficulty.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Difficulty")
                } footer: {
                    Text("Like \(challenge.mathDifficulty.example)")
                }
                Section {
                    Picker("Problems", selection: $challenge.mathProblems) {
                        ForEach(Challenge.problemOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("In a row")
                } footer: {
                    Text("A wrong answer starts the streak over.")
                }
            case .journal:
                Section {
                    Picker("Words", selection: $challenge.journalWords) {
                        ForEach(Challenge.wordOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Minimum words")
                } footer: {
                    Text("Distinct real words — mashing and padding don't count. If no dream comes back, you can write your first thoughts instead (\(JournalRequirement.noRecall.minimumWords) words).")
                }
            case .steps:
                Section {
                    Picker("Steps", selection: $challenge.stepCount) {
                        ForEach(Challenge.stepOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Counted by your iPhone's motion sensor. If Motion & Fitness access is off, you'll shake instead.")
                }
            case .scan:
                Section {
                    if challenge.scanCode.isEmpty {
                        Button { registering = true } label: {
                            Label("Register a code", systemImage: "barcode.viewfinder")
                        }
                    } else {
                        LabeledContent("Code", value: challenge.scanLabel.isEmpty ? String(localized: "Registered") : challenge.scanLabel)
                        Button("Use a different code") { registering = true }
                    }
                } header: {
                    Text("Your code")
                } footer: {
                    Text("Any barcode or QR code on something far from your bed — toothpaste in the bathroom, the coffee bag in the kitchen. If the camera can't be used in the morning, you'll do math instead.")
                }
            case .phrase:
                Section {
                    Picker("Length", selection: $challenge.phraseLength) {
                        ForEach(PhraseLength.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Length")
                } footer: {
                    Text("Like “\(challenge.phraseLength.phrases[0])”")
                }
            case .memory:
                Section {
                    Picker("Pattern", selection: $challenge.memoryLength) {
                        ForEach(Challenge.memoryOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Pattern length")
                } footer: {
                    Text("Watch the tiles light up, then tap them in order. A wrong tap plays a new pattern.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(NightBackground(stars: false))
        .navigationTitle(challenge.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $registering) {
            ScanSetupView(challenge: $challenge)
        }
    }
}

#Preview {
    AlarmEditorView(alarm: nil)
        .environment(AppModel())
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}

/// Live shake counter for tuning sensitivity in settings.
private struct ShakeTester: View {
    let sensitivity: Double
    @State private var monitor: ShakeMonitor?

    var body: some View {
        HStack {
            Label("Test shakes", systemImage: "iphone.gen3.radiowaves.left.and.right")
                .foregroundStyle(Palette.text)
            Spacer()
            Text("\(monitor?.count ?? 0)")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(Palette.dawn)
                .contentTransition(.numericText())
                .animation(.snappy, value: monitor?.count)
            Button("Reset") { restart() }
                .buttonStyle(.borderless)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: monitor?.count)
        .onAppear { restart() }
        .onDisappear { monitor?.stop() }
        .onChange(of: sensitivity) { restart() }
    }

    private func restart() {
        monitor?.stop()
        let fresh = ShakeMonitor(sensitivity: sensitivity)
        fresh.start()
        monitor = fresh
    }
}
