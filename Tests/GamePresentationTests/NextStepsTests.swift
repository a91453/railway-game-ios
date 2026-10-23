import GameCore
@testable import GamePresentation
import XCTest

/// City Transport Manager study, step M2: a free game's next steps, their
/// progress read from the world, and the check and tune when one is met
/// (decision 256), with nothing paid and nothing saved.
@MainActor
final class NextStepsTests: XCTestCase {
    /// A new game of simple rules with a track between its first two
    /// towns and a station at each, and a branch to a third station off
    /// the first town's end; money enough for every step.
    private func world() throws -> (world: GameWorld, a: StationID, b: StationID, c: StationID) {
        var world = GameWorld.newGame(balance: Money(5_000_000_000), rules: .simple)
        world.setTourism(nil)
        let towns = Land.townCentres(seed: 1, in: world.bounds)
        let from = towns[0], to = towns[1]
        let platform = Int64(4) * world.platformCarLength
        let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
        let span = (dx * dx + dy * dy).squareRoot()
        func along(_ point: PlanPoint, _ metres: Double) -> WorldCoordinate {
            WorldCoordinate(x: point.x + Int64(dx / span * metres), y: point.y + Int64(dy / span * metres))
        }
        let start = try world.buildTrackNode(at: along(from, -Double(platform)))
        let end = try world.buildTrackNode(at: along(to, Double(platform)))
        let main = try world.buildTrackEdge(from: start, to: end)
        let length = world.trackEdge(main)?.length ?? 0
        let a = try world.buildStation(named: "A", at: from).id
        try world.addTrackPlatform(a, on: main, from: platform / 2, to: platform + platform / 2)
        let b = try world.buildStation(named: "B", at: to).id
        try world.addTrackPlatform(b, on: main, from: length - platform - platform / 2, to: length - platform / 2)
        let reach = Double(4_000 * WorldCoordinate.unitsPerMetre)
        let far = try world.buildTrackNode(at: along(from, -reach))
        let branch = try world.buildTrackEdge(from: far, to: start)
        let c = try world.buildStation(named: "C", at: PlanPoint(x: along(from, -reach + Double(platform)).x, y: along(from, -reach + Double(platform)).y)).id
        try world.addTrackPlatform(c, on: branch, from: platform / 2, to: platform + platform / 2)
        return (world, a, b, c)
    }

    private func openLine(_ stops: [StationID], in session: GameSession) {
        for stop in stops {
            session.selectStation(stop)
            session.addSelectedStationToLineDraft()
        }
        session.createLineFromDraft()
    }

    func testANewGameStartsWithNothingMet() throws {
        let fresh = try XCTUnwrap(GameSession(world: GameWorld.newGame(rules: .simple)).nextSteps)
        XCTAssertEqual(fresh.steps.map(\.step), NextStep.allCases, "a map with land has every step")
        XCTAssertEqual(fresh.metCount, 0)
        XCTAssertEqual(fresh.current?.step, .firstLine)
        XCTAssertEqual(fresh.chipText(in: .english), "Next: Open your first line · 0/6")
        XCTAssertEqual(fresh.chipText(in: .traditionalChinese), "下一步：開第一條線 · 0/6")
        XCTAssertEqual(fresh.steps.last?.progressText, "0% / 50%")

        // Stations reach people before a line calls at them (decision 292),
        // so the coverage step can come first; the next step is still the
        // first not met.
        let built = try XCTUnwrap(GameSession(world: try world().world).nextSteps)
        XCTAssertTrue(built.steps[5].isMet, built.steps[5].progressText)
        XCTAssertEqual(built.current?.step, .firstLine)
        XCTAssertEqual(built.chipText(in: .english), "Next: Open your first line · 1/6")
    }

    /// Opening the line meets the first step at once: the check says so
    /// and the tune plays, though the game is not running.
    func testOpeningTheFirstLineIsAnsweredAtOnce() throws {
        let (world, a, b, _) = try world()
        let session = GameSession(world: world, language: .traditionalChinese)
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        openLine([a, b], in: session)
        XCTAssertEqual(session.world.lines.count, 1)
        XCTAssertEqual(session.goalPulse?.titles.first, "開第一條線")
        XCTAssertTrue(heard.contains(.goalMet))
        let steps = try XCTUnwrap(session.nextSteps)
        XCTAssertEqual(steps.current?.step, .profitableDay)
        XCTAssertTrue(steps.steps[0].isMet)
        // Two towns' stations reach more than half of the map's people.
        XCTAssertTrue(steps.steps[5].isMet, steps.steps[5].progressText)
    }

    /// Undo takes the line away, and opening it again is not met again.
    func testAStepIsAnsweredOnce() throws {
        let (world, a, b, _) = try world()
        let session = GameSession(world: world, language: .english)
        openLine([a, b], in: session)
        let serial = try XCTUnwrap(session.goalPulse?.serial)
        session.undo()
        XCTAssertEqual(session.world.lines.count, 0)
        XCTAssertEqual(session.nextSteps?.current?.step, .firstLine)
        openLine([a, b], in: session)
        XCTAssertEqual(session.goalPulse?.serial, serial, "no second check for the same step")
    }

    /// A second train on the line meets its step; the second line from a
    /// station the first calls at meets two in one: a second line and a
    /// station two lines share.
    func testTheNetworkSteps() throws {
        let (world, a, b, c) = try world()
        let session = GameSession(world: world, language: .english)
        openLine([a, b], in: session)
        session.selectLine(session.world.lines[0].id)
        session.addTrainToSelectedLine()
        XCTAssertEqual(session.world.lines[0].trains.count, 2, session.message?.text ?? "")
        XCTAssertEqual(session.goalPulse?.titles, ["Run two trains on one line"])

        openLine([c, a], in: session)
        XCTAssertEqual(session.world.lines.count, 2)
        XCTAssertEqual(Set(session.goalPulse?.titles ?? []), ["Open a second line", "A station two lines share"])
        let steps = try XCTUnwrap(session.nextSteps)
        XCTAssertEqual(steps.steps[2].progressText, "2/2")
        XCTAssertTrue(steps.steps[4].isMet)
        XCTAssertEqual(steps.current?.step, .profitableDay)
        XCTAssertEqual(steps.metCount, 5)
    }

    /// The first midnight with the line running pays: the check comes in
    /// the step of game time that settles it.
    func testADayThatPaysIsMetAtMidnight() throws {
        let (world, a, b, _) = try world()
        let opening = GameSession(world: world, language: .english)
        openLine([a, b], in: opening)
        var running = opening.world
        let day = running.clock.now.seconds / GameTime.secondsPerDay
        let late = (day + 1) * GameTime.secondsPerDay - 5 * GameTime.secondsPerMinute
        try running.advance(ticks: Int((late - running.clock.now.seconds) / GameTime.secondsPerMinute))
        XCTAssertFalse(NextSteps(world: running).steps[1].isMet, "the day is not settled yet")

        running.setSpeed(.fast)
        let session = GameSession(world: running, language: .english)
        for _ in 0..<2_000 where session.world.clock.now.seconds / GameTime.secondsPerDay == day {
            session.advance(realElapsed: GameSession.maximumStepDuration)
        }
        XCTAssertGreaterThan(session.world.clock.now.seconds / GameTime.secondsPerDay, day)
        XCTAssertTrue(try XCTUnwrap(session.nextSteps).steps[1].isMet)
        XCTAssertTrue(session.goalPulse?.titles.contains("A day that makes money") == true, "\(String(describing: session.goalPulse))")
    }

    /// Only a free game of the company's: not in a challenge, a demo, or
    /// free play without money; no coverage step without land.
    func testOnlyAFreeManagedGame() throws {
        var free = try world().world
        free.setEconomyMode(.free)
        XCTAssertNil(GameSession(world: free).nextSteps)

        let demo = GameSession(world: DemoWorld.make(in: .english))
        demo.news.isDemo = true
        XCTAssertNil(demo.nextSteps)

        var bare = GameWorld(bounds: try WorldBounds(width: 131_072, height: 98_304), economy: GameEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        bare.setEconomyMode(.management)
        let steps = try XCTUnwrap(GameSession(world: bare).nextSteps)
        XCTAssertEqual(steps.steps.count, 5)
        XCTAssertFalse(steps.steps.map(\.step).contains(.halfCovered))
    }

    /// PLAYER_FEEDBACK 82.1: the coverage step counts the map's people
    /// again only when the land or the open stations change, not after
    /// every edit (it was nearly all of an edit's time on a map of 44
    /// stations), and the steps stay what a fresh count makes them.
    func testTheCoverageIsCountedAgainOnlyWhenStationsOrLandChange() throws {
        let (world, a, b, _) = try world()
        let session = GameSession(world: world, language: .english)
        XCTAssertEqual(session.nextSteps, NextSteps(world: session.world))
        XCTAssertEqual(session.catchmentCoverageCounted, 1)

        let corner = WorldCoordinate(x: 2_000 * WorldCoordinate.unitsPerMetre, y: 2_000 * WorldCoordinate.unitsPerMetre)
        try session.performEdit { world throws(GameError) in _ = try world.buildTrackNode(at: corner) }
        openLine([a, b], in: session)
        session.undo()
        XCTAssertEqual(session.nextSteps, NextSteps(world: session.world))
        XCTAssertEqual(session.catchmentCoverageCounted, 1, "track, a line and an undo move no station")

        try session.performEdit { world throws(GameError) in _ = try world.buildStation(named: "D", at: PlanPoint(x: corner.x, y: corner.y)) }
        XCTAssertEqual(session.nextSteps, NextSteps(world: session.world))
        XCTAssertEqual(session.catchmentCoverageCounted, 2, "a new station")
    }

    func testAllDone() {
        let done = NextSteps(steps: NextStep.allCases.map { NextStepProgress(step: $0, value: 100, target: 1) })
        XCTAssertNil(done.current)
        XCTAssertEqual(done.chipText(in: .traditionalChinese), "6 個步驟都完成了")
        XCTAssertEqual(NextStepProgress(step: .secondTrain, value: 5, target: 2).progressText, "2/2")
    }
}
