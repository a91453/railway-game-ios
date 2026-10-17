import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 266: the lessons. One state decides what a player
/// has: the lessons passed open the next, and a lesson's game has only the
/// tools unlocked by the lessons up to it; every other game has them all.
@MainActor
final class LessonTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LessonTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testTheLessonsAndWhatEachUnlocks() {
        XCTAssertEqual(Lesson.all.map(\.number), Array(1...10))
        XCTAssertEqual(Lesson.all.map(\.id), (1...10).map { "lesson.\($0)" })
        XCTAssertEqual(Lesson.all[0].tools, [])
        XCTAssertEqual(Lesson.all[1].tools, [])
        XCTAssertEqual(Lesson.all[2].tools, [.addTrain, .passingLoop])
        // Decision 271: one more each, in `UnlockableTool`'s order, and
        // every tool by the last lesson.
        XCTAssertEqual(Lesson.all.map(\.unlocks), [
            [], [], [.addTrain, .passingLoop], [], [.doubleTrack], [.lineDetails], [.depot], [.freight], [.buildingTool], [.trainTool],
        ])
        XCTAssertEqual(Lesson.all.last?.tools, Set(UnlockableTool.allCases))
        XCTAssertEqual(Lesson.all.map { $0.challenge.title(in: .traditionalChinese) }, [
            "第一條線", "第三個城鎮", "多一列車", "兩條線", "雙線", "路線的細節", "機廠", "貨運", "觀光景點", "城市的委託",
        ])
        XCTAssertEqual(Set(Lesson.all.map { $0.teaches(in: .english) }).count, 10, "each teaches its own thing")
        for lesson in Lesson.all {
            XCTAssertNotNil(Challenge.named(lesson.id), "a save names it")
            XCTAssertFalse(lesson.teaches(in: .english).isEmpty)
            let scenario = lesson.challenge.scenario(seed: Lesson.seed, in: GameWorld.newGameBounds)
            XCTAssertTrue(scenario.isValid(in: GameWorld.newGameBounds), lesson.id)
            XCTAssertNil(scenario.insolvencyDays, "a lesson is never lost by debt")
        }
    }

    /// The tutorial's step engine guides lessons 1 and 2: lesson 1 is the
    /// first line until its first fares, without buying its trains (the
    /// line opens with one, decision 264); lesson 2 the line's card and a
    /// station's riders.
    func testTheTutorialIsTheFirstLessonsGuide() {
        let first = Lesson.all[0].guide.map(\.id)
        XCTAssertEqual(first.first, "build.network")
        XCTAssertEqual(first.last, "first.fare")
        XCTAssertFalse(first.contains("line.staff"))
        XCTAssertEqual(Lesson.all[1].guide.map(\.id), ["lesson.extend", "line.card.open", "line.card.read", "station.select", "station.ridership"])
        XCTAssertEqual(Lesson.all[2].guide.map(\.id), ["lesson.addTrain"])
        XCTAssertEqual(Lesson.all.dropFirst(3).map { $0.guide.map(\.id) }, (4...10).map { ["lesson.\($0)"] })

        let world = GameWorld.newGame(lesson: Lesson.all[0])
        XCTAssertEqual(Tutorial.steps(over: world).map(\.id), first)
        XCTAssertEqual(Tutorial.steps(over: .newGame()).map(\.id), Tutorial.standardSteps.map(\.id), "elsewhere, the whole tour")
    }

    /// A lesson's game: simple rules on the usual blank map of seed 1's
    /// towns, no holidays, sights or requests, its scenario running.
    func testALessonsGame() throws {
        let world = GameWorld.newGame(lesson: Lesson.all[1])
        XCTAssertEqual(world.lesson?.number, 2)
        XCTAssertEqual(NewGameRules(of: world), .simple)
        XCTAssertEqual(world.bounds, GameWorld.newGameBounds)
        XCTAssertNil(world.mapExpansion)
        XCTAssertNil(world.disruptions)
        XCTAssertNil(world.tourism)
        XCTAssertEqual(world.scenario?.scenario.id, "lesson.2")
        XCTAssertNil(GameWorld.newGame().lesson)
        // Lesson 1 begins on a blank map; the lessons after it with lesson
        // 1's line, its train running, so each goes on from the one before.
        XCTAssertTrue(GameWorld.newGame(lesson: Lesson.all[0]).lines.isEmpty)
        XCTAssertEqual(world.lines.count, 1)
        XCTAssertGreaterThanOrEqual(world.lines.first?.stops.count ?? 0, 2, "its two stations, and the passing loop a long line opens with (decision 264)")
        XCTAssertFalse(world.trains.isEmpty)
        XCTAssertNil(world.scenario?.outcome)
    }

    /// Decision 271: lessons 5 to 10 begin with lesson 4's line to the
    /// third town too, and what a lesson turns on stays on after it: the
    /// sight from lesson 9, the city's requests in lesson 10. Freight, on
    /// in every new game, is shown from lesson 8.
    func testTheLaterLessonsGames() throws {
        let fourth = GameWorld.newGame(lesson: Lesson.all[3])
        XCTAssertEqual(fourth.lines.count, 1, "lesson 4 opens the second line itself")
        XCTAssertFalse(GameSession(world: fourth).showsFreight)
        let fifth = GameWorld.newGame(lesson: Lesson.all[4])
        XCTAssertEqual(fifth.lines.count, 2)
        XCTAssertGreaterThanOrEqual(fifth.trains.count, 2)
        XCTAssertNil(fifth.tourism)
        XCTAssertFalse(GameSession(world: .newGame(lesson: Lesson.all[6])).showsFreight)
        XCTAssertTrue(GameSession(world: .newGame(lesson: Lesson.all[7])).showsFreight)
        XCTAssertTrue(GameSession(world: .newGame()).showsFreight, "every other game")
        let ninth = GameWorld.newGame(lesson: Lesson.all[8])
        XCTAssertEqual(ninth.tourism?.attractions.map(\.point), [Lesson.sight(in: ninth.bounds)])
        XCTAssertNil(ninth.cityRequests)
        let tenth = GameWorld.newGame(lesson: Lesson.all[9])
        XCTAssertNotNil(tenth.cityRequests)
        for lesson in Lesson.all.dropFirst(3) {
            let world = GameWorld.newGame(lesson: lesson)
            XCTAssertNil(world.scenario?.outcome, "lesson \(lesson.number) is not won as it begins")
            XCTAssertGreaterThan(world.economy.balance, .zero, "lesson \(lesson.number) begins with money to build")
        }
    }

    /// Decision 271: double track only once lesson 5 has taught it.
    func testDoubleTrackFromLessonFive() {
        XCTAssertFalse(GameSession(world: .newGame(lesson: Lesson.all[3])).allows(UnlockableTool.doubleTrack))
        XCTAssertTrue(GameSession(world: .newGame(lesson: Lesson.all[4])).allows(UnlockableTool.doubleTrack))
        // The first line's track picked in each: Make Double Track is
        // offered in lesson 5, not in lesson 4.
        for (index, offered) in [(3, false), (4, true)] {
            let session = GameSession(world: .newGame(lesson: Lesson.all[index]))
            session.selectTool(.select)
            let edge = session.world.network.edges.max { $0.length < $1.length }
            let geometry = edge.flatMap { session.world.trackGeometry(of: $0.id) }
            if let geometry {
                session.tapMap(at: geometry.location(at: geometry.length / 3).position.plan, reach: 512)
            }
            XCTAssertNotNil(session.selectedTrackEdge, "lesson \(index + 1)")
            XCTAssertEqual(session.canDoubleSelectedTrack, offered, "lesson \(index + 1)")
        }
    }

    /// Decision 266: in a lesson only the tools unlocked up to it; in any
    /// other game, all of them.
    func testALessonHasOnlyItsTools() {
        let first = GameSession(world: .newGame(lesson: Lesson.all[0]))
        XCTAssertFalse(first.allows(UnlockableTool.addTrain))
        XCTAssertFalse(first.allows(UnlockableTool.trainTool))
        XCTAssertFalse(first.allows(ConstructionTool.train))
        XCTAssertTrue(first.allows(ConstructionTool.network))
        XCTAssertFalse(first.allows(NetworkToolMode.passingLoop))
        XCTAssertFalse(first.allows(UnlockableTool.lineDetails))
        XCTAssertFalse(AdvancedDetails.isShown(stored: true, roomy: true, unlocked: first.allows(UnlockableTool.lineDetails)))
        let third = GameSession(world: .newGame(lesson: Lesson.all[2]))
        XCTAssertTrue(third.allows(UnlockableTool.addTrain))
        XCTAssertTrue(third.allows(UnlockableTool.passingLoop))
        XCTAssertFalse(third.allows(UnlockableTool.depot))
        let free = GameSession(world: .newGame(rules: .simple))
        XCTAssertTrue(UnlockableTool.allCases.allSatisfy { free.allows($0) })
    }

    /// The first lesson is always open; each other once the one before was
    /// passed. A lesson's stars are kept, the most it was passed with, and
    /// lesson 1 passed is the tutorial finished.
    func testPassingALessonOpensTheNextAndKeepsItsStars() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let launcher = GameLauncher(library: SaveLibrary(directory: folder), language: .english)
        XCTAssertEqual(Lesson.all.map(launcher.isOpen), [true] + Array(repeating: false, count: 9))
        XCTAssertTrue(launcher.showsFirstGameCard)

        launcher.startLesson(Lesson.all[0])
        let session = try XCTUnwrap(launcher.session)
        XCTAssertEqual(session.lesson?.number, 1)
        XCTAssertEqual(session.tutorial?.step.id, "build.network", "the guide begins")
        XCTAssertTrue(session.runsLinesForThePlayer, "its lines open with their trains")

        var world = session.world
        world.scenario?.outcome = .completed(day: 2, rating: .silver)
        launcher.recordLessonResult(of: world)
        XCTAssertEqual(launcher.stars(of: Lesson.all[0]), 2)
        XCTAssertEqual(Lesson.all.map(launcher.isOpen), [true, true] + Array(repeating: false, count: 8))
        XCTAssertFalse(launcher.showsFirstGameCard, "the tutorial is finished")

        world.scenario?.outcome = .completed(day: 3, rating: .bronze)
        launcher.recordLessonResult(of: world)
        XCTAssertEqual(launcher.stars(of: Lesson.all[0]), 2, "the most kept")
        world.scenario?.outcome = .completed(day: 1, rating: .gold)
        launcher.recordLessonResult(of: world)
        XCTAssertEqual(launcher.lessonStarTotal, 3)

        let again = GameLauncher(library: SaveLibrary(directory: folder), language: .english)
        XCTAssertEqual(again.stars(of: Lesson.all[0]), 3, "kept on the device")
    }

    /// The tutorial's entries start lesson 1.
    func testTheTutorialStartsTheFirstLesson() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let launcher = GameLauncher(library: SaveLibrary(directory: folder), language: .english)
        launcher.startTutorial()
        XCTAssertEqual(launcher.session?.lesson?.number, 1)
        XCTAssertEqual(launcher.session?.tutorial?.step.id, "build.network")
    }

    /// Decision 266, later: a lesson's minutes, with the app in the
    /// foreground only, the minutes it took to pass and the step its guide
    /// was left on, for the problem report; nothing else.
    func testTheLessonsTimingsForAProblemReport() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let launcher = GameLauncher(library: SaveLibrary(directory: folder), language: .english)
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        launcher.now = { clock }
        XCTAssertNil(launcher.lessonReport(in: .english), "no lesson played")
        launcher.setActive(true)
        defer { launcher.setActive(false) }
        launcher.startLesson(Lesson.all[0])
        clock += 4 * 60
        launcher.setActive(false)
        clock += 60 * 60
        launcher.setActive(true)
        clock += 2 * 60
        var world = try XCTUnwrap(launcher.session).world
        world.scenario?.outcome = .completed(day: 1, rating: .gold)
        launcher.recordLessonResult(of: world)
        clock += 3 * 60
        XCTAssertEqual(
            launcher.lessonReport(in: .english),
            "1 ★3 9 min, passed after 6 min, left at step 1 of 15", "the hour in the background is not counted"
        )
        XCTAssertEqual(launcher.lessonReport(in: .traditionalChinese), "1 ★3 9 分，6 分 過關，停在第 1／15 步")

        launcher.startLesson(Lesson.all[1])
        launcher.startLesson(Lesson.all[1])
        clock += 60
        XCTAssertEqual(
            launcher.lessonReport(in: .english),
            "1 ★3 9 min, passed after 6 min, left at step 1 of 15; 2 ★0 1 min, left at step 1 of 5, started 2 times"
        )
        let report = ProblemReport(version: "1.0", build: "1", system: "iOS", device: "iPhone", lessons: launcher.lessonReport(in: .english))
        XCTAssertTrue(report.text(in: .english).hasSuffix("Lessons: 1 ★3 9 min, passed after 6 min, left at step 1 of 15; 2 ★0 1 min, left at step 1 of 5, started 2 times"))
        XCTAssertFalse(ProblemReport(version: "1.0", build: "1", system: "iOS", device: "iPhone").text(in: .english).contains("Lessons"))
    }

    /// Decision 266, later: the lessons' unlocks never reach another game;
    /// once every lesson is passed, the list says so.
    func testEveryLessonPassedAndFreePlayHasEverything() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let launcher = GameLauncher(library: SaveLibrary(directory: folder), language: .english)
        XCTAssertFalse(launcher.passedEveryLesson)
        for lesson in Lesson.all {
            var world = GameWorld.newGame(lesson: lesson)
            world.scenario?.outcome = .completed(day: 1, rating: .bronze)
            launcher.recordLessonResult(of: world)
        }
        XCTAssertTrue(launcher.passedEveryLesson)
        launcher.startLesson(Lesson.all[0])
        XCTAssertFalse(try XCTUnwrap(launcher.session).allows(UnlockableTool.addTrain), "a lesson keeps to its own tools")
        launcher.startNewGame()
        let free = try XCTUnwrap(launcher.session)
        XCTAssertNil(free.lesson)
        XCTAssertTrue(UnlockableTool.allCases.allSatisfy { free.allows($0) })
        XCTAssertTrue(free.showsFreight)
    }

    /// Lesson 1's guide ends on an action step, the first fares: done, it
    /// does not move on by itself, so the guide waits for Finish (decision
    /// 177) rather than ending before it can be tapped (the full lane on
    /// main d530311).
    func testTheFirstLessonsLastStepWaitsForFinish() throws {
        // A line from the first town to the second, as the guide has it
        // built, then time run until the fares come in.
        var world = GameWorld.newGame(lesson: Lesson.all[0])
        var opening = CurvedOpening(auto: true)
        try opening.openFirstLine(&world, from: Lesson.towns(in: world.bounds)[0], to: Lesson.towns(in: world.bounds)[1])
        let session = GameSession(world: world, language: .english)
        session.startTutorial(atStep: "first.fare")
        let last = try XCTUnwrap(session.tutorial?.steps.count) - 1
        XCTAssertEqual(session.tutorial?.steps.last?.id, "first.fare")
        XCTAssertEqual(session.tutorial?.index, last)
        let end = session.world.clock.now.seconds + 2 * GameTime.secondsPerDay
        while !session.isTutorialStepDone, session.world.clock.now.seconds < end {
            session.advance(realElapsed: GameSession.maximumStepDuration)
        }
        XCTAssertTrue(session.isTutorialStepDone, "the fares came in")
        XCTAssertFalse(session.tutorialAdvancesByItself, "the last step waits for Finish")
        session.showNextTutorialStep(from: last)
        XCTAssertEqual(session.tutorial?.index, last, "moving on by itself does nothing")
        session.showNextTutorialStep()
        XCTAssertNil(session.tutorial, "Finish ends it")
    }

    func testTheResultCard() throws {
        var world = GameWorld.newGame(lesson: Lesson.all[0])
        XCTAssertNil(LessonResult(world: world), "not over yet")
        world.scenario?.outcome = .completed(day: 1, rating: .gold)
        let gold = try XCTUnwrap(LessonResult(world: world))
        XCTAssertEqual(gold.stars, 3)
        XCTAssertEqual(gold.next?.number, 2)
        XCTAssertEqual(gold.title(in: .traditionalChinese), "第 1 關過關")
        world.scenario?.outcome = .failed(day: 3, reason: .deadline)
        let failed = try XCTUnwrap(LessonResult(world: world))
        XCTAssertEqual(failed.stars, 0)
        XCTAssertNil(failed.next)
        XCTAssertEqual(Lesson.stars(for: .silver), 2)
        var last = GameWorld.newGame(lesson: Lesson.all[9])
        last.scenario?.outcome = .completed(day: 2, rating: .gold)
        XCTAssertNil(LessonResult(world: last)?.next, "the last lesson")
    }
}
