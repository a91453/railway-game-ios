import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 266: the lessons' targets, measured. Each lesson is played on
/// its own map (seed 1's towns, simple rules) by a `Policy` that does what
/// the lesson teaches as soon as it may, and the riders of each day and
/// the day each goal is met are printed as Markdown. Runs only on request:
///
///     LESSON_REPORT=7 swift test -c release -Xswiftc -enable-testing \
///       --filter LessonTargetReportTests
///
/// `LESSON_REPORT` is the days to play (1 to 30).
@MainActor
final class LessonTargetReportTests: XCTestCase {
    func testTheLessonsTargets() throws {
        guard let value = ProcessInfo.processInfo.environment["LESSON_REPORT"] else {
            throw XCTSkip("set LESSON_REPORT=<days> to measure the lessons' targets")
        }
        let days = try XCTUnwrap(Int64(value).flatMap { (1...30).contains($0) ? $0 : nil }, "LESSON_REPORT is 1 to 30 days")
        var rows = [
            "| Lesson | Play | Riders a day: day 1 … \(days) | Goals met (day) | Outcome |",
            "| --- | --- | --- | --- | --- |",
        ]
        for lesson in Lesson.all {
            // Lessons 1–4 and 9 without the lines they begin with: each play
            // opens them on day 0, as ``GameWorld/newGame(lesson:)`` does,
            // and goes on from there. The other lessons as they begin
            // (decision 271).
            let blank = GameWorld.newGame(lesson: lesson, opensFirstLine: ![1, 2, 3, 4, 9].contains(lesson.number))
            for (name, policy) in Self.plays(for: lesson, in: blank) {
                var player = PolicyPlayer(world: blank, policy: policy)
                while player.day < days {
                    try player.playDay()
                }
                let state = player.world.scenario
                let met = (state?.achieved ?? []).map { $0.map(String.init) ?? "—" }.joined(separator: " / ")
                let outcome = state?.outcome.map { "\($0)" } ?? "running"
                rows.append("| \(lesson.number) | \(name) | \(player.trips.map(String.init).joined(separator: " · ")) | \(met) | \(outcome) |")
            }
        }
        print("### The lessons' plays (seed \(Lesson.seed), \(days) days)\n\n" + rows.joined(separator: "\n"))
    }

    /// The plays each lesson is measured with: what it teaches, done at
    /// once (the network tool stops the clock while the player builds).
    static func plays(for lesson: Lesson, in world: GameWorld) -> [(String, Policy)] {
        let towns = Lesson.towns(in: world.bounds)
        let first = Policy.twoTowns(towns, auto: true)
        switch lesson.number {
        case 1:
            return [("first line", first)]
        case 2:
            // The track on to the third town and its station added to the
            // line, on day 0 or day 1.
            return [0, 1].map { day in
                ("third town on day \(day)", Policy(name: "lesson-2", actions: first.actions + [
                    Policy.Action(day: day, waitsForMoney: true) { world, memory in
                        try memory.opening.extend(&world, to: towns[2])
                    },
                ]))
            }
        case 4:
            // Nothing, and lesson 4's line on to the third town, from the
            // first town's end of the track, on day 0 or day 1.
            return [("nothing", first)] + [0, 1].map { day in
                ("second line on day \(day)", Policy(name: "lesson-4", actions: first.actions + [
                    Policy.Action(day: day, waitsForMoney: true) { world, memory in
                        try memory.opening.extend(&world, to: towns[2])
                    },
                ]))
            }
        case 9:
            // The lines lesson 9 begins with, then nothing, or the track on
            // from beyond the second town to the sight on day 0 or day 1.
            let both = first.actions + [Policy.Action(day: 0) { world, memory in try memory.opening.extend(&world, to: towns[2]) }]
            return [("nothing", Policy(name: "lesson-9", actions: both))] + [0, 1].map { day in
                ("line to the sight on day \(day)", Policy(name: "lesson-9", actions: both + [
                    Policy.Action(day: day, waitsForMoney: true) { world, memory in
                        try memory.opening.extendBeyondTheSecondTown(&world, to: Lesson.sight(in: world.bounds))
                    },
                ]))
            }
        case 5...10:
            // As the lesson begins: what it teaches is not among the goals
            // GameCore judges (decision 271).
            return [("as it begins", Policy(name: "lesson-\(lesson.number)", actions: []))]
        default:
            // One train, as lesson 1's line opens, and a second on day 0 or
            // day 1, as Add a Train puts it on.
            return [("one train", first)] + [0, 1].map { day in
                ("second train on day \(day)", Policy(name: "lesson-3", actions: first.actions + [
                    Policy.Action(day: day, waitsForMoney: true) { world, _ in
                        try MainActor.assumeIsolated {
                            let session = GameSession(world: world)
                            guard let line = world.lines.first?.id else { return }
                            session.selectLine(line)
                            session.addTrainToSelectedLine()
                            guard session.world.lines.first?.trains.count == 2 else {
                                throw GameError.insufficientFunds(required: .zero, available: world.economy.balance)
                            }
                            world = session.world
                        }
                    },
                ]))
            }
        }
    }
}
