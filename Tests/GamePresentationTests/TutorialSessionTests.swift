import Foundation
import GameCore
import GamePresentation
import XCTest

/// The tutorial (Stage C5): the step on screen, its text and the controls
/// it is about, Next waiting until the player has done what the step asks
/// (read from the world and the session), Back, Skip and starting again,
/// after the `Ci/` reference's guided tour.
final class TutorialSessionTests: XCTestCase {
    private static let reach: Int64 = 512
    private static let tile: Int64 = 1_024

    private static let stepIDs = [
        "build.network", "build.track", "map.move", "build.firstStation", "build.secondStation", "line.create",
        "line.staff", "time.speed", "first.fare", "station.ridership", "end",
    ]

    /// Next waits for each step's goal, in the order a first line is built
    /// and run: the network tool, track, moving the map, two stations, a
    /// line, its trains bought and set running in one step (decision 125),
    /// a change of speed and its first fares; the last two steps need only
    /// reading, and Done ends the tutorial.
    /// A new game and the demo map, which already has all of it, are both
    /// walked through: each goal asks for something new.
    func testNextWaitsForEachStepAndDoneEndsTheTutorial() async throws {
        for world in [GameWorld.newGame(), DemoWorld.make(in: .english)] {
            await MainActor.run { [world] in
                let session = GameSession(world: world)
                XCTAssertNil(session.tutorial)
                XCTAssertFalse(session.isTutorialStepDone, "no tutorial")
                session.startTutorial()
                XCTAssertEqual(session.tutorial?.steps.map(\.id), Self.stepIDs)
                XCTAssertEqual(session.tutorial?.isFirstStep, true)
                XCTAssertEqual(session.tutorial?.isLastStep, false)

                session.showNextTutorialStep()
                XCTAssertEqual(session.tutorial?.index, 0, "Next waits for the network tool")
                for index in Self.stepIDs.indices {
                    Self.carryOut(index, in: session)
                    if index < Self.stepIDs.count - 1 {
                        Self.advance(session)
                    }
                }
                XCTAssertEqual(session.tutorial?.isLastStep, true)
                session.showNextTutorialStep()
                XCTAssertNil(session.tutorial, "Done ends it")
            }
        }
    }

    /// Carries out the step on screen, checking its goal, its targets and
    /// that nothing short of the whole of it is enough.
    @MainActor
    private static func carryOut(_ index: Int, in session: GameSession) {
        // A new game's line goes through its first town, the middle of the
        // map, so its first fares come (decision 125); the demo's own lines
        // earn them, and its middle is taken. Only the track and station
        // steps use the place, all before the walk-through's line.
        let origin = session.world.lines.isEmpty && !session.world.land.isEmpty
            ? PlanPoint(x: session.world.bounds.width / 2 - 8 * Self.tile, y: session.world.bounds.height / 2 - 6 * Self.tile)
            : PlanPoint(x: 0, y: 0)
        func point(_ x: Int64, _ y: Int64) -> PlanPoint {
            PlanPoint(x: origin.x + x, y: origin.y + y)
        }
        let y = 6 * Self.tile
        switch index {
        case 0:
            Self.expect(session, step: 0, goal: .chooseTool(.network), targets: [.networkTool])
            session.selectTool(.network)
        case 1:
            // A stretch of track; the ends only preview it.
            Self.expect(session, step: 1, goal: .buildTrack, targets: [.map, .actionButton])
            session.tapNetwork(at: point(2 * Self.tile, y), reach: Self.reach)
            session.tapNetwork(at: point(7 * Self.tile, y), reach: Self.reach)
            XCTAssertFalse(session.isTutorialStepDone, "a preview builds nothing")
            session.buildNetworkTrack()
        case 2:
            // Moving the map (Stage E1): the map view reports it.
            Self.expect(session, step: 2, goal: .moveMap, targets: [.map, .zoomControls])
            session.mapDidMove()
        case 3:
            // The first station: a platform on that track.
            Self.expect(session, step: 3, goal: .buildStation, targets: [.networkModes, .map, .actionButton])
            session.setNetworkMode(.platform)
            session.tapNetwork(at: point(4 * Self.tile, y), reach: Self.reach)
            XCTAssertFalse(session.isTutorialStepDone, "picking the place builds nothing")
            session.addNetworkPlatform()
        case 4:
            // The second station, further along new track.
            Self.expect(session, step: 4, goal: .buildStation, targets: [.networkModes, .map, .actionButton])
            session.setNetworkMode(.build)
            session.tapNetwork(at: point(7 * Self.tile, y), reach: Self.reach)
            session.tapNetwork(at: point(13 * Self.tile, y), reach: Self.reach)
            session.buildNetworkTrack()
            XCTAssertFalse(session.isTutorialStepDone, "track is not a station")
            session.setNetworkMode(.platform)
            session.tapNetwork(at: point(11 * Self.tile, y), reach: Self.reach)
            session.addNetworkPlatform()
        case 5:
            // The line through both stations.
            Self.expect(session, step: 5, goal: .createLine, targets: [.linesButton])
            let (first, second) = Self.newStations(session)
            session.selectStation(first)
            session.addSelectedStationToLineDraft()
            session.selectStation(second)
            session.addSelectedStationToLineDraft()
            XCTAssertFalse(session.isTutorialStepDone, "a draft is not a line")
            session.createLineFromDraft()
        case 6:
            // Decision 125: the new line, still selected, gets its trains
            // in the lines panel's one step (decision 101).
            Self.expect(session, step: 6, goal: .startService, targets: [.staffLine, .linesButton])
            XCTAssertEqual(session.selectedLine?.trains.isEmpty, true)
            session.staffSelectedLine(headway: 10)
            XCTAssertFalse(session.selectedLine?.trains.isEmpty ?? true, "the line has its trains")
            XCTAssertEqual(session.selectedLine?.targetHeadways, TargetHeadways(peak: 10, offPeak: 10, low: 10))
        case 7:
            Self.expect(session, step: 7, goal: .changeSpeed, targets: [.speedControl])
            session.setSpeed(.fast)
        case 8:
            // Decision 125: the first fares, settled at the end of an hour.
            Self.expect(session, step: 8, goal: .earnFare, targets: [.cash, .speedControl])
            Self.runUntilFares(session)
        case 9:
            Self.expect(session, step: 9, goal: .read, targets: [.map])
        default:
            Self.expect(session, step: 10, goal: .read, targets: [.gameMenu])
        }
        XCTAssertTrue(session.isTutorialStepDone, "step \(index) is done")
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

    /// The two stations the walk-through built, in the order built.
    @MainActor
    private static func newStations(_ session: GameSession) -> (first: StationID, second: StationID) {
        let ids = session.world.stations.suffix(2).map(\.id)
        return (ids[0], ids[1])
    }

    /// The step on screen is `index`, with `goal` and `targets`, and not
    /// done yet unless reading is enough.
    @MainActor
    private static func expect(_ session: GameSession, step index: Int, goal: TutorialGoal, targets: [TutorialTarget], line: UInt = #line) {
        let step = session.tutorial?.step
        XCTAssertEqual(session.tutorial?.index, index, line: line)
        XCTAssertEqual(step?.id, Self.stepIDs[index], line: line)
        XCTAssertEqual(step?.goal, goal, line: line)
        XCTAssertEqual(step?.targets, targets, line: line)
        XCTAssertEqual(session.isTutorialStepDone, goal == .read, "step \(index) starts \(goal == .read ? "done" : "undone")", line: line)
    }

    /// Next, with the step done: the following step is on screen.
    @MainActor
    private static func advance(_ session: GameSession, line: UInt = #line) {
        let before = session.tutorial?.index
        XCTAssertTrue(session.isTutorialStepDone, line: line)
        session.showNextTutorialStep()
        XCTAssertEqual(session.tutorial?.index, before.map { $0 + 1 }, line: line)
    }

    /// The track step waits for track built while it is on screen, not
    /// track that was already there; choosing another tool undoes the
    /// first step's goal.
    func testGoalsAreReadFromTheWorldAndTheSessionAsTheyAreNow() async throws {
        var world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
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
            XCTAssertEqual(session.tutorial?.step.goal, .buildTrack)
            XCTAssertFalse(session.isTutorialStepDone, "the edge was there before the step")

            session.tapNetwork(at: PlanPoint(x: 6_144, y: 2_048), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 10_240, y: 2_048), reach: Self.reach)
            session.buildNetworkTrack()
            XCTAssertEqual(session.world.network.edges.count, 2)
            XCTAssertTrue(session.isTutorialStepDone)
        }
    }

    /// Back to a step the player finished leaves it finished: Next must not
    /// wait for a second stretch of track because the step was shown again.
    func testBackToTheTrackStepKeepsItDone() async throws {
        let world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
        await MainActor.run {
            let session = GameSession(world: world)
            session.startTutorial()
            session.selectTool(.network)
            session.showNextTutorialStep()
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 6_144, y: 2_048), reach: Self.reach)
            session.buildNetworkTrack()
            XCTAssertTrue(session.isTutorialStepDone)
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "map.move")

            session.showPreviousTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "build.track")
            XCTAssertEqual(session.world.network.edges.count, 1)
            XCTAssertTrue(session.isTutorialStepDone, "the track built for this step is still built")
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "map.move", "Next works again")

            // A step shown for the first time still waits for its own track.
            session.showPreviousTutorialStep()
            session.showPreviousTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "build.network")
            session.startTutorial()
            session.selectTool(.network)
            session.showNextTutorialStep()
            XCTAssertFalse(session.isTutorialStepDone, "starting again snapshots the track that is there now")
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
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 6_144, y: 2_048), reach: Self.reach)
            session.buildNetworkTrack()
            session.mapDidMove()
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "map.move")
            XCTAssertFalse(session.isTutorialStepDone, "moving the map on an earlier step does not count")

            session.mapDidMove()
            XCTAssertTrue(session.isTutorialStepDone)
            let moved = session.tutorial
            session.mapDidMove()
            XCTAssertEqual(session.tutorial, moved, "only the first move changes the session")
            session.showPreviousTutorialStep()
            session.showNextTutorialStep()
            XCTAssertTrue(session.isTutorialStepDone, "going back keeps the step done")
            session.showNextTutorialStep()
            XCTAssertEqual(session.tutorial?.step.id, "build.firstStation")
            XCTAssertEqual(session.world.network.edges.count, 1, "only the track the player built")
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
            XCTAssertNil(session.tutorial, "nothing to move through")
            XCTAssertEqual(session.world, world)
        }
    }

    /// The start screen's tutorial entry starts a new game on the first
    /// step, keeping the autosave as starting a new game does; the
    /// tutorial's game keeps no holidays (decision 154).
    func testTheStartScreenStartsANewGameWithTheTutorial() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TutorialSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run {
            let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
            launcher.startTutorial()
            let session = try XCTUnwrap(launcher.session)
            // A new game, without its holidays (decision 154).
            var expected = GameWorld.newGame(eventSeed: try XCTUnwrap(session.world.demandEvents?.seed))
            expected.setDisruptions(nil)
            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.tutorial?.index, 0)
            XCTAssertEqual(session.tutorial?.steps, Tutorial.standardSteps)
        }
    }

    /// Every target has its own stable name, and the tool picker's buttons
    /// are named as their accessibility identifiers (`tool.<tool>`).
    func testEveryTargetHasItsOwnStableName() {
        let names = TutorialTarget.allCases.map(\.rawValue)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names, [
            "tool.select", "tool.network", "tool.train", "tool.building", "train.buy", "line.staff.start", "network.modes",
            "panel.action", "map", "map.zoom", "hud.lines", "hud.speed", "hud.cash", "hud.menu",
        ])
        for tool in ConstructionTool.allCases {
            XCTAssertEqual(TutorialTarget(tool: tool)?.rawValue, "tool.\(tool)", "every tool has its button")
        }
    }

    /// Each step reads in both languages, the Chinese written out by hand,
    /// as plain text (the reference's cards hold HTML), and names controls
    /// it can outline once each.
    func testTheStepsReadInBothLanguages() {
        let steps = Tutorial.standardSteps
        XCTAssertEqual(steps.map(\.id), Self.stepIDs)
        XCTAssertEqual(Set(steps.map(\.id)).count, steps.count)
        XCTAssertEqual(steps.map { $0.title(in: .english) }, [
            "Start building a line", "Lay the track", "Move around the map", "Build a station", "A line needs two stations", "Create the line",
            "Start service", "Control time", "Your first fares", "Passengers", "That's the tour",
        ])
        XCTAssertEqual(steps.map { $0.title(in: .traditionalChinese) }, [
            "開始建線", "鋪設軌道", "移動與縮放地圖", "建造車站", "路線至少要兩座車站", "建立路線",
            "開始營運", "控制時間", "第一筆車資", "乘客", "導覽結束",
        ])
        XCTAssertEqual(steps[0].body(in: .traditionalChinese), "點「路網」。軌道、月台和車站都用它來建造。")
        for step in steps {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                XCTAssertFalse(step.title(in: language).isEmpty, step.id)
                XCTAssertFalse(step.body(in: language).isEmpty, step.id)
                XCTAssertFalse(step.body(in: language).contains("<"), "\(step.id) is plain text")
            }
            XCTAssertNotEqual(step.body(in: .traditionalChinese), step.body(in: .english), step.id)
            XCTAssertEqual(Set(step.targets).count, step.targets.count, step.id)
        }
    }

    /// The second-station step says short trips walk, up to 2 km, only
    /// where they do: a world with demand by distance (decision 137). A
    /// demo or a save from before it has none, and the step leaves it out.
    func testTheStepsSayShortTripsWalkOnlyWhereTheyDo() async throws {
        await MainActor.run {
            @MainActor func secondStation(_ session: GameSession) -> String {
                session.startTutorial()
                return session.tutorial?.steps.first { $0.id == "build.secondStation" }?.body(in: .english) ?? ""
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
            XCTAssertTrue(body.hasSuffix("add a platform there too."), body)
        }
    }

    /// The speed step reads the clock as it is now: it is done while the
    /// speed differs from the one it was shown at, and resuming counts.
    func testTheSpeedStepIsDoneWhileTheSpeedDiffers() async throws {
        await MainActor.run {
            let session = GameSession(world: .newGame())
            session.startTutorial()
            for index in 0..<7 {
                Self.carryOut(index, in: session)
                Self.advance(session)
            }
            XCTAssertEqual(session.tutorial?.step.goal, .changeSpeed)
            // Decision 125: the step follows the line's trains, still paused
            // by the network tool (decision 99).
            XCTAssertEqual(session.world.clock.speed, .paused)
            XCTAssertFalse(session.isTutorialStepDone)
            session.togglePause()
            XCTAssertEqual(session.world.clock.speed, .normal)
            XCTAssertTrue(session.isTutorialStepDone, "resumed")
            session.togglePause()
            XCTAssertFalse(session.isTutorialStepDone, "paused again, as it was shown")
            session.setSpeed(.x60)
            XCTAssertTrue(session.isTutorialStepDone)
        }
    }

    /// Decision 125: the fare step waits for fares settled while it is
    /// shown; a free game charges none, so it has nothing to wait for.
    func testTheFareStepWaitsForFaresUnlessTheGameIsFree() async throws {
        var free = GameWorld.newGame()
        free.setEconomyMode(.free)
        for (world, charges) in [(GameWorld.newGame(), true), (free, false)] {
            await MainActor.run { [world] in
                let session = GameSession(world: world)
                session.startTutorial()
                for index in 0..<8 {
                    Self.carryOut(index, in: session)
                    Self.advance(session)
                }
                XCTAssertEqual(session.tutorial?.step.id, "first.fare")
                XCTAssertEqual(session.isTutorialStepDone, !charges)
                guard charges else { return }
                Self.runUntilFares(session)
                // Going back and on again keeps the fares it waited for.
                session.showPreviousTutorialStep()
                session.showNextTutorialStep()
                XCTAssertTrue(session.isTutorialStepDone)
            }
        }
    }

    /// Starting service needs both a train given to the line and the line
    /// set to run trains, in either order, and a train that was already
    /// assigned when the step was shown does not count. The lines panel's
    /// one step does both (decision 125); doing it by hand still counts.
    func testStartingServiceNeedsAnAssignedTrainAndATrainWanted() async throws {
        await MainActor.run {
            let session = GameSession(world: DemoWorld.make(in: .english))
            session.startTutorial()
            for index in 0..<6 {
                Self.carryOut(index, in: session)
                Self.advance(session)
            }
            XCTAssertEqual(session.tutorial?.step.goal, .startService)
            XCTAssertFalse(session.isTutorialStepDone, "the demo's lines already run their own trains")
            session.selectTool(.train)
            session.purchaseTrain()
            session.selectStation(Self.newStations(session).first)
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
}
