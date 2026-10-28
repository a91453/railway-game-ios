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
            "第一條線", "第三個城鎮", "多一列車", "兩條線", "複線", "路線的細節", "機廠", "貨運", "觀光景點", "城市的委託",
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

    /// Decision 390: a lesson's goal of linking places says which ("Link
    /// all 2 towns" read wrong, and lesson 9's second place is a sight);
    /// lesson 1's gold is open on the second day, and lesson 7 asks for
    /// what its lines carry resting at night.
    func testTheLessonsGoalsSayWhatToLink() {
        XCTAssertEqual(Lesson.all[0].challenge.goalsText(in: .english).first, "Link the two towns by rail")
        XCTAssertEqual(Lesson.all[1].challenge.goalsText(in: .traditionalChinese).first, "用鐵路連通三座城鎮")
        XCTAssertEqual(Lesson.all[3].challenge.goalsText(in: .english).first, "Link all three towns by rail")
        XCTAssertEqual(Lesson.all[8].challenge.goalsText(in: .english).first, "Take the railway on to Seaview Point")
        XCTAssertEqual(Lesson.all[0].starsText(in: .english), "★★★ within 2 days · ★★ within 3 days · ★ within 5 days")
        XCTAssertEqual(Lesson.all[6].challenge.goalsText(in: .english), ["65,000 riders a day"])
        let world = GameWorld.newGame(lesson: Lesson.all[8])
        XCTAssertEqual(world.goalProgress(in: .english).first?.title, "Take the railway on to Seaview Point")
    }

    /// The tutorial's step engine guides lessons 1 and 2: lesson 1 is the
    /// first line until its first fares, without buying its trains (the
    /// line opens with one, decision 264); lesson 2 the line's card and a
    /// station's riders, after (decision 390) the track, station and stop
    /// on to the third town, one action each.
    func testTheTutorialIsTheFirstLessonsGuide() {
        let first = Lesson.all[0].guide.map(\.id)
        XCTAssertEqual(first.first, "build.network")
        XCTAssertEqual(first.last, "first.fare")
        XCTAssertFalse(first.contains("line.staff"))
        XCTAssertEqual(Lesson.all[1].guide.map(\.id), [
            "lesson.extend", "lesson.2.track", "track.build", "station.mode", "lesson.2.site", "station.first.build", "lesson.2.done",
            "lesson.2.station", "lesson.2.lines", "lesson.2.add", "line.card.open", "line.card.read", "station.select", "station.ridership",
        ])
        // Decision 376: lessons 3–10 step by step (LessonGuideTests), each
        // after the third starting at its earlier read step's id.
        XCTAssertEqual(Lesson.all[2].guide.map(\.id).first, "lesson.3.lines")
        XCTAssertEqual(Lesson.all.dropFirst(3).map { $0.guide.map(\.id).first }, (4...10).map { "lesson.\($0)" })

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
            "1 ★3 9 min, passed after 6 min, left at step 1 of 15; 2 ★0 1 min, left at step 1 of 14, started 2 times"
        )
        let report = ProblemReport(version: "1.0", build: "1", system: "iOS", device: "iPhone", lessons: launcher.lessonReport(in: .english))
        XCTAssertTrue(report.text(in: .english).hasSuffix("Lessons: 1 ★3 9 min, passed after 6 min, left at step 1 of 15; 2 ★0 1 min, left at step 1 of 14, started 2 times"))
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

    /// A goal met pauses the game (decision 175); "Keep Playing" on the
    /// lesson's result card goes on running it, as it says, without the
    /// player looking for Resume (the Codex UI tests of #784 saw it stay
    /// paused). A pause of the player's own is left alone.
    func testKeepPlayingRunsTheGameAGoalPaused() throws {
        let session = GameSession(world: GameWorld.newGame(lesson: Lesson.all[0], opensFirstLine: true), language: .english)
        session.setSpeed(.normal)
        for _ in 0..<48 where !session.world.clock.isPaused {
            let tick = try XCTUnwrap(session.beginLoopTick())
            let step = try GameSession.advanced(tick.world, by: 60, listening: false)
            XCTAssertTrue(session.finish(tick, with: .success(step)))
        }
        XCTAssertTrue(session.world.clock.isPaused, "a goal met paused it")
        XCTAssertTrue(session.isPausedForEvent)
        session.keepPlaying()
        XCTAssertFalse(session.world.clock.isPaused, "Keep Playing runs it again")
        XCTAssertEqual(session.world.clock.speed, .normal)

        session.togglePause()
        session.keepPlaying()
        XCTAssertTrue(session.world.clock.isPaused, "the player's own pause stays")
    }

    /// LessonUITests passes lesson 1 by building the second town's station
    /// and a line on the tutorial's fixture, then waits for the result
    /// card. Opened at midnight, as the UI test now launches it (paused),
    /// day 0 carries the riders and the lesson passes at its end. Opened
    /// in the afternoon, as a slow runner once left it running until 09:04
    /// before it paused, day 0 carries too few: the goal met at midnight
    /// is the link alone, and the game pauses for it with no result
    /// (main f70a4cb's full lane, run 40592891253).
    func testTheUITestsFirstLessonPassesOnDayZero() throws {
        XCTAssertEqual(try firstLessonOutcome(openingAfterMinutes: 0), .completed(day: 0, rating: .gold))
        XCTAssertNil(try firstLessonOutcome(openingAfterMinutes: 15 * 60), "too few riders on day 0")
    }

    /// The outcome at the first midnight of lesson 1 built as LessonUITests'
    /// `passFirstLesson` builds it, `minutes` after the tutorial's step
    /// starts, then run at fast forward.
    private func firstLessonOutcome(openingAfterMinutes minutes: Int) throws -> ScenarioOutcome? {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let launcher = GameLauncher(library: SaveLibrary(directory: folder), language: .english)
        launcher.startTutorial(atStep: "line.open")
        let session = try XCTUnwrap(launcher.session)
        session.skipTutorial()
        session.setSpeed(.normal)
        for _ in 0..<minutes {
            let tick = try XCTUnwrap(session.beginLoopTick())
            session.finish(tick, with: .success(try GameSession.advanced(tick.world, by: 1, listening: false)))
        }
        session.togglePause()

        let middle = WorldBounds.standard.width / 2
        let town = Land.townCentres(seed: 1, in: .standard)[1]
        let east = town.x >= middle
        let junction = PlanPoint(x: middle + (east ? 5_120 : -6_144), y: middle)
        let dx = Double(town.x - junction.x), dy = Double(town.y - junction.y)
        let span = hypot(dx, dy)
        let margin = Double(800 * WorldCoordinate.unitsPerMetre)
        let end = PlanPoint(x: town.x + Int64(dx / span * margin), y: town.y + Int64(dy / span * margin))
        let curve = try XCTUnwrap(NetworkBuilding.curve(from: junction, leaving: PlanVector(dx: east ? 1 : -1, dy: 0), to: end, leaving: nil))
        let geometry = try XCTUnwrap(TrackGeometry(from: WorldCoordinate(x: junction.x, y: junction.y), to: WorldCoordinate(x: end.x, y: end.y), curve: curve))
        let site = try XCTUnwrap(geometry.points.min {
            hypot(Double($0.x - town.x), Double($0.y - town.y)) < hypot(Double($1.x - town.x), Double($1.y - town.y))
        })
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.tapNetwork(at: junction, reach: 512)
        session.tapNetwork(at: end, reach: 512)
        session.buildNetworkTrack()
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: site.x, y: site.y), reach: 512)
        session.addNetworkPlatform()
        XCTAssertEqual(session.world.stations.count, 3, "the second town's station")
        session.selectTool(.select)
        for station in [session.world.stations[0], session.world.stations[2]] {
            session.selectStation(station.id)
            session.addSelectedStationToLineDraft()
        }
        session.createLineFromDraft()
        XCTAssertEqual(session.world.lines.count, 1)

        session.setSpeed(.fast)
        // The midnight that ends day 0 is judged with the tick after it.
        let midnight = GameTime.secondsPerDay
        while session.world.clock.now.seconds <= midnight, let tick = session.beginLoopTick() {
            session.finish(tick, with: .success(try GameSession.advanced(tick.world, by: 1, listening: false)))
        }
        XCTAssertTrue(session.world.clock.isPaused, "a goal met at midnight paused it")
        return session.world.scenario?.outcome
    }
}
