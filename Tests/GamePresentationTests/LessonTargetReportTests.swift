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
            for (name, policy) in Self.plays(for: lesson, in: GameWorld.newGame(lesson: lesson)) {
                var player = PolicyPlayer(world: .newGame(lesson: lesson), policy: policy)
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
        default:
            // A second train on day 0 or day 1, as Add a Train puts it on.
            return [0, 1].map { day in
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
