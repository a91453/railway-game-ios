import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 573 (player report 111.1): "I put a depot behind my station,
/// but after service ends the trains stay at the station, not in the
/// depot." A new depot is made the depot of the one line it serves in the
/// same edit; with several, the banner offers each.
///
/// A straight track from west (x 1024) to east (x 16384) along y 8192,
/// stations West and East on it, the line Main between them, as in
/// `DepotToolsTests`.
@MainActor
final class DepotLinkTests: XCTestCase {
    private func world(minutes: Int64 = 600, width: Int64 = 65_536) throws -> (GameWorld, west: StationID, east: StationID) {
        var world = GameWorld(
            bounds: try WorldBounds(width: width, height: 16_384), economy: GameEconomy(balance: 10_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minutes), speed: .paused)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 12_288, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(east, on: edge, from: 9_216, to: 13_312)
        return (world, west, east)
    }

    /// Main with one train standing at West, running until 23:00.
    private func lineWithATrain(_ world: inout GameWorld, west: StationID, east: StationID) throws -> (LineID, TrainID) {
        let main = try world.createLine(named: "Main", stops: [west, east]).id
        try world.setLineServiceWindow(main, to: .standard)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1").id
        let first = try world.splitTrackEdge(XCTUnwrap(world.network.edges.first).id, at: 5_120)
        let into = try XCTUnwrap(world.network.edges.first { $0.to == first }).id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: into, direction: .forward), offset: 5_120))
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: main)
        return (main, train)
    }

    private func layDepot(on world: GameWorld, language: DisplayLanguage = .traditionalChinese) -> GameSession {
        let session = GameSession(world: world, language: language)
        session.selectTool(.network)
        session.setNetworkMode(.depot)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        session.addDepotYard()
        return session
    }

    /// The report itself: the depot laid behind East, nothing ticked on
    /// the line panel, and after the last train the line's train runs
    /// into it instead of staying at a platform. One Undo takes back the
    /// sidings and the line's depot together.
    func testADepotLaidBehindALinesEndTakesItsTrainsAfterTheLastTrain() throws {
        var (world, west, east) = try world(minutes: 1_380)
        let (main, train) = try lineWithATrain(&world, west: west, east: east)
        let session = layDepot(on: world)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let depot = try XCTUnwrap(session.world.stations.first(where: \.isDepot)).id
        XCTAssertEqual(session.world.line(id: main)?.depots, [depot])
        XCTAssertEqual(session.message?.text.hasSuffix("已設為「Main」的機廠，收班後列車會開進來。"), true, session.message?.text ?? "")
        XCTAssertNil(session.message?.depotOffer)

        var night = session.world
        night.resume()
        for _ in 0..<(4 * 60) { try night.advance(ticks: 1) }
        XCTAssertEqual(night.depotState(of: train), .inDepot)
        XCTAssertFalse(night.stationsStoppedAt(by: train).contains(where: [west, east].contains))

        // Logged as the two commands, and replayed to the same world.
        let actions = session.commandLog.entries.suffix(2).map(\.action)
        guard case .command(.buildDepotYard)? = actions.first, case .command(.edit(.setLineDepots(main, [depot])))? = actions.last else {
            return XCTFail("\(actions)")
        }
        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.5.0", build: "57", data: [:]).encoded()
        )
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world, session.world)

        XCTAssertEqual(session.undoCount, 1)
        session.undo()
        XCTAssertEqual(session.world, world)
    }

    /// Several lines end near it: none is chosen, and the banner offers
    /// each; its button makes the depot that line's.
    func testSeveralLinesAreOfferedAndNoneChosen() throws {
        var (world, west, east) = try world()
        let main = try world.createLine(named: "Main", stops: [west, east]).id
        let back = try world.createLine(named: "Back", stops: [east, west]).id
        let session = layDepot(on: world, language: .english)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let depot = try XCTUnwrap(session.world.stations.first(where: \.isDepot)).id
        XCTAssertEqual(session.world.line(id: main)?.depots, [])
        XCTAssertEqual(session.world.line(id: back)?.depots, [])
        XCTAssertEqual(session.message?.depotOffer, DepotLinkOffer(depot: depot, lines: [main, back]))
        XCTAssertEqual(session.message?.autoDismissDelay, .seconds(10))
        XCTAssertEqual(session.depotOfferTitle(line: back), "Make it Back's depot")

        session.linkDepot(depot, to: back)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.line(id: back)?.depots, [depot])
        XCTAssertEqual(session.world.line(id: main)?.depots, [])
        XCTAssertNil(session.message?.depotOffer)
    }

    /// A line that already keeps a depot is left as it is; with no line
    /// to serve, the message says where to choose it.
    func testALineWithADepotIsLeftAlone() throws {
        var (world, west, east) = try world()
        let main = try world.createLine(named: "Main", stops: [west, east]).id
        let yard = try world.buildStation(named: "Yard", at: PlanPoint(x: 40_960, y: 12_288)).id
        try world.setStationDepot(yard, to: true)
        try world.setLineDepots(main, to: [yard])
        let session = layDepot(on: world)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.line(id: main)?.depots, [yard])
        XCTAssertNil(session.message?.depotOffer)
        XCTAssertEqual(session.message?.text.hasSuffix("到路線面板替路線選這個機廠。"), true, session.message?.text ?? "")
    }

    /// A line whose ends are further than ``DepotLink/reach`` of track
    /// from the depot is not one it serves.
    func testAFarLineIsNotServed() throws {
        var (world, west, east) = try world(width: 524_288)
        let main = try world.createLine(named: "Main", stops: [west, east]).id
        // Track on east from the end, 4 km, to the depot's place.
        let end = try XCTUnwrap(world.network.nodes.first { $0.position.x == 16_384 }).id
        let far = try world.buildTrackNode(at: WorldCoordinate(x: 16_384 + 4_000 * WorldCoordinate.unitsPerMetre, y: 8_192))
        try world.buildTrackEdge(from: end, to: far)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTool(.network)
        session.setNetworkMode(.depot)
        session.tapNetwork(at: far.position(in: world).plan, reach: 64)
        session.addDepotYard()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.line(id: main)?.depots, [])
    }

    /// The station panel's "Make a depot" serves the line too, a line
    /// that runs to a timetable included (decision 221).
    func testMakingAStationADepotServesTheLine() throws {
        var (world, west, east) = try world()
        let main = try world.createLine(named: "Main", stops: [west, east]).id
        let run = LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 600, departure: 600), LineRunTime(arrival: 900, departure: 900)])
        try world.setLineRuns(main, to: [run])
        // A siding off East's end, with a station on it.
        let end = try XCTUnwrap(world.network.nodes.first { $0.position.x == 16_384 }).id
        let far = try world.buildTrackNode(at: WorldCoordinate(x: 24_576, y: 8_192))
        let siding = try world.buildTrackEdge(from: end, to: far)
        let yard = try world.buildStation(named: "Yard", at: PlanPoint(x: 20_480, y: 8_704)).id
        try world.addTrackPlatform(yard, on: siding, from: 1_024, to: 5_120)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectStation(yard)
        session.setSelectedStationDepot(true)
        XCTAssertEqual(session.message?.text, "「Yard」現在是機廠。已設為「Main」的機廠，收班後列車會開進來。")
        XCTAssertEqual(session.world.line(id: main)?.depots, [yard])
        session.undo()
        XCTAssertEqual(session.world, world)
    }

    /// The screenshot scene: the depot tool off Line 2's north end of the
    /// demo offers Line 2 and the Ring Line.
    func testTheScreenshotSceneOffersTwoLines() throws {
        let session = GameSession(world: ScreenshotScene.depotOffer.make(in: .traditionalChinese), language: .traditionalChinese)
        ScreenshotScene.depotOffer.prepare(session)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let offer = try XCTUnwrap(session.message?.depotOffer, session.message?.text ?? "")
        XCTAssertEqual(offer.lines.compactMap { session.world.line(id: $0)?.name }, ["2 號線", "環狀線"])
    }
}

private extension TrackNodeID {
    func position(in world: GameWorld) -> WorldCoordinate {
        world.network.node(self)!.position
    }
}
