import SwiftData
import SwiftUI

/// Wake-back-to-bed plan: bedtime + offset → a gentle alarm, then journal → MILD → sleep.
struct WBTBSettingsView: View {
    let plan: WakeAlarm

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model

    @State private var enabled: Bool
    @State private var bedtime: Date
    @State private var offset: Double
    @State private var nights: WeekdaySet
    @State private var sound: AlarmSound
    @State private var mildMinutes: Int
    @State private var journalWords: Int
    @State private var technique: WBTBTechnique
    @AppStorage(AudioPreferences.voiceKey) private var voiceGuidance = true
    @AppStorage(AudioPreferences.soundscapeKey) private var sleepSounds = true

    static let offsetRange: ClosedRange<Double> = 270...360

    init(plan: WakeAlarm) {
        self.plan = plan
        _enabled = State(initialValue: plan.isEnabled)
        _bedtime = State(initialValue: plan.bedtime.date())
        _offset = State(initialValue: Double(plan.wbtbOffsetMinutes))
        _nights = State(initialValue: plan.wbtbNights)
        _sound = State(initialValue: plan.sound)
        _mildMinutes = State(initialValue: plan.mildMinutes)
        _journalWords = State(initialValue: plan.wbtbJournalWords)
        _technique = State(initialValue: plan.wbtbTechnique)
    }

    private var wakeTime: AlarmTime {
        AlarmTime(date: bedtime).adding(minutes: Int(offset))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $enabled) {
                        Label("Lucid window", systemImage: "moon.stars.fill")
                    }
                    .tint(Palette.iris)
                } footer: {
                    Text("A gentle alarm after a few hours of sleep, when REM periods run longest. Jot the dream down, rehearse your intention, and go straight back to sleep — falling asleep quickly afterwards is linked to more lucid dreams.")
                }

                Section {
                    VStack(spacing: 18) {
                        HStack(alignment: .bottom) {
                            column("Bed", AlarmTime(date: bedtime))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundStyle(Palette.textTertiary)
                                .padding(.bottom, 12)
                            Spacer()
                            column("Wake", wakeTime, tint: Palette.iris)
                        }
                        VStack(spacing: 6) {
                            Slider(value: $offset, in: Self.offsetRange, step: 15)
                                .tint(Palette.iris)
                            HStack {
                                Text("4½ h").font(.caption).foregroundStyle(Palette.textTertiary)
                                Spacer()
                                Text(offsetText).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                                Spacer()
                                Text("6 h").font(.caption).foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    DatePicker("Bedtime", selection: $bedtime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Timing")
                } footer: {
                    Text("Studies typically wake people 4½–6 hours after lights out. Five hours is a good place to start.")
                }

                Section {
                    DayPicker(selection: $nights)
                        .padding(.vertical, 6)
                } header: {
                    Text("Nights")
                } footer: {
                    Text("Chosen by the night you go to bed. Two or three nights a week protects your sleep.")
                }

                Section {
                    Picker("Technique", selection: $technique) {
                        ForEach(WBTBTechnique.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Technique")
                } footer: {
                    Text("\(technique.detail). MILD and SSILD worked about equally well in the largest study — pick whichever feels easier.")
                }

                Section("When it wakes you") {
                    Picker("Journal", selection: $journalWords) {
                        ForEach([8, 10, 15, 25], id: \.self) { Text("\($0) words").tag($0) }
                    }
                    if technique == .mild {
                        Picker("Intention practice", selection: $mildMinutes) {
                            ForEach([1, 2, 3, 5], id: \.self) { Text("\($0) min").tag($0) }
                        }
                    }
                    Toggle("Voice guidance", isOn: $voiceGuidance).tint(Palette.iris)
                    Toggle("Sleep sounds", isOn: $sleepSounds).tint(Palette.iris)
                    NavigationLink {
                        SoundPickerView(selection: $sound)
                    } label: {
                        LabeledContent("Sound", value: sound.title)
                    }
                }

                Section {
                    Button {
                        Task { await testNow() }
                    } label: {
                        Label("Test in 10 seconds", systemImage: "play.circle.fill")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NightBackground(stars: false))
            .navigationTitle("Lucid Window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                ToolbarItem(placement: .prominentConfirm) {
                    Button(role: .confirm) {
                        apply()
                        dismiss()
                    }
                }
            }
        }
    }

    private var offsetText: String {
        let minutes = Int(offset)
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) h after bed") : String(localized: "\(hours) h \(rest) min after bed")
    }

    private func column(_ title: LocalizedStringKey, _ time: AlarmTime, tint: Color = Palette.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.textTertiary)
            ClockText(time, size: 36).foregroundStyle(tint)
        }
    }

    private func apply() {
        plan.applyWBTB(bedtime: AlarmTime(date: bedtime), offsetMinutes: Int(offset), nights: nights)
        plan.isEnabled = enabled && !nights.isEmpty
        plan.sound = sound
        plan.mildMinutes = mildMinutes
        plan.wbtbJournalWords = journalWords
        plan.wbtbTechnique = technique
        plan.touch()
        try? context.save()
        Task { await model.syncAlarms(context) }
    }

    private func testNow() async {
        apply()
        await model.coordinator.armOneOff(spec: plan.spec, at: .now.addingTimeInterval(10), isTest: true)
    }
}
