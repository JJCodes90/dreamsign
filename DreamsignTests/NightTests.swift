import Foundation
import Testing
@testable import Dreamsign

@Suite("Night audio plan")
struct NightPlanTests {
    let start = Fixtures.date(2026, 11, 2, 23, 0)

    @Test func soundscapeFadesInAndOutOnTheTimer() {
        let plan = NightPlan(soundscape: .rain, sleepTimerMinutes: 30, riseInto: nil, cues: nil)
        #expect(plan.soundscapeLevel(at: start, startedAt: start) == 0)
        #expect(plan.soundscapeLevel(at: start.addingTimeInterval(10), startedAt: start) == 0.5)
        #expect(plan.soundscapeLevel(at: start.addingTimeInterval(600), startedAt: start) == 1)
        let midFade = plan.soundscapeLevel(at: start.addingTimeInterval(30 * 60 + 150), startedAt: start)
        #expect(abs(midFade - 0.5) < 0.001)
        #expect(plan.soundscapeLevel(at: start.addingTimeInterval(40 * 60), startedAt: start) == 0)
        #expect(plan.endDate(startedAt: start) == start.addingTimeInterval(30 * 60 + NightPlan.fadeOut + 5))
    }

    @Test func offMeansSilence() {
        let plan = NightPlan(soundscape: .off, sleepTimerMinutes: 0, riseInto: nil, cues: nil)
        #expect(plan.soundscapeLevel(at: start.addingTimeInterval(600), startedAt: start) == 0)
        #expect(plan.endDate(startedAt: start) == start)
    }

    @Test func risesIntoTheAlarm() {
        let alarm = Fixtures.date(2026, 11, 3, 6, 45)
        let plan = NightPlan(soundscape: .ocean, sleepTimerMinutes: 0, riseInto: alarm, cues: nil)
        #expect(plan.soundscapeLevel(at: alarm.addingTimeInterval(-3600), startedAt: start) == 1)
        #expect(plan.leadInLevel(at: alarm.addingTimeInterval(-3600)) == nil)
        let early = plan.leadInLevel(at: alarm.addingTimeInterval(-NightPlan.leadIn + 1)) ?? 0
        let late = plan.leadInLevel(at: alarm.addingTimeInterval(-5)) ?? 0
        #expect(early > 0 && early < late)
        #expect(plan.soundscapeLevel(at: alarm, startedAt: start) == 0)
        #expect(plan.endDate(startedAt: start) == alarm.addingTimeInterval(90))
    }

    @Test func cuesKeepTheNightGoing() {
        let wake = Fixtures.date(2026, 11, 3, 6, 45)
        let window = CuePlan.window(beforeWake: wake)
        let plan = NightPlan(soundscape: .rain, sleepTimerMinutes: 30, riseInto: nil,
                             cues: CuePlan(start: window.start, end: window.end))
        #expect(plan.endDate(startedAt: start) == window.end.addingTimeInterval(60))
    }
}

@Suite("Lucidity cues")
struct CuePlanTests {
    let wake = Fixtures.date(2026, 11, 3, 6, 45)

    var plan: CuePlan {
        let window = CuePlan.window(beforeWake: wake)
        return CuePlan(start: window.start, end: window.end)
    }

    @Test func windowIsTheLastTwoHours() {
        #expect(plan.start == Fixtures.date(2026, 11, 3, 4, 30))
        #expect(plan.end == Fixtures.date(2026, 11, 3, 6, 30))
    }

    @Test func burstsAreSpacedAndStayInTheWindow() {
        let inWindow = Fixtures.date(2026, 11, 3, 5, 0)
        #expect(!plan.shouldStartBurst(now: Fixtures.date(2026, 11, 3, 4, 0), lastBurst: nil, lastMovement: nil))
        #expect(plan.shouldStartBurst(now: inWindow, lastBurst: nil, lastMovement: nil))
        #expect(!plan.shouldStartBurst(now: inWindow, lastBurst: inWindow.addingTimeInterval(-60), lastMovement: nil))
        #expect(plan.shouldStartBurst(now: inWindow, lastBurst: inWindow.addingTimeInterval(-plan.interval), lastMovement: nil))
        #expect(!plan.shouldStartBurst(now: Fixtures.date(2026, 11, 3, 6, 40), lastBurst: nil, lastMovement: nil))
    }

    @Test func movementAndHoldsQuietTheCues() {
        let now = Fixtures.date(2026, 11, 3, 5, 30)
        #expect(!plan.shouldStartBurst(now: now, lastBurst: nil, lastMovement: now.addingTimeInterval(-120)))
        #expect(plan.shouldStartBurst(now: now, lastBurst: nil, lastMovement: now.addingTimeInterval(-plan.quietAfterMovement - 1)))
        #expect(!plan.shouldStartBurst(now: now, lastBurst: nil, lastMovement: nil, heldUntil: now.addingTimeInterval(60)))
    }
}

@Suite("Dream world map")
struct DreamGraphTests {
    let day = Fixtures.date(2026, 10, 1)

    func dreams() -> [DreamGraph.Dream] {
        [
            .init(signs: ["school", "water", "grandma"], isLucid: true, date: day),
            .init(signs: ["school", "water"], isLucid: false, date: day.addingTimeInterval(86400)),
            .init(signs: ["school", "exam"], isLucid: false, date: day.addingTimeInterval(2 * 86400)),
            .init(signs: ["flying"], isLucid: true, date: day.addingTimeInterval(3 * 86400)),
            .init(signs: [], isLucid: false, date: day),
        ]
    }

    @Test func countsAndLinks() {
        let graph = DreamGraph(dreams: dreams())
        #expect(graph.nodes.first?.id == "school")
        #expect(graph.node("school")?.count == 3)
        #expect(graph.node("school")?.lucidCount == 1)
        #expect(graph.node("school")?.weight == 1)
        #expect(graph.node("school")?.lastSeen == day.addingTimeInterval(2 * 86400))
        #expect(graph.edges.contains(DreamGraph.Edge(a: "school", b: "water", count: 2)))
        #expect(graph.neighbors(of: "school").first?.id == "water")
        #expect(graph.neighbors(of: "flying").isEmpty)
    }

    @Test func layoutIsDeterministicAndInBounds() {
        let first = DreamGraph(dreams: dreams())
        let second = DreamGraph(dreams: dreams())
        #expect(first.nodes == second.nodes)
        for node in first.nodes {
            #expect((0.08...0.92).contains(node.x) && (0.08...0.92).contains(node.y))
        }
        // Nodes don't pile on top of each other.
        for a in first.nodes {
            for b in first.nodes where a.id < b.id {
                #expect(hypot(a.x - b.x, a.y - b.y) > 0.08)
            }
        }
    }

    @Test func duplicateSignsInOneDreamCountOnce() {
        let graph = DreamGraph(dreams: [.init(signs: ["cat", "cat", "dog"], isLucid: false, date: day)])
        #expect(graph.node("cat")?.count == 1)
        #expect(graph.edges == [DreamGraph.Edge(a: "cat", b: "dog", count: 1)])
    }

    @Test func emptyAndSingle() {
        #expect(DreamGraph(dreams: []).nodes.isEmpty)
        let single = DreamGraph(dreams: [.init(signs: ["moon"], isLucid: false, date: day)])
        #expect(single.nodes.count == 1)
        #expect(single.nodes[0].x == 0.5)
    }
}
