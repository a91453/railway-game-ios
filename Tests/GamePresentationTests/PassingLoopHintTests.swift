import GameCore
@testable import GamePresentation
import XCTest

/// Decision 204, later: a new passing loop offers its signal station to the
/// lines it lies on; and a one-time card points to the tool the first time
/// a line's train waits on single track.
@MainActor
final class PassingLoopHintTests: XCTestCase {
    /// A single track 480 m long west to east, stations West and East at its
    /// ends, and line Single between them; and apart from it, a track with
    /// stations North and South and line Other.
    private func world() throws -> (GameWorld, west: StationID, east: StationID, single: LineID, other: LineID) {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 29_696, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 4_096)
        try world.addTrackPlatform(east, on: edge, from: 26_624, to: 29_696)
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 2_048))
        let d = try world.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 2_048))
        let apart = try world.buildTrackEdge(from: c, to: d)
        let north = try world.buildStation(named: "North", at: PlanPoint(x: 3_072, y: 2_560)).id
        let south = try world.buildStation(named: "South", at: PlanPoint(x: 13_312, y: 2_560)).id
        try world.addTrackPlatform(north, on: apart, from: 1_024, to: 4_096)
        try world.addTrackPlatform(south, on: apart, from: 10_240, to: 13_312)
        let single = try world.createLine(named: "Single", stops: [west, east]).id
        let other = try world.createLine(named: "Other", stops: [north, south]).id
        return (world, west, east, single, other)
    }

    private func loopSession(_ world: GameWorld) -> GameSession {
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.passingLoop)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        session.addPassingLoop()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        return session
    }

    func testANewLoopIsOfferedToTheLinesOnItsWayOnly() throws {
        let (world, west, east, single, _) = try world()
        let session = loopSession(world)
        let signal = try XCTUnwrap(session.world.stations.first { $0.operationMode == .closed }).id
        let offer = try XCTUnwrap(session.passingLoopOffer)
        XCTAssertEqual(offer.station, signal)
        XCTAssertEqual(offer.stops, [PassingLoopOffer.Stop(line: single, index: 1)], "not Other, which runs elsewhere")
        XCTAssertEqual(offer.byHand, [])
        XCTAssertEqual(
            offer.message(in: session.world, language: .english),
            "Single run through Signal 1. Its trains pass each other there only if it is one of the line's stops; each train then stops there briefly."
        )
        // Nothing changes until the player says so.
        XCTAssertEqual(session.world.line(id: single)?.stops, [west, east])

        session.acceptPassingLoopOffer()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.message?.text, "Signal 1 is now a stop of Single.")
        XCTAssertEqual(session.world.line(id: single)?.stops, [west, signal, east])
        XCTAssertNil(session.passingLoopOffer)
        guard case .command(.edit(.setLineStops(single, [west, signal, east])))? = session.commandLog.entries.last?.action else {
            return XCTFail("logged as the stops edit")
        }
    }

    func testTheOfferCanBeDeclined() throws {
        let (world, west, east, single, _) = try world()
        let session = loopSession(world)
        session.dismissPassingLoopOffer()
        XCTAssertNil(session.passingLoopOffer)
        XCTAssertEqual(session.world.line(id: single)?.stops, [west, east])
    }

    func testWithoutALineOnItsWayThereIsNoOffer() throws {
        var (world, _, _, single, _) = try world()
        try world.removeLine(single)
        let session = loopSession(world)
        XCTAssertNil(session.passingLoopOffer)
    }

    func testALineWithRouteChoicesIsLeftToThePlayer() throws {
        let (world, _, _, single, _) = try world()
        var built = loopSession(world).world
        let signal = try XCTUnwrap(built.stations.first { $0.operationMode == .closed }).id
        // Choose a route for the line's leg (decision 201): its legs are named
        // by stop number.
        let choice = try XCTUnwrap(built.lineRouteChoices(single, from: 0, to: 1).first)
        try built.setLineRoutePreferences(single, to: [choice])
        let offer = built.passingLoopOffer(for: signal)
        XCTAssertEqual(offer.stops, [])
        XCTAssertEqual(offer.byHand, [single])
    }

    // MARK: - The card

    private func wait(_ train: TrainID, deadlocked: Bool = false) -> TrafficOverlay.Wait {
        let point = WorldCoordinate(x: 0, y: 0)
        return TrafficOverlay.Wait(
            train: train, holder: TrainID(rawValue: 99), isDeadlocked: deadlocked, contested: .init(), from: point, to: point,
            heading: PlanVector(dx: 1, dy: 0)
        )
    }

    func testTheCardNamesTheLineWaitingOnSingleTrack() throws {
        var (world, _, _, single, _) = try world()
        let train = try world.purchaseTrain(named: "Train 1").id
        try world.assignTrain(train, to: single)
        XCTAssertEqual(PassingLoopHint.waitingLine([wait(train)], in: world), single)
        XCTAssertNil(PassingLoopHint.waitingLine([wait(train, deadlocked: true)], in: world), "a deadlock has its own warning")
        let unassigned = try world.purchaseTrain(named: "Train 2").id
        XCTAssertNil(PassingLoopHint.waitingLine([wait(unassigned)], in: world))
    }

    func testALoopTheLineDoesNotStopAtLeavesItSingle() throws {
        var (world, _, _, single, _) = try world()
        let train = try world.purchaseTrain(named: "Train 1").id
        try world.assignTrain(train, to: single)
        let session = loopSession(world)
        world = session.world
        let signal = try XCTUnwrap(world.stations.first { $0.operationMode == .closed }).id
        XCTAssertEqual(PassingLoopHint.waitingLine([wait(train)], in: world), single, "a loop it does not stop at is still single")
        try world.setLineStops(single, to: [try XCTUnwrap(world.line(id: single)?.stops.first), signal, try XCTUnwrap(world.line(id: single)?.stops.last)])
        XCTAssertNotNil(PassingLoopHint.waitingLine([wait(train)], in: world), "the legs either side are still single")
    }

    func testTheCardsButtonOpensTheLoopTool() throws {
        let (world, _, _, _, _) = try world()
        let session = GameSession(world: world)
        session.passingLoopHint = LineID(rawValue: 1)
        session.showPassingLoopTool()
        XCTAssertNil(session.passingLoopHint)
        XCTAssertEqual(session.tool, .network)
        XCTAssertEqual(session.networkMode, .passingLoop)
    }

    func testTheCardSaysWhatToDo() throws {
        let (world, _, _, single, _) = try world()
        XCTAssertEqual(
            PassingLoopHint.message(line: single, in: world, language: .traditionalChinese),
            "Single 的列車在單線上等另一列車：一段單線一次只能走一列。\n\n加一條待避線，兩列車就能在中途交會。在「路網」選「待避」，點一段單線，就會在旁邊加第二條軌道和號誌站。\n\n再把號誌站加進路線的停靠站，列車才會在那裡交會。"
        )
    }
}
