import Foundation
import GameCore
import GamePresentation
import XCTest

/// The tutorial (Stage C5, redone by decision 188): one action a step, in
/// five chapters; Next waiting until the player has done what the step
/// asks (read from the world and the session), the step moving on by
/// itself once done and passing over the steps done ahead, Back, Skip,
/// "Skip this step", the steps' setups and hints, and starting again, after
/// the `Ci/` reference's guided tour.
final class TutorialSessionTests: XCTestCase {
    private static let reach: Int64 = 512
    private static let tile: Int64 = 1_024

    private static let stepIDs = [
        "build.network", "map.move", "track.draw", "track.build",
        "station.mode", "station.first.site", "station.first.build", "station.second.site", "station.second.build",
        "line.open", "line.stations", "line.create",
        "line.staff", "build.done", "time.play", "first.fare", "line.card.open", "line.card.read",
        "station.select", "station.ridership", "end",
    ]

    /// Each step waits for its own action, in the order a first line is
    /// built and run, and moves on by itself once done; the time step is
    /// passed, as Done sets time running; the last two steps need only
    /// reading, and Finish ends the tutorial. A new game and the demo map,
    /// which already has track, stations and lines, are both walked
    /// through: each goal asks for something new.
    func testNextWaitsForEachStepAndDoneEndsTheTutorial() async throws {
        for world in [GameWorld.newGame(), DemoWorld.make(in: .english)] {
            await MainActor.run { [world] in
                let session = GameSession(world: world, language: .english)
                var finished = false
                session.onTutorialCompleted = { finished = true }
                XCTAssertNil(session.tutorial)
                XCTAssertFalse(session.isTutorialStepDone, "no tutorial")
                session.startTutorial()
                XCTAssertEqual(session.tutorial?.steps.map(\.id), Self.stepIDs)
                XCTAssertEqual(session.tutorial?.isFirstStep, true)
                session.showNextTutorialStep()
                XCTAssertEqual(session.tutorial?.index, 0, "Next waits for the network tool")

                var visited: [String] = []
                while let tutorial = session.tutorial, visited.count < Self.stepIDs.count {
                    let id = tutorial.step.id
                    visited.append(id)
                    XCTAssertEqual(session.isTutorialStepDone, tutorial.step.goal == .read, "\(id) starts \(tutorial.step.goal == .read ? "done" : "undone")")
                    // The card keeps clear of what the player taps on the
                    // map: the ends of the stretch just built, then the two
                    // stations just built, not the demo's own.
                    switch id {
                    case "station.first.site", "station.second.site":
                        XCTAssertEqual(Set(session.tutorialPlacesToTap), [Self.point(2, in: session), Self.point(13, in: session)], id)
                    case "line.stations", "station.select":
                        let (first, second) = Self.newStations(session)
                        XCTAssertEqual(session.tutorialPlacesToTap, [first.location, second.location], id)
                    default:
                        XCTAssertEqual(session.tutorialPlacesToTap, [], id)
                    }
                    Self.carryOut(id, in: session)
                    XCTAssertTrue(session.isTutorialStepDone, "\(id) is done")
                    if tutorial.step.goal == .read {
                        XCTAssertFalse(session.tutorialAdvancesByItself, id)
                        session.showNextTutorialStep()
                    } else {
                        XCTAssertTrue(session.tutorialAdvancesByItself, id)
                        session.showNextTutorialStep(from: tutorial.index)
                    }
                }
                XCTAssertEqual(visited, Self.stepIDs.filter { $0 != "time.play" }, "Done sets time running")
                XCTAssertNil(session.tutorial, "Finish ends it")
                XCTAssertTrue(finished)
            }
        }
    }

    /// Where the walk-through builds: a new game's line goes through its
    /// first town, the middle of the map, so its first fares come (decision
    /// 125); the demo's own lines earn them, and its middle is taken.
    @MainActor
    private static func point(_ x: Int64, in session: GameSession) -> PlanPoint {
        let origin = session.world.lines.isEmpty && !session.world.land.isEmpty
            ? PlanPoint(x: session.world.bounds.width / 2 - 8 * tile, y: session.world.bounds.height / 2 - 6 * tile)
            : PlanPoint(x: 0, y: 0)
        return PlanPoint(x: origin.x + x * tile, y: origin.y + 6 * tile)
    }

    /// Does what step `id` asks, checking what it sets up and says on the way.
    @MainActor
    private static func carryOut(_ id: String, in session: GameSession) {
        func at(_ x: Int64) -> PlanPoint {
            point(x, in: session)
        }
        switch id {
        case "build.network":
            session.selectTool(.network)
        case "map.move":
            session.mapDidMove()
        case "track.draw":
            session.tapNetwork(at: at(2), reach: reach)
            XCTAssertEqual(session.tutorialHint?.text, "Now tap where it ends.")
            // 176 m, enough for two stations.
            session.tapNetwork(at: at(13), reach: reach)
            XCTAssertNotNil(session.networkPreview)
        case "track.build":
            session.buildNetworkTrack()
        case "station.mode":
            XCTAssertNil(session.networkStart, "the end flag is gone")
            session.setNetworkMode(.platform)
        case "station.first.site":
            session.tapNetwork(at: at(4), reach: reach)
        case "station.first.build":
            session.addNetworkPlatform()
        case "station.second.site":
            XCTAssertNil(session.networkEdgePoint, "the bubble on the first station is gone")
            XCTAssertEqual(session.message?.text.hasPrefix("Built station"), true, "the first station's message stays")
            session.tapNetwork(at: at(11), reach: reach)
        case "station.second.build":
            session.addNetworkPlatform()
        case "line.open":
            // The lines panel starts picking by itself.
            session.startPickingLineStops(announces: false)
        case "line.stations":
            let (first, second) = newStations(session)
            session.tapMap(at: first.point, reach: reach)
            XCTAssertEqual(session.tutorialHint?.text, "Now tap the other station.")
            session.tapMap(at: second.point, reach: reach)
        case "line.create":
            session.createLineFromDraft()
        case "line.staff":
            // Decision 125: the new line, still selected, gets its trains in
            // the lines panel's one step (decision 101).
            XCTAssertEqual(session.selectedLine?.trains.isEmpty, true)
            session.staffSelectedLine(headway: 10)
            XCTAssertEqual(session.selectedLine?.targetHeadways, TargetHeadways(peak: 10, offPeak: 10, low: 10))
        case "build.done":
            session.selectTool(.select)
        case "first.fare":
            runUntilFares(session)
        case "line.card.open":
            XCTAssertNotNil(session.selectedLine, "the tutorial's line is selected")
            session.linesPanelDidChange(isShown: true)
        case "station.select":
            XCTAssertNil(session.selectedStationID, "picking the line's stations selected one")
            session.selectStation(newStations(session).first.id)
        default:
            // The ridership and the end are read.
            break
        }
    }

    /// Runs time until the step on screen is done, at most two game days;
    /// fails if it never is.
    @MainActor
    private static func runUntilFares(_ session: GameSession, line: UInt = #line) {
        let end = session.world.clock.now.seconds + 2 * GameTime.secondsPerDay
        while !session.isTutorialStepDone, session.world.clock.now.seconds < end {
            session.advance(realElapsed: GameSession.maximumStepDuration)
        }
        XCTAssertTrue(session.isTutorialStepDone, "no fares in two days", line: line)
    }

    /// The two stations built last, in the order built.
    @MainActor
    private static func newStations(_ session: GameSession) -> (first: Station, second: Station) {
        let stations = Array(session.world.stations.suffix(2))
        return (stations[0], stations[1])
    }

    /// Walks the standard actions until step `id` is on screen.
    @MainActor
    private static func walk(_ session: GameSession, to id: String, line: UInt = #line) {
        var steps = 0
        while let tutorial = session.tutorial, tutorial.step.id != id, steps < stepIDs.count {
            carryOut(tutorial.step.id, in: session)
            session.showNextTutorialStep()
            steps += 1
        }
        XCTAssertEqual(session.tutorial?.step.id, id, line: line)
    }

    /// The track step waits for track drawn and built while the tutorial is
    /// on screen, not track that was already there; choosing another tool
    /// undoes the first step's goal.
    func testGoalsAreReadFromTheWorldAndTheSessionAsTheyAreNow() async throws {
        var world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 14_336, y: 2_048))
        try world.buildTrackEdge(from: a, to: b)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.startTutorial()
            session.selectTool(.network)
            XCTAssertTrue(session.isTutorialStepDone)
            session.selectTool(.select)
            XCTAssertFalse(session.isTutorialStepDone, "the network tool is no longer chosen")
            session.selectTool(.network)
            session.showNextTutorialStep()
            session.mapDidMove()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.goal, .drawTrack)
            XCTAssertFalse(session.isTutorialStepDone, "the 192 m edge was there before the tutorial")

            // A new 192 m stretch: drawn, then built.
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 6_144), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 14_336, y: 6_144), reach: Self.reach)
            XCTAssertTrue(session.isTutorialStepDone)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.goal, .buildTrack)
            XCTAssertFalse(session.isTutorialStepDone, "a preview builds nothing")
            session.buildNetworkTrack()
            XCTAssertEqual(session.world.network.edges.count, 2)
            XCTAssertTrue(session.isTutorialStepDone)
        }
    }

    /// Back to a step the player finished leaves it finished, and it waits
    /// for Next rather than moving on by itself; Next passes over it again.
    func testBackToTheTrackStepKeepsItDone() async throws {
        let world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
        await MainActor.run {
            let session = GameSession(world: world)
            session.startTutorial()
            session.selectTool(.network)
            session.showNextTutorialStep()
            session.mapDidMove()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "track.draw")
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 14_336, y: 2_048), reach: Self.reach)
            session.buildNetworkTrack()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.mode", "the track step, done ahead, is passed")

            session.showPreviousTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "track.build")
            XCTAssertEqual(session.tutorial?.reachedByBack, true)
            XCTAssertEqual(session.world.network.edges.count, 1)
            XCTAssertTrue(session.isTutorialStepDone, "the track built for this step is still built")
            XCTAssertFalse(session.tutorialAdvancesByItself, "a step reached by Back waits for Next")
            session.showNextTutorialStep(from: 3)
            XCTAssertEqual(session.tutorial?.step.id, "track.build")
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.mode", "Next works again")
            XCTAssertEqual(session.tutorial?.reachedByBack, false)

            // Starting again snapshots the track that is there now.
            session.startTutorial()
            session.showNextTutorialStep()
            session.mapDidMove()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "track.draw")
            XCTAssertFalse(session.isTutorialStepDone, "starting again snapshots the track that is there now")
        }
    }

    /// Two stations built on the first station's step are the two a line
    /// needs: Next passes over the steps of the second.
    func testTwoStationsOnTheFirstStationStepAreEnough() async throws {
        let world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
        await MainActor.run {
            let session = GameSession(world: world)
            session.startTutorial()
            session.selectTool(.network)
            session.showNextTutorialStep()
            session.mapDidMove()
            session.showNextTutorialStep()
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 14_336, y: 2_048), reach: Self.reach)
            session.buildNetworkTrack()
            session.showNextTutorialStep()
            session.setNetworkMode(.platform)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.first.site")
            for x: Int64 in [4_096, 12_288] {
                session.tapNetwork(at: PlanPoint(x: x, y: 2_048), reach: Self.reach)
                session.addNetworkPlatform()
            }
            XCTAssertEqual(session.world.stations.count, 2)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "line.open")
        }
    }

    /// Stage E1: the map step waits for the player to move the map, which
    /// the map view reports; a report on another step, or with no tutorial,
    /// changes nothing, and going back keeps the step done. The world is
    /// never touched.
    func testTheMapStepWaitsForTheMapToMove() async throws {
        let world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
        await MainActor.run {
            let session = GameSession(world: world)
            session.mapDidMove()
            XCTAssertNil(session.tutorial)
            session.startTutorial()
            let first = session.tutorial
            session.mapDidMove()
            XCTAssertEqual(session.tutorial, first, "the first step is not about the map")
            session.selectTool(.network)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.index, 1)
            XCTAssertEqual(session.tutorial?.step.id, "map.move")
            XCTAssertFalse(session.isTutorialStepDone, "moving the map on an earlier step does not count")

            session.mapDidMove()
            XCTAssertTrue(session.isTutorialStepDone)
            let moved = session.tutorial
            session.mapDidMove()
            XCTAssertEqual(session.tutorial, moved, "only the first move changes the session")
            session.showPreviousTutorialStep()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "track.draw", "the map step, still done, is passed")
            XCTAssertEqual(session.world.network.edges.count, 0, "nothing built")
        }
    }

    /// Back goes to the step before (none on the first), Skip ends the
    /// tutorial at any step, and starting again begins at the first step.
    /// None of them changes the world.
    func testBackSkipAndStartingAgain() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            session.startTutorial()
            session.showPreviousTutorialStep()
            XCTAssertEqual(session.tutorial?.index, 0, "no step before the first")

            session.selectTool(.network)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.index, 1)
            XCTAssertEqual(session.tutorial?.isFirstStep, false)
            session.showPreviousTutorialStep()
            XCTAssertEqual(session.tutorial?.index, 0)
            XCTAssertTrue(session.isTutorialStepDone, "the network tool is still chosen")

            session.showNextTutorialStep()
            session.startTutorial()
            XCTAssertEqual(session.tutorial?.index, 0, "from the first step again")

            session.skipTutorial()
            XCTAssertNil(session.tutorial)
            XCTAssertFalse(session.isTutorialStepDone)
            session.showNextTutorialStep()
            session.showPreviousTutorialStep()
            session.skipTutorialStep()
            XCTAssertNil(session.tutorial, "nothing to move through")
            XCTAssertEqual(session.world, world)
        }
    }

    /// The game menu's Tutorial in a game being built in: what was picked
    /// before (a stretch's start and end, a line's stations, a selection)
    /// is dropped, so no step is passed as done by what the player did
    /// before the tutorial began (NEXT_PRIORITIES §2: a step was passed
    /// when the tutorial was started again from the menu).
    func testStartingFromTheMenuDropsWhatWasPickedBefore() async throws {
        await MainActor.run {
            let session = GameSession(world: GameWorld.newGame(), language: .english)
            session.selectTool(.network)
            session.tapNetwork(at: Self.point(2, in: session), reach: Self.reach)
            session.tapNetwork(at: Self.point(13, in: session), reach: Self.reach)
            XCTAssertNotNil(session.networkPreview)
            session.startTutorial()
            XCTAssertNil(session.networkStart)
            XCTAssertNil(session.networkEnd)
            XCTAssertNil(session.networkPreview)
            session.showNextTutorialStep()
            session.mapDidMove()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "track.draw", "not passed over to track.build")
            XCTAssertFalse(session.isTutorialStepDone)
        }
    }

    /// Skip keeps the tutorial (TestFlight 54.1; decision 188, later fix):
    /// the game menu takes it up again at the same step, where what was
    /// built in the tutorial still counts, so nothing is built twice; Start
    /// Over drops it. The launcher is told the step to take it up at.
    func testASkippedTutorialIsTakenUpAgainAtTheSameStep() async throws {
        await MainActor.run {
            let session = GameSession(world: GameWorld.newGame(), language: .english)
            var noted: [String?] = []
            session.onTutorialStepToResume = { noted.append($0) }
            session.resumeTutorial()
            XCTAssertNil(session.tutorial, "nothing skipped to take up")
            session.startTutorial()
            Self.walk(session, to: "station.second.site")
            let skipped = session.tutorial
            session.skipTutorial()
            XCTAssertNil(session.tutorial)
            XCTAssertEqual(session.skippedTutorial, skipped)
            XCTAssertEqual(noted.last, "station.second.site")
            session.skipTutorial()
            XCTAssertEqual(session.skippedTutorial, skipped, "a second Skip keeps it")

            // Built while the tutorial was away: the step's own place is
            // still to pick, as the place is the session's.
            session.selectTool(.select)
            session.resumeTutorial()
            XCTAssertNil(session.skippedTutorial)
            XCTAssertEqual(session.tutorial?.step.id, "station.second.site")
            XCTAssertEqual(session.tutorial?.index, skipped?.index)
            XCTAssertEqual(noted.last, "station.second.site", "the same step")
            XCTAssertFalse(session.isTutorialStepDone)
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: Self.point(11, in: session), reach: Self.reach)
            XCTAssertTrue(session.isTutorialStepDone)
            session.showNextTutorialStep()
            Self.carryOut("station.second.build", in: session)
            XCTAssertTrue(session.isTutorialStepDone, "the first station, built before Skip, still counts")
            XCTAssertEqual(session.world.stations.count, 2)
            // The steps before are still done.
            session.showPreviousTutorialStep()
            session.showPreviousTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.first.build")
            XCTAssertTrue(session.isTutorialStepDone)

            session.skipTutorial()
            session.startTutorial()
            XCTAssertNil(session.skippedTutorial, "Start Over drops it")
            XCTAssertEqual(session.tutorial?.index, 0)
            XCTAssertEqual(noted.last, "build.network")
        }
    }

    /// The tutorial's step is kept between launches (decision 188, later
    /// fix): skipped, or on screen when the game is left, it is offered in
    /// the next game at that step, its chapter read from the world as it
    /// is, so what was built before is not asked for again. Finishing it
    /// forgets it.
    func testTheTutorialIsTakenUpAgainInALaterLaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TutorialSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            var launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
            launcher.startTutorial()
            var session = try XCTUnwrap(launcher.session)
            Self.walk(session, to: "station.second.site")
            XCTAssertEqual(launcher.preferences.tutorialStepToResume, "station.second.site", "on screen")
            session.skipTutorial()
            XCTAssertEqual(launcher.preferences.tutorialStepToResume, "station.second.site", "skipped")
            launcher.returnToStart()

            launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
            XCTAssertEqual(launcher.preferences.tutorialStepToResume, "station.second.site")
            launcher.continueGame()
            session = try XCTUnwrap(launcher.session)
            XCTAssertNil(session.tutorial)
            XCTAssertEqual(session.skippedTutorial?.step.id, "station.second.site")
            XCTAssertEqual(session.world.stations.count, 1)
            session.resumeTutorial()
            XCTAssertEqual(session.tutorial?.step.id, "station.second.site")
            XCTAssertFalse(session.isTutorialStepDone)
            // One more station, not two: the one built before counts.
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: Self.point(11, in: session), reach: Self.reach)
            XCTAssertTrue(session.isTutorialStepDone)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.second.build")
            Self.carryOut("station.second.build", in: session)
            XCTAssertTrue(session.isTutorialStepDone)
            // The steps before it read the world as it is.
            session.showPreviousTutorialStep()
            session.showPreviousTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.first.build")
            XCTAssertTrue(session.isTutorialStepDone)
            session.showNextTutorialStep()
            session.showNextTutorialStep()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "line.open", "the line chapter asks for a new line")
            XCTAssertFalse(session.isTutorialStepDone)
            launcher.returnToStart()

            launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
            XCTAssertEqual(launcher.preferences.tutorialStepToResume, "line.open", "on screen when left")
            launcher.continueGame()
            session = try XCTUnwrap(launcher.session)
            session.resumeTutorial()
            Self.walk(session, to: "end")
            session.showNextTutorialStep()
            XCTAssertNil(session.tutorial)
            XCTAssertNil(launcher.preferences.tutorialStepToResume, "finished")
            XCTAssertTrue(launcher.preferences.tutorialCompleted)

            launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
            launcher.continueGame()
            XCTAssertNil(launcher.session?.skippedTutorial)
        }
    }

    /// The start screen's tutorial entry starts a new game on the first
    /// step, keeping the autosave as starting a new game does; the
    /// tutorial's game keeps no holidays (decision 154), no building
    /// materials (decision 157), no slowing of the doors in a crowd
    /// (decision 169), no flexible dispatch (decision 172) and no keeping
    /// left (decision 202).
    func testTheStartScreenStartsANewGameWithTheTutorial() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TutorialSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
            launcher.startTutorial()
            let session = try XCTUnwrap(launcher.session)
            // A new game, without its holidays (decision 154), its
            // building materials (decision 157), its crowded doors
            // (decision 169), its flexible dispatch (decision 172), its
            // keeping left (decision 202), its realistic operation
            // (decision 207), its block sections (decision 212) or its
            // curve speed limits (decision 217) or its real car lengths
            // (decision 227).
            var expected = GameWorld.newGame(eventSeed: try XCTUnwrap(session.world.demandEvents?.seed))
            expected.setDisruptions(nil)
            expected.setBuildingMaterials(false)
            expected.setDoorCrowding(false)
            expected.setRollingStockEconomics(false)
            expected.setFlexDispatch(false)
            expected.setKeepLeft(false)
            expected.setRealisticOperation(false)
            expected.setBlockSections(false)
            expected.setCurveSpeedLimits(false)
            expected.setRealCarLengths(false)
            expected.setTourism(nil)
            expected.setCityRequests(seed: nil)
            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.tutorial?.index, 0)
            XCTAssertEqual(session.tutorial?.steps, Tutorial.standardSteps)
        }
    }

    /// Debug builds' `-tutorial-step`, for the UI tests of a later step's
    /// screen: the tutorial's game at that step, over what the steps before
    /// it build, waiting for the step's own action; an unknown step starts
    /// at the first.
    func testTheTutorialStartsAtALaterStepOverWhatTheStepsBeforeBuild() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TutorialSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
            launcher.startTutorial(atStep: "line.open")
            var session = try XCTUnwrap(launcher.session)
            XCTAssertEqual(session.tutorial?.step.id, "line.open")
            XCTAssertEqual(session.tutorial?.isFirstStep, false)
            XCTAssertEqual(session.world.stations.count, 2)
            XCTAssertEqual(session.world.network.edges.count, 1, "one stretch")
            XCTAssertNil(session.networkEdgePoint, "no bubble left on a station")
            XCTAssertEqual(session.tool, .network)
            XCTAssertFalse(session.isTutorialStepDone)
            session.startPickingLineStops(announces: false)
            XCTAssertTrue(session.isTutorialStepDone)
            // Begun after the stations chapter, every station is one to tap.
            XCTAssertEqual(session.tutorialPlacesToTap, [])
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "line.stations")
            XCTAssertEqual(session.tutorialPlacesToTap, session.world.stations.map(\.location))

            launcher.startTutorial(atStep: "line.create")
            session = try XCTUnwrap(launcher.session)
            XCTAssertEqual(session.tutorial?.step.id, "line.create")
            XCTAssertEqual(session.lineDraftStops.count, 2)
            XCTAssertFalse(session.isTutorialStepDone, "the line is still to make")
            session.createLineFromDraft()
            XCTAssertTrue(session.isTutorialStepDone)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "line.staff")

            launcher.startTutorial(atStep: "line.staff")
            session = try XCTUnwrap(launcher.session)
            XCTAssertEqual(session.tutorial?.step.id, "line.staff")
            XCTAssertEqual(session.world.lines.count, 1)
            XCTAssertFalse(session.isTutorialStepDone, "the line has no trains")
            session.staffSelectedLine(headway: 10)
            XCTAssertTrue(session.isTutorialStepDone)

            launcher.startTutorial(atStep: "build.done")
            session = try XCTUnwrap(launcher.session)
            XCTAssertEqual(session.tutorial?.step.id, "build.done")
            XCTAssertFalse(session.world.trains.isEmpty)
            XCTAssertFalse(session.isTutorialStepDone, "the network tool is still chosen")

            launcher.startTutorial(atStep: "no.such.step")
            XCTAssertEqual(launcher.session?.tutorial?.index, 0)
            XCTAssertEqual(launcher.session?.world.stations.isEmpty, true)
        }
    }

    /// Every target has its own stable name, and the tool picker's buttons
    /// are named as their accessibility identifiers (`tool.<tool>`).
    func testEveryTargetHasItsOwnStableName() {
        let names = TutorialTarget.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names, [
            "tool.select", "tool.network", "tool.train", "tool.building", "train.buy", "line.staff.start", "network.modes",
            "panel.action", "map", "map.zoom", "hud.lines", "hud.speed", "hud.cash", "hud.menu", "line.draft.pick",
            "line.draft.create", "panel.details", "panel.side", "map.build.confirm", "inspector.ridership", "line.loss",
            "line.loss.fix",
        ])
        for tool in ConstructionTool.allCases {
            XCTAssertEqual(TutorialTarget(tool: tool)?.rawValue, "tool.\(tool)", "every tool has its button")
        }
    }

    /// Each step reads in both languages, the Chinese written out by hand,
    /// as plain text (the reference's cards hold HTML), short (decision
    /// 188: each title the instruction, each body a line), and names
    /// controls it can outline once each.
    func testTheStepsReadInBothLanguages() async {
        let steps = Tutorial.standardSteps
        // The caps leave out the distance note, on only where demand is by
        // distance: the steps over a world without it.
        let plain = await MainActor.run {
            var world = GameWorld.newGame()
            world.setDistanceDemand(false)
            let session = GameSession(world: world)
            session.startTutorial()
            return session.tutorial?.steps ?? []
        }
        XCTAssertEqual(plain.map(\.id), Self.stepIDs)
        XCTAssertEqual(steps.map(\.id), Self.stepIDs)
        XCTAssertEqual(Set(steps.map(\.id)).count, steps.count)
        XCTAssertEqual(steps.map { $0.title(in: .english) }, [
            "Tap Network", "Zoom out to see the town", "Tap the start, then the end", "Tap ✓ to build the track",
            "Tap Platform", "Tap your track near one end", "Tap ✓ to build the station", "Tap the track near the other end",
            "Tap ✓ for the second station",
            "Tap Lines", "Tap one station, then the other", "Tap ✓ to create the line",
            "Tap Buy … and Start Service", "Tap Done to stop building", "Tap \u{25B6}\u{FE0E} to run time", "Wait for your first fares",
            "Tap Lines to check your line", "Read your line's card",
            "Tap one of your stations", "Tap Ridership to see who rides", "That's the tour",
        ])
        XCTAssertEqual(steps.map { $0.title(in: .traditionalChinese) }, [
            "點「路網」", "縮小地圖看看城鎮", "點起點，再點終點", "按 ✓ 蓋好軌道",
            "點「月台」", "點軌道靠近一端的地方", "按 ✓ 蓋車站", "點軌道另一端的地方", "按 ✓ 蓋第二座車站",
            "點「路線」", "點一座車站，再點另一座", "按 ✓ 建立路線",
            "按「購買…列並開始營運」", "點「完成」結束建造", "按 \u{25B6}\u{FE0E} 讓時間走", "等第一筆車資進帳",
            "點「路線」看營運收支", "看懂路線卡",
            "點你的一座車站", "點「客源」看誰在搭車", "導覽結束",
        ])
        XCTAssertEqual(steps.map(\.chapter), [
            .track, .track, .track, .track, .stations, .stations, .stations, .stations, .stations,
            .line, .line, .line, .service, .service, .service, .service, .service, .service,
            .passengers, .passengers, .passengers,
        ])
        XCTAssertEqual(steps[0].body(in: .traditionalChinese), "目標：蓋一條賺到第一筆車資的路線。軌道和車站都用「路網」蓋。")
        XCTAssertTrue(steps[2].body(in: .english).contains("at least \(Tutorial.minimumTrackMetres) m"))
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertEqual(Set(steps.map { $0.title(in: language) }).count, steps.count, "titles are unique")
        }
        for step in plain {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                XCTAssertFalse(step.title(in: language).isEmpty, step.id)
                XCTAssertFalse(step.body(in: language).isEmpty, step.id)
                XCTAssertFalse(step.body(in: language).contains("<"), "\(step.id) is plain text")
            }
            XCTAssertLessThanOrEqual(step.body(in: .english).count, 90, step.id)
            XCTAssertLessThanOrEqual(step.body(in: .traditionalChinese).count, 36, step.id)
            XCTAssertLessThanOrEqual(step.title(in: .english).count, 34, step.id)
            XCTAssertLessThanOrEqual(step.title(in: .traditionalChinese).count, 14, step.id)
            XCTAssertNotEqual(step.body(in: .traditionalChinese), step.body(in: .english), step.id)
            XCTAssertFalse(step.targets.isEmpty, "\(step.id) points at something")
            XCTAssertEqual(Set(step.targets).count, step.targets.count, step.id)
        }
    }

    /// The second-station step says longer trips ride more, up to 2 km,
    /// only where short ones walk: a world with demand by distance
    /// (decision 137). A demo or a save from before it has none, and the
    /// step leaves it out.
    func testTheStepsSayShortTripsWalkOnlyWhereTheyDo() async throws {
        await MainActor.run {
            @MainActor func secondStation(_ session: GameSession) -> String {
                session.startTutorial()
                return session.tutorial?.steps.first { $0.id == "station.second.site" }?.body(in: .english) ?? ""
            }
            let distanced = GameSession(world: .newGame(), language: .english)
            XCTAssertTrue(distanced.world.distanceDemand)
            XCTAssertTrue(secondStation(distanced).contains("up to 2 km"))
            XCTAssertEqual(distanced.tutorial?.steps, Tutorial.standardSteps)

            var world = GameWorld.newGame()
            world.setDistanceDemand(false)
            let plain = GameSession(world: world, language: .english)
            let body = secondStation(plain)
            XCTAssertFalse(body.contains("2 km"), body)
            XCTAssertTrue(body.hasSuffix("needs two stations."), body)
        }
    }

    /// Done resumes the clock the network tool paused (decision 99), and
    /// the time step is passed; time paused by hand shows it, and it waits
    /// for time to run. Pausing again undoes it.
    func testTheTimeStepWaitsForTimeToRunAndIsPassedWhenItDoes() async throws {
        await MainActor.run {
            let session = GameSession(world: .newGame(), language: .english)
            session.startTutorial()
            Self.walk(session, to: "build.done")
            XCTAssertTrue(session.world.clock.isPaused, "paused while building")
            // Paused by hand: the speed is the player's, Done leaves it.
            session.setSpeed(.paused)
            session.selectTool(.select)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "time.play")
            XCTAssertFalse(session.isTutorialStepDone)
            session.togglePause()
            XCTAssertTrue(session.isTutorialStepDone, "resumed")
            session.togglePause()
            XCTAssertFalse(session.isTutorialStepDone, "paused again")
            session.setSpeed(.fast)
            XCTAssertTrue(session.isTutorialStepDone)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "first.fare")
        }
    }

    /// Decision 125: the fare step waits for fares settled since its
    /// chapter began; a free game charges none, so it is passed.
    func testTheFareStepWaitsForFaresUnlessTheGameIsFree() async throws {
        var free = GameWorld.newGame()
        free.setEconomyMode(.free)
        for (world, charges) in [(GameWorld.newGame(), true), (free, false)] {
            await MainActor.run { [world] in
                let session = GameSession(world: world, language: .english)
                session.startTutorial()
                Self.walk(session, to: "build.done")
                session.selectTool(.select)
                session.showNextTutorialStep()
                guard charges else {
                    XCTAssertEqual(session.tutorial?.step.id, "line.card.open", "nothing to wait for")
                    return
                }
                XCTAssertEqual(session.tutorial?.step.id, "first.fare")
                XCTAssertFalse(session.isTutorialStepDone)
                XCTAssertEqual(session.tutorialHint?.text, "Trains start at 06:00. Tap the speed beside \u{25B6}\u{FE0E} to go faster.")
                Self.runUntilFares(session)
                // Going back and on again keeps the fares it waited for.
                session.showPreviousTutorialStep()
                XCTAssertEqual(session.tutorial?.step.id, "time.play")
                session.showNextTutorialStep()
                XCTAssertEqual(session.tutorial?.step.id, "line.card.open", "the fares are still in")
            }
        }
    }

    /// Starting service needs both a train given to the line and the line
    /// set to run trains, in either order, and a train that was already
    /// assigned when the step was shown does not count. The lines panel's
    /// one step does both (decision 125); doing it by hand still counts.
    func testStartingServiceNeedsAnAssignedTrainAndATrainWanted() async throws {
        await MainActor.run {
            let session = GameSession(world: DemoWorld.make(in: .english), language: .english)
            session.startTutorial()
            Self.walk(session, to: "line.staff")
            XCTAssertEqual(session.tutorial?.step.goal, .startService)
            XCTAssertFalse(session.isTutorialStepDone, "the demo's lines already run their own trains")
            session.selectTool(.train)
            session.purchaseTrain()
            session.selectStation(Self.newStations(session).first.id)
            session.placeSelectedTrain()
            XCTAssertFalse(session.isTutorialStepDone, "a train placed is not in service")

            session.setSelectedLineTrains(1, at: .offPeak)
            XCTAssertFalse(session.isTutorialStepDone, "wanted, but no train assigned")
            session.assignSelectedTrainToSelectedLine()
            XCTAssertTrue(session.isTutorialStepDone)
            session.unassignSelectedTrain()
            XCTAssertFalse(session.isTutorialStepDone, "no longer assigned")
        }
    }

    /// A step done before it is shown (a fast player, the map's ✓ while
    /// the step before waits its moment) is passed: Next and the step
    /// moving on by itself land on the first that is not done.
    func testAStepDoneAheadIsPassed() async throws {
        await MainActor.run {
            let session = GameSession(world: .newGame(), language: .english)
            session.startTutorial()
            Self.walk(session, to: "track.draw")
            session.tapNetwork(at: Self.point(2, in: session), reach: Self.reach)
            session.tapNetwork(at: Self.point(13, in: session), reach: Self.reach)
            session.buildNetworkTrack()
            session.showNextTutorialStep(from: 2)
            XCTAssertEqual(session.tutorial?.step.id, "station.mode", "the build step is passed")

            Self.walk(session, to: "line.open")
            let (first, second) = Self.newStations(session)
            session.startPickingLineStops(announces: false)
            session.tapMap(at: first.point, reach: Self.reach)
            session.tapMap(at: second.point, reach: Self.reach)
            session.createLineFromDraft()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "line.staff", "picking and creating are passed")
        }
    }

    /// The first stretch must hold two stations (decision 188): a short
    /// one is not enough, the card says to make it longer, and lengthening
    /// what was built counts with it.
    func testTheTrackMustHoldTwoStations() async throws {
        let world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
        await MainActor.run {
            let session = GameSession(world: world, language: .english)
            session.startTutorial()
            Self.walk(session, to: "track.draw")
            // 64 m.
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 6_144, y: 2_048), reach: Self.reach)
            XCTAssertNotNil(session.networkPreview)
            XCTAssertFalse(session.isTutorialStepDone, "too short")
            XCTAssertEqual(session.tutorialHint, TutorialHint("Make it longer: at least 160 m, so two stations fit."))
            session.buildNetworkTrack()
            XCTAssertEqual(session.world.network.edges.count, 1)
            XCTAssertFalse(session.isTutorialStepDone)
            XCTAssertEqual(session.tutorialHint?.text, "Too short for two stations. Tap farther on from its end, then ✓.")
            // 128 m more from its end.
            session.tapNetwork(at: PlanPoint(x: 14_336, y: 2_048), reach: Self.reach)
            XCTAssertTrue(session.isTutorialStepDone, "the two stretches hold two stations")
            session.buildNetworkTrack()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.mode")
        }
    }

    /// "Skip this step" moves on without the step's goal, passing what is
    /// done; it does nothing on a read step or the last, and never finishes
    /// the tutorial (decision 177).
    func testSkippingAStepMovesOnWithoutItsGoal() async throws {
        await MainActor.run {
            let session = GameSession(world: .newGame(), language: .english)
            var finished = false
            session.onTutorialCompleted = { finished = true }
            session.startTutorial()
            session.skipTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "map.move")
            XCTAssertEqual(session.tool, .select, "the goal was not done for the player")
            var skips = 0
            while session.tutorial?.step.goal != .read, skips < Self.stepIDs.count {
                session.skipTutorialStep()
                skips += 1
            }
            XCTAssertEqual(session.tutorial?.step.id, "line.card.read")
            session.skipTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "line.card.read", "a read step has Next")
            session.showNextTutorialStep()
            session.skipTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.ridership")
            session.showNextTutorialStep()
            session.skipTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "end", "the last step has Finish")
            XCTAssertFalse(finished)
            XCTAssertTrue(session.world.stations.isEmpty, "skipping builds nothing")
        }
    }

    /// The step moving on by itself calls Next for the step it was done
    /// on: once that step is gone (Next tapped, or Back), it does nothing.
    func testNextFromAnOldStepDoesNothing() async throws {
        await MainActor.run {
            let session = GameSession(world: .newGame(), language: .english)
            session.startTutorial()
            session.showNextTutorialStep(from: 0)
            XCTAssertEqual(session.tutorial?.index, 0, "not done")
            session.selectTool(.network)
            session.showNextTutorialStep(from: 0)
            XCTAssertEqual(session.tutorial?.index, 1)
            session.showNextTutorialStep(from: 0)
            XCTAssertEqual(session.tutorial?.index, 1, "a late call")
            session.showPreviousTutorialStep()
            session.showNextTutorialStep(from: 0)
            XCTAssertEqual(session.tutorial?.index, 0, "reached by Back: it waits for Next")
        }
    }

    /// Each step's setup runs when it is first shown going forward: the
    /// end flag and the bubble left on the first station go, Lay is chosen,
    /// the line's draft and the selection are let go of; the first
    /// station's message stays. Back sets nothing up.
    func testTheStepsSetUpWhatTheyNeedWithoutWipingTheMessage() async throws {
        await MainActor.run {
            let session = GameSession(world: .newGame(), language: .english)
            session.startTutorial()
            Self.walk(session, to: "map.move")
            session.setNetworkMode(.remove)
            session.mapDidMove()
            session.showNextTutorialStep()
            XCTAssertEqual(session.networkMode, .build, "the track step lays track")

            Self.walk(session, to: "station.second.site")
            XCTAssertNil(session.networkEdgePoint)
            XCTAssertNotNil(session.platformStationID, "only the bubble goes")
            XCTAssertEqual(session.message?.text.contains("Within 800 m"), true)
            session.tapNetwork(at: Self.point(11, in: session), reach: Self.reach)
            session.showPreviousTutorialStep()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "station.second.build", "the site picked is kept, and the step passed")
            XCTAssertNotNil(session.networkEdgePoint)

            Self.walk(session, to: "line.open")
            XCTAssertNil(session.networkEdgePoint)
            XCTAssertTrue(session.lineDraft.isEmpty)
            XCTAssertFalse(session.isPickingLineStops)

            Self.walk(session, to: "station.select")
            XCTAssertNil(session.selectedStationID)
        }
    }

    /// Decision 188, later fix (#491's gap): after the first fares the
    /// tutorial has the player open the lines panel at the line it made
    /// and points at the line's card, its fares against its costs and the
    /// fix beside the first reason it loses money (decision 194), scrolled
    /// into view; the next step, on the map, closes the panel again.
    func testTheLineCardStepsOpenTheLinesPanelAtTheTutorialsLine() async throws {
        try await MainActor.run {
            let session = GameSession(world: DemoWorld.make(in: .english), language: .english)
            session.startTutorial()
            Self.walk(session, to: "first.fare")
            let made = session.selectedLineID
            XCTAssertNotNil(made)
            XCTAssertEqual(made, session.world.lines.last?.id, "the line the tutorial made")
            Self.runUntilFares(session)
            session.showNextTutorialStep()

            XCTAssertEqual(session.tutorial?.step.id, "line.card.open")
            let open = try XCTUnwrap(session.tutorial?.step)
            XCTAssertEqual(open.targets, [.linesButton])
            XCTAssertNil(open.panel, "the player opens it")
            XCTAssertFalse(session.isTutorialStepDone, "the panel is closed")
            session.linesPanelDidChange(isShown: true)
            XCTAssertTrue(session.isTutorialStepDone)
            XCTAssertTrue(session.tutorialAdvancesByItself)
            session.linesPanelDidChange(isShown: false)
            XCTAssertFalse(session.isTutorialStepDone, "closed again")
            session.linesPanelDidChange(isShown: true)
            session.showNextTutorialStep(from: session.tutorial?.index ?? 0)

            let read = try XCTUnwrap(session.tutorial?.step)
            XCTAssertEqual(read.id, "line.card.read")
            XCTAssertEqual(read.chapter, .service)
            XCTAssertEqual(read.goal, .read)
            XCTAssertEqual(read.panel, .lines)
            XCTAssertEqual(read.targets, [.lineLoss, .lineLossFix, .sidePanel])
            XCTAssertEqual(read.revealsInPanel, .lineLoss, "the panel scrolls to the card")
            XCTAssertEqual(TutorialTarget.lineLoss.rawValue, "line.loss", "the card's accessibility identifier")
            XCTAssertEqual(session.selectedLineID, made)
            XCTAssertTrue(read.body(in: .english).contains("fix"))
            XCTAssertTrue(read.body(in: .traditionalChinese).contains("一鍵修正"))
            session.showNextTutorialStep()

            XCTAssertEqual(session.tutorial?.step.id, "station.select")
            XCTAssertEqual(session.tutorial?.step.panel, .closed, "the map gets the screen")
        }
    }

    /// The lines panel step selects the newest line when none is selected
    /// (the `Ci/` line steps' `openUI`), and keeps the player's choice.
    func testTheLineCardStepSelectsTheNewestLineOnlyWhenNoneIs() async throws {
        await MainActor.run {
            let session = GameSession(world: DemoWorld.make(in: .english), language: .english)
            let lines = session.world.lines.map(\.id)
            XCTAssertGreaterThan(lines.count, 1)
            session.selectLine(lines[0])
            session.startTutorial(atStep: "line.card.open")
            XCTAssertEqual(session.tutorial?.step.id, "line.card.open")
            XCTAssertEqual(session.selectedLineID, lines[0], "the player's line is kept")
        }
    }

    /// The card says what is wrong with what the player did, as a problem
    /// (which offers to skip the step), or what to do next.
    func testHintsSayWhatIsMissing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TutorialSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let session = GameSession(world: .newGame(), language: .english)
            session.startTutorial()
            Self.walk(session, to: "track.draw")
            XCTAssertNil(session.tutorialHint, "the title says it")
            // 8 m: refused.
            session.tapNetwork(at: Self.point(2, in: session), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: Self.point(2, in: session).x + 512, y: Self.point(2, in: session).y), reach: Self.reach)
            let problem = try XCTUnwrap(session.networkPreview?.problem)
            XCTAssertEqual(session.tutorialHint, TutorialHint(problem, isProblem: true))
            session.clearNetworkDraft()

            Self.walk(session, to: "station.second.site")
            // Beside the first station.
            session.tapNetwork(at: Self.point(4, in: session), reach: Self.reach)
            let first = try XCTUnwrap(session.world.stations.last)
            XCTAssertEqual(session.tutorialHint, TutorialHint("That spot joins “\(first.name)”. Tap farther along the track.", isProblem: true))
            session.tapNetwork(at: Self.point(11, in: session), reach: Self.reach)
            XCTAssertNil(session.tutorialHint, "done")
            session.showNextTutorialStep()
            // Off the track, then ✓.
            session.tapNetwork(at: PlanPoint(x: 1_024, y: 1_024), reach: Self.reach)
            XCTAssertEqual(session.tutorialHint?.text, "Tap the track again to pick the spot.")
            session.addNetworkPlatform()
            XCTAssertEqual(session.tutorialHint, TutorialHint("Tap the track where the platform goes.", isProblem: true))

            // Two stations no track joins.
            let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
            launcher.startTutorial(atStep: "line.open")
            let lines = try XCTUnwrap(launcher.session)
            let bounds = lines.world.bounds
            lines.setNetworkMode(.build)
            lines.tapNetwork(at: PlanPoint(x: bounds.width / 2 - 6 * Self.tile, y: bounds.height / 2 + 4 * Self.tile), reach: Self.reach)
            lines.tapNetwork(at: PlanPoint(x: bounds.width / 2 + 6 * Self.tile, y: bounds.height / 2 + 4 * Self.tile), reach: Self.reach)
            lines.buildNetworkTrack()
            lines.setNetworkMode(.platform)
            lines.tapNetwork(at: PlanPoint(x: bounds.width / 2, y: bounds.height / 2 + 4 * Self.tile), reach: Self.reach)
            lines.addNetworkPlatform()
            XCTAssertEqual(lines.world.stations.count, 3)
            lines.startPickingLineStops(announces: false)
            lines.showNextTutorialStep()
            XCTAssertEqual(lines.tutorial?.step.id, "line.stations")
            lines.tapMap(at: lines.world.stations[0].point, reach: Self.reach)
            lines.tapMap(at: lines.world.stations[2].point, reach: Self.reach)
            XCTAssertEqual(lines.tutorialHint?.isProblem, true)
            XCTAssertEqual(lines.tutorialHint?.text.hasPrefix("No track joins these stations."), true)
            lines.stopPickingLineStops()
            lines.clearLineDraft()
            XCTAssertEqual(lines.tutorialHint?.text, "Tap Lines to pick stations again.")

            // Time paused while waiting for fares.
            launcher.startTutorial(atStep: "build.done")
            let fares = try XCTUnwrap(launcher.session)
            fares.selectTool(.select)
            fares.setSpeed(.paused)
            fares.showNextTutorialStep()
            fares.togglePause()
            fares.showNextTutorialStep()
            XCTAssertEqual(fares.tutorial?.step.id, "first.fare")
            fares.setSpeed(.paused)
            XCTAssertEqual(fares.tutorialHint, TutorialHint("Time is paused. Tap \u{25B6}\u{FE0E}."))
        }
    }

    /// Decision 188: the details card opens only for the steps that point
    /// into it; the lines panel's steps open it, and its picking starts by
    /// itself on the line steps.
    func testOnlyTheModeAndRidershipStepsNeedTheDetailsCard() {
        let steps = Tutorial.standardSteps
        XCTAssertEqual(steps.filter(\.usesDetailsCard).map(\.id), ["station.mode", "station.ridership"])
        XCTAssertEqual(steps.filter { $0.panel == .lines }.map(\.id), ["line.stations", "line.create", "line.staff", "line.card.read"])
        XCTAssertEqual(steps.filter { $0.panel == .closed }.map(\.id), ["build.network", "build.done", "station.select"])
        XCTAssertEqual(steps.filter(\.picksLineStops).map(\.id), ["line.open", "line.stations"])
        XCTAssertEqual(steps.compactMap(\.revealsInPanel), [.staffLine, .lineLoss], "the line is created on the map (decision 100, later)")
        XCTAssertEqual(steps.map(\.skipOfferSeconds).filter { $0 != 20 }, [90])
    }

    /// Undo is off in the tutorial, so choosing Network there does not say
    /// that every edit can be undone; it still pauses.
    func testChoosingNetworkInTheTutorialLeavesOutThePauseMessage() async throws {
        await MainActor.run {
            let plain = GameSession(world: .newGame(), language: .english)
            plain.selectTool(.network)
            XCTAssertEqual(plain.message?.text.hasPrefix("Paused while you build"), true)

            let session = GameSession(world: .newGame(), language: .english)
            session.startTutorial()
            XCTAssertFalse(session.world.clock.isPaused)
            session.selectTool(.network)
            XCTAssertTrue(session.world.clock.isPaused)
            XCTAssertNil(session.message)
        }
    }
}
