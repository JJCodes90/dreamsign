import Foundation
import Testing
@testable import Dreamsign

@MainActor
@Suite("Course & practice")
struct LearnTests {
    @Test func lessonIDsAreUnique() {
        let ids = Course.lessons.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyLessonIsSubstantialAndSourced() {
        for lesson in Course.lessons {
            #expect(!lesson.blocks.isEmpty, "\(lesson.id) has no content")
            #expect(!lesson.sources.isEmpty, "\(lesson.id) cites nothing")
            #expect(lesson.minutes > 0)
        }
    }

    @Test func sourcesUseHTTPS() {
        for source in Course.lessons.flatMap(\.sources) {
            #expect(source.url.scheme == "https", "\(source.text)")
        }
    }

    @Test func lookupFindsLessons() {
        #expect(Course.lesson("mild")?.title == "MILD")
        #expect(Course.lesson("nope") == nil)
        #expect(Course.modules.count == 6)
        #expect(Course.lessons.count == 13)
    }

    @Test func ssildPlanTiming() {
        #expect(SSILDView.plan.count == (SSILDView.quickCycles + SSILDView.slowCycles) * 3)
        #expect(SSILDView.total == 4 * 3 * 5 + 3 * 3 * 30)

        let start = SSILDView.beat(at: 0)
        #expect(start.index == 0)
        #expect(start.beat.sense == .sight)
        #expect(!start.beat.slow)

        #expect(SSILDView.beat(at: 5.1).beat.sense == .sound)

        let firstSlow = SSILDView.beat(at: 60.5)
        #expect(firstSlow.beat.slow)
        #expect(firstSlow.beat.sense == .sight)
        #expect(firstSlow.beat.cycle == 1)

        let end = SSILDView.beat(at: 10_000)
        #expect(end.index == SSILDView.plan.count - 1)
    }

    @Test func techniqueLogExpires() {
        TechniqueLog.record(.ssild)
        #expect(TechniqueLog.recent == .ssild)
        UserDefaults.standard.set(Date.now.addingTimeInterval(-11 * 3600), forKey: "technique.at")
        #expect(TechniqueLog.recent == nil)
    }
}
