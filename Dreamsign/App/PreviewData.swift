import Foundation
import SwiftData

/// In-memory store with sample content for SwiftUI previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: WakeAlarm.self, DreamEntry.self, DreamSign.self,
                                                  configurations: configuration)
        else { fatalError("Preview container failed") }
        let context = container.mainContext

        let weekday = WakeAlarm(time: AlarmTime(hour: 6, minute: 45), weekdays: .weekdays)
        weekday.label = "Work"
        var math = Challenge(kind: .math)
        math.mathProblems = 3
        weekday.challenges = [Challenge(kind: .shake), Challenge(kind: .journal), math]
        let weekend = WakeAlarm(time: AlarmTime(hour: 9, minute: 0), weekdays: .weekends)
        weekend.isEnabled = false
        context.insert(weekday)
        context.insert(weekend)

        let grandma = DreamSign(name: "Grandma", category: .person)
        let school = DreamSign(name: "Old school", category: .place)
        let water = DreamSign(name: "Rising water", category: .theme)
        let flying = DreamSign(name: "Flying", category: .theme)
        for sign in [grandma, school, water, flying] { context.insert(sign) }

        let samples: [(String, Int, Bool, Bool, [DreamSign])] = [
            ("I was back at my old school but the hallways kept filling with warm water. Grandma was teaching chemistry and handed me a key made of glass.", 0, false, false, [school, water, grandma]),
            ("Flying low over a city made of bookshelves. Realized I was dreaming when the streetlights started breathing.", 1, false, true, [flying]),
            ("Calm, a little heavy. Thinking about the trip next week and the sound of rain.", 2, true, false, []),
            ("Grandma's kitchen, but huge, like an airport. We were looking for a lost dog that kept turning into a cat.", 3, false, false, [grandma]),
            ("Swimming through my old school gym. Everyone could breathe underwater except me, then suddenly I could.", 5, false, false, [school, water]),
        ]
        for (text, daysAgo, noRecall, lucid, signs) in samples {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            let entry = DreamEntry(text: text, createdAt: date, isNoRecall: noRecall, source: .alarm)
            entry.isLucid = lucid
            entry.signs = signs
            context.insert(entry)
        }
        return container
    }()
}
