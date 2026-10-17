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
        XCTAssertEqual(Lesson.all.map(\.number), [1, 2, 3])
        XCTAssertEqual(Lesson.all.map(\.id), ["lesson.1", "lesson.2", "lesson.3"])
        XCTAssertEqual(Lesson.all[0].tools, [])
        XCTAssertEqual(Lesson.all[1].tools, [])
        XCTAssertEqual(Lesson.all[2].tools, [.addTrain, .passingLoop])
        XCTAssertEqual(Lesson.all.map { $0.challenge.title(in: .traditionalChinese) }, ["第一條線", "第三個城鎮", "多一列車"])
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
        XCTAssertEqual(Lesson.all.map(launcher.isOpen), [true, false, false])
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
        XCTAssertEqual(Lesson.all.map(launcher.isOpen), [true, true, false])
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
        var last = GameWorld.newGame(lesson: Lesson.all[2])
        last.scenario?.outcome = .completed(day: 2, rating: .gold)
        XCTAssertNil(LessonResult(world: last)?.next, "the last lesson")
    }
}
