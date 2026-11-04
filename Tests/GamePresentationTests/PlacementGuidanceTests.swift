@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 584 (TestFlight 111.1): why a train will not go on the track,
/// and what to do next. The train tool's button asks for a station before
/// one is picked; a refused placement names the train on the platform (and
/// offers to go to it) or how short the platform is; a line's new trains
/// left off the track say whose train holds the first stop, and the line
/// panel offers an idle train standing at its stops instead of buying.
@MainActor
final class PlacementGuidanceTests: XCTestCase {
    /// One straight edge between two towns with a 4-car platform at each
    /// end: stations A and B, traffic control on.
    private func twoStations(rules: NewGameRules = .realistic) throws -> (world: GameWorld, a: StationID, b: StationID) {
        var world = GameWorld.newGame(rules: rules)
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
        try world.setTrafficControl(true)
        return (world, a, b)
    }

    func testTheTrainToolsButtonAsksForAStationFirst() throws {
        let (world, a, _) = try twoStations()
        let session = GameSession(world: world)
        session.purchaseTrain()
        session.selectTool(.train)
        XCTAssertFalse(session.trainActionIsReady)
        XCTAssertEqual(session.trainActionTitle, "Tap a Station on the Map First")
        session.placeSelectedTrain()
        XCTAssertEqual(session.message?.text, "Tap a station on the map first, then place Train 1 there.")
        XCTAssertNil(session.selectedTrain?.position)

        session.selectStation(a)
        XCTAssertTrue(session.trainActionIsReady)
        XCTAssertEqual(session.trainActionTitle, "Place Train 1 Here")
        session.placeSelectedTrain()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertNotNil(session.selectedTrain?.position)
        XCTAssertEqual(session.trainActionTitle, "Send Train 1 Here")
    }

    /// The author's Gangho: Train 4 stood idle at the first stop, and the
    /// next train placed there was refused with "a train's route runs over
    /// that track". Now the refusal names Train 4, says it has no line,
    /// and the banner goes to it.
    func testARefusedPlacementNamesTheTrainOnThePlatform() throws {
        let (world, a, _) = try twoStations()
        let session = GameSession(world: world)
        session.purchaseTrain()
        let idle = try XCTUnwrap(session.selectedTrainID)
        session.selectStation(a)
        session.placeSelectedTrain()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")

        session.purchaseTrain()
        let second = try XCTUnwrap(session.selectedTrainID)
        session.selectStation(a)
        let before = session.world
        XCTAssertEqual(session.world.trainPlacementProblem(second, at: a, heading: session.placementHeading), .held(a, by: idle))
        session.placeSelectedTrain()
        XCTAssertEqual(session.world, before)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(
            session.message?.text,
            "A's platform is taken by Train 1. It has no line: give it one in its train card, or move it, and try again."
        )
        XCTAssertEqual(session.message?.goToTrain, idle)
        XCTAssertEqual(
            session.world.trainPlacementProblemText(.held(a, by: idle), train: second, in: .traditionalChinese),
            "A的月台被 Train 1 佔著。它沒有路線：在它的列車卡配屬路線，或把它開走，再試一次。"
        )

        session.goToTrain(idle)
        XCTAssertEqual(session.selectedTrainID, idle)
        XCTAssertEqual(session.followedTrainID, idle)
    }

    /// A platform at a dead end with no track behind it: a train longer
    /// than it is refused with the platform's length, the train's, and how
    /// many cars fit.
    func testATooShortPlatformSaysHowManyCarsFit() throws {
        var world = GameWorld.newGame(rules: .realistic)
        world.setTourism(nil)
        let car = world.platformCarLength
        let x = world.bounds.width / 2, y = world.bounds.height / 2
        let start = try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: x + 2 * car, y: y))
        let stub = try world.buildTrackEdge(from: start, to: end)
        let length = try XCTUnwrap(world.trackEdge(stub)?.length)
        let station = try world.buildStation(named: "Stub", at: PlanPoint(x: x + car, y: y + car)).id
        try world.addTrackPlatform(station, on: stub, from: 0, to: length)
        let train = try world.purchaseTrain(named: "Long")
        try world.setTrainCars(train.id, to: 6)

        let problem = world.trainPlacementProblem(train.id, at: station, heading: .east)
        guard case .tooShort(station, let longest, let cars)? = problem else {
            return XCTFail("\(String(describing: problem))")
        }
        XCTAssertEqual(longest, length)
        XCTAssertEqual(cars, 2)
        let text = world.trainPlacementProblemText(try XCTUnwrap(problem), train: train.id, in: .traditionalChinese)
        XCTAssertTrue(text.hasPrefix("Long 太長，Stub 放不下：最長的月台"), text)
        XCTAssertTrue(text.contains("列車 6 節共"), text)
        XCTAssertTrue(text.hasSuffix("減到 2 節，或把月台加長。"), text)

        let session = GameSession(world: world)
        session.selectTrain(train.id)
        session.selectStation(station)
        session.placeSelectedTrain()
        XCTAssertEqual(session.world, world)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertTrue(session.message?.text.contains("Shorten it to 2 cars") == true, session.message?.text ?? "")
    }

    /// The author's line 2: an idle train with no line stood at its first
    /// stop, so the line's new train was bought and left off the track.
    /// The message names the idle train and the banner goes to it; the
    /// line panel offers it to the line instead of buying another.
    func testALinesFirstStopHeldByAnIdleTrainIsNamed() throws {
        let (world, a, b) = try twoStations()
        let setup = GameSession(world: world)
        for stop in [a, b] {
            setup.selectStation(stop)
            setup.addSelectedStationToLineDraft()
        }
        setup.createLineFromDraft()
        let line = try XCTUnwrap(setup.world.lines.first?.id)
        // Train 1 bought and left where the line's trips start, with no line.
        var standing = setup.world
        let idle = try standing.purchaseTrain(named: "Train 1").id
        try GameSession.placeAtStart(idle, of: try XCTUnwrap(standing.lineJourney(line)), in: &standing)
        let session = GameSession(world: standing)
        session.selectLine(line)
        XCTAssertEqual(session.world.trainsStanding(at: a), [idle])
        XCTAssertEqual(session.world.lineStartBlocker(line), idle)
        XCTAssertEqual(session.world.idleTrainsAtStops(of: line), [IdleTrainAtStop(train: idle, station: a)])
        XCTAssertEqual(
            session.world.idleTrainAtStopText(idle, at: a, line: line, in: .traditionalChinese),
            "Train 1 停在A、沒有路線。可以把它配屬給\(session.world.lines[0].name)，不必再買。"
        )

        session.staffSelectedLine(headway: 60)
        let text = session.message?.text ?? ""
        XCTAssertTrue(text.contains("A's platform is taken by Train 1, which has no line"), text)
        XCTAssertFalse(text.contains("now runs 0"), text)
        XCTAssertEqual(session.message?.goToTrain, idle)

        session.undo()
        session.selectLine(line)
        session.assignTrain(idle, toLine: line)
        XCTAssertEqual(session.world.line(id: line)?.trains, [idle])
        XCTAssertTrue(session.world.idleTrainsAtStops(of: line).isEmpty)
    }

    /// A line's own trains waiting one behind another are no blocker: the
    /// message keeps saying that one train waits at the first stop at a
    /// time.
    func testALinesOwnTrainIsNoBlocker() throws {
        let (world, a, b) = try twoStations()
        let session = GameSession(world: world)
        for stop in [a, b] {
            session.selectStation(stop)
            session.addSelectedStationToLineDraft()
        }
        session.createLineFromDraft()
        let line = try XCTUnwrap(session.world.lines.first?.id)
        session.selectLine(line)
        session.staffSelectedLine(headway: 3)
        XCTAssertNil(session.world.lineStartBlocker(line))
        XCTAssertNil(session.message?.goToTrain)
    }
}
