import Foundation
import SwiftData
import SwiftUI

/// Screenshot / demo mode: launch with `-showcase <screen>` to open straight to a screen, filled
/// with sample data in memory. Nothing touches AlarmKit, permissions or the real store.
enum Showcase {
    static let screen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-showcase"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }()

    static var isActive: Bool { screen != nil }

    /// Screens that are simply a tab of the normal app.
    static var tab: AppModel.Tab? {
        switch screen ?? "" {
        case "tonight": .tonight
        case "alarms": .alarms
        case "journal", "dream-world": .journal
        case "insights": .insights
        case "learn": .learn
        default: nil
        }
    }

    static let dreamText = """
    I was back at my old school, but the hallways kept filling with warm water. Grandma was teaching \
    chemistry and handed me a key made of glass. When I looked at the clock it had no hands, and \
    I suddenly knew I was dreaming.
    """

    @MainActor
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: WakeAlarm.self, DreamEntry.self, DreamSign.self,
                                                  configurations: configuration)
        else { fatalError("Showcase container failed") }
        seed(container.mainContext)
        return container
    }

    @MainActor
    private static func seed(_ context: ModelContext) {
        let work = WakeAlarm(time: AlarmTime(hour: 6, minute: 45), weekdays: .weekdays)
        work.label = "Work"
        var math = Challenge(kind: .math)
        math.mathProblems = 3
        var scan = Challenge(kind: .scan)
        scan.scanCode = "0123456789012"
        scan.scanLabel = "Toothpaste, bathroom"
        work.challenges = [Challenge(kind: .shake), Challenge(kind: .journal), math, scan]
        work.sound = .tide
        work.gentleStartMinutes = 10
        work.wakeCheck = true
        work.bedtimeNudge = true

        let weekend = WakeAlarm(time: AlarmTime(hour: 9, minute: 15), weekdays: .weekends)
        weekend.label = "Slow Saturday"
        weekend.challenges = [Challenge(kind: .journal)]
        weekend.isEnabled = false

        let gym = WakeAlarm(time: AlarmTime(hour: 5, minute: 30), weekdays: [.tuesday, .thursday])
        gym.label = "Gym"
        var hardMath = Challenge(kind: .math)
        hardMath.mathDifficulty = .hard
        gym.challenges = [Challenge(kind: .shake), hardMath]
        gym.sound = .beacon

        let wbtb = WakeAlarm(time: AlarmTime(hour: 4, minute: 30), weekdays: .everyDay, kind: .wbtb)
        wbtb.applyWBTB(bedtime: AlarmTime(hour: 23, minute: 30), offsetMinutes: 300,
                       nights: [.friday, .saturday])
        wbtb.isEnabled = true
        [work, weekend, gym, wbtb].forEach { context.insert($0) }

        let grandma = DreamSign(name: "Grandma", category: .person)
        let school = DreamSign(name: "Old school", category: .place)
        let water = DreamSign(name: "Rising water", category: .theme)
        let flying = DreamSign(name: "Flying", category: .theme)
        let clocks = DreamSign(name: "Broken clocks", category: .theme)
        let sam = DreamSign(name: "Sam", category: .person)
        let airport = DreamSign(name: "Airport", category: .place)
        let signs = [grandma, school, water, flying, clocks, sam, airport]
        signs.forEach { context.insert($0) }

        let texts: [(String, [DreamSign], Bool, Bool)] = [
            (dreamText, [school, water, grandma, clocks], false, true),
            ("Flying low over a city made of bookshelves. The streetlights started breathing and I realized it was a dream.", [flying], false, true),
            ("Calm, a little heavy. Thinking about the trip next week and the sound of rain.", [], true, false),
            ("Grandma's kitchen, but huge, like an airport. We were looking for a dog that kept turning into a cat.", [grandma, airport], false, false),
            ("Swimming through my old school gym. Everyone could breathe underwater except me, then suddenly I could.", [school, water], false, false),
            ("Sam and I missed a flight because every clock showed a different time.", [sam, airport, clocks], false, false),
            ("A long train ride through a desert of glass. Nobody had a face.", [], false, false),
            ("Back at school for an exam I hadn't studied for. The questions kept rewriting themselves.", [school], false, false),
            ("Flying again, this time above the ocean at night. I could steer by leaning.", [flying, water], false, true),
            ("Restless. Nothing came back except a feeling of being late.", [], true, false),
            ("Sam was teaching me to drive a boat through the airport terminal.", [sam, airport, water], false, false),
            ("Grandma's garden, with clocks growing like sunflowers.", [grandma, clocks], false, false),
        ]
        var random = SeededRandomNumberGenerator(seed: 11)
        let calendar = Calendar.current
        var dayOffset = 0
        for index in 0..<26 {
            let (text, tagged, noRecall, lucid) = texts[index % texts.count]
            dayOffset += index < 9 ? 1 : Int.random(in: 1...3, using: &random)
            let day = calendar.date(byAdding: .day, value: -dayOffset + 1, to: .now) ?? .now
            let hour = Int.random(in: 6...7, using: &random)
            let created = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59, using: &random), second: 0, of: day) ?? day
            let entry = DreamEntry(text: text, createdAt: created, isNoRecall: noRecall, source: index % 5 == 2 ? .wbtb : .alarm)
            entry.isLucid = lucid && index < 12
            entry.signs = tagged
            entry.vividness = noRecall ? 0 : Int.random(in: 2...5, using: &random)
            entry.mood = noRecall ? nil : DreamMood.allCases.randomElement(using: &random)
            entry.techniqueRaw = [WBTBTechnique.mild.rawValue, WBTBTechnique.ssild.rawValue, "", ""][index % 4]
            entry.isNightmare = index == 7
            context.insert(entry)
        }
        try? context.save()
    }
}

/// Renders a single showcase screen that isn't a plain tab.
struct ShowcaseRoot: View {
    let screen: String
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\WakeAlarm.hour)]) private var alarms: [WakeAlarm]
    @Query(sort: \DreamEntry.createdAt, order: .reverse) private var entries: [DreamEntry]

    private var workAlarm: WakeAlarm? { alarms.first { $0.label == "Work" } }

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case "onboarding":
            OnboardingView {}
        case "alarm-editor":
            AlarmEditorView(alarm: workAlarm)
        case "wbtb":
            WBTBSettingsView(plan: model.wbtbPlan(context))
        case "settings":
            SettingsView()
        case "entry":
            if let entry = entries.first {
                NavigationStack { JournalEntryView(entry: entry) }
            }
        case "wake-shake":
            WakeFlowView(session: wakeSession, startIndex: 0)
        case "wake-journal":
            WakeFlowView(session: wakeSession, startIndex: 1)
        case "wake-math":
            WakeFlowView(session: wakeSession, startIndex: 2)
        case "wake-complete":
            WakeFlowView(session: wakeSession, startIndex: 4, savedEntry: entries.first)
        case "wake-voice":
            WakeFlowView(session: wakeSession, startIndex: 1)
        case "cues":
            NavigationStack { CuesView() }
        case "wake-steps":
            WakeFlowView(session: session(.steps), startIndex: 0)
        case "wake-scan":
            WakeFlowView(session: session(.scan), startIndex: 0)
        case "wake-phrase":
            WakeFlowView(session: session(.phrase), startIndex: 0)
        case "wake-memory":
            WakeFlowView(session: session(.memory), startIndex: 0)
        case "wake-check":
            WakeFlowView(session: checkSession, startIndex: 0)
        case "mild":
            WakeFlowView(session: wbtbSession, startIndex: 1, savedEntry: entries.first)
        case "sleep":
            WakeFlowView(session: wbtbSession, startIndex: 2)
        case "lesson":
            if let lesson = Course.lesson("mild") {
                NavigationStack {
                    LessonView(lesson: lesson, progress: LearnProgress.shared, onPractice: { _ in }, onNext: { _ in })
                }
            }
        case "reality":
            RealityCheckView()
        case "ssild":
            PracticeHost(action: .ssild)
        case "nightstand":
            NightstandView()
        default:
            Text("Unknown showcase screen: \(screen)")
        }
    }

    private var wakeSession: WakeSession {
        let alarmID = workAlarm?.id ?? UUID()
        let occurrence = Occurrence(alarmID: alarmID, fireDate: .now.addingTimeInterval(-252), kind: .wake,
                                    chainLength: 15, primaryID: alarmID)
        return WakeSession(occurrence: occurrence, alarm: workAlarm)
    }

    /// A one-challenge wake-up for showing a single challenge type.
    private func session(_ kind: Challenge.Kind) -> WakeSession {
        let alarm = WakeAlarm(time: AlarmTime(hour: 6, minute: 45), weekdays: .weekdays)
        alarm.label = "Work"
        var challenge = Challenge(kind: kind)
        if kind == .scan {
            challenge.scanCode = "0123456789012"
            challenge.scanLabel = "Toothpaste, bathroom"
        }
        alarm.challenges = [challenge]
        let occurrence = Occurrence(alarmID: alarm.id, fireDate: .now.addingTimeInterval(-140), kind: .wake,
                                    chainLength: 15, primaryID: alarm.id)
        return WakeSession(occurrence: occurrence, alarm: alarm)
    }

    private var checkSession: WakeSession {
        let alarmID = workAlarm?.id ?? UUID()
        var occurrence = Occurrence(alarmID: alarmID, fireDate: .now.addingTimeInterval(-20), kind: .wake,
                                    chainLength: 4, primaryID: UUID(), isOneOff: true)
        occurrence.checkOf = "showcase"
        return WakeSession(occurrence: occurrence, alarm: workAlarm)
    }

    private var wbtbSession: WakeSession {
        let plan = alarms.first { $0.kind == .wbtb }
        let alarmID = plan?.id ?? UUID()
        let occurrence = Occurrence(alarmID: alarmID, fireDate: .now.addingTimeInterval(-180), kind: .wbtb,
                                    chainLength: 10, primaryID: alarmID)
        return WakeSession(occurrence: occurrence, alarm: plan)
    }
}
