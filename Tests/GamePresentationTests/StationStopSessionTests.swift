import GameCore
import GamePresentation
import XCTest

/// Stage N in the train tool: selecting a station sends the train to the
/// station with `GameWorld.route(from:toStation:)`, committed unchanged, and
/// the stop shown is read from `GameWorld.stationsStoppedAt(by:)`.
///
/// Each test compares the session's world with the same commands applied to
/// GameCore directly.
final class StationStopSessionTests: XCTestCase {
    // A dead-end line on row 2 with stations beside it:
    //
    //            C       M
    //   a - b - c - d - e      T
    //                    H
    //
    // Central is north of b; Market and Hill are north and south of d;
    // Terminus has no track beside it.
    private static let a = GridPosition(x: 1, y: 2)
    private static let b = GridPosition(x: 2, y: 2)
    private static let c = GridPosition(x: 3, y: 2)
    private static let d = GridPosition(x: 4, y: 2)
    private static let e = GridPosition(x: 5, y: 2)
    private static let centralTile = GridPosition(x: 2, y: 1)
    private static let marketTile = GridPosition(x: 4, y: 1)
    private static let hillTile = GridPosition(x: 4, y: 3)
    private static let terminusTile = GridPosition(x: 7, y: 2)
    private static let central = StationID(rawValue: 1)
    private static let market = StationID(rawValue: 2)
    private static let hill = StationID(rawValue: 3)
    private static let first = TrainID(rawValue: 1)

    private func makeStationWorld(trainAt position: TrainPosition? = nil, rate: Int64 = 0) throws -> GameWorld {
        var world = try makeWorld(balance: 100_000, speed: .normal)
        try world.buildTrack(at: Self.a, connections: .east)
        for tile in [Self.b, Self.c, Self.d] {
            try world.buildTrack(at: tile, connections: [.east, .west])
        }
        try world.buildTrack(at: Self.e, connections: .west)
        try world.buildStation(named: "Central", at: Self.centralTile)
        try world.buildStation(named: "Market", at: Self.marketTile)
        try world.buildStation(named: "Hill", at: Self.hillTile)
        try world.buildStation(named: "Terminus", at: Self.terminusTile)
        if let position {
            try world.purchaseTrain(named: "Train 1")
            try world.placeTrain(Self.first, at: position)
            try world.setTrainMovementRate(Self.first, to: rate)
        }
        return world
    }

    func testSendingToAStationCommitsGameCoresStationRouteUnchanged() async throws {
        let world = try makeStationWorld(trainAt: .atNode(Self.a, heading: .east))
        let route = try XCTUnwrap(world.route(from: .atNode(Self.a, heading: .east), toStation: Self.market))
        XCTAssertEqual(route, [Self.b, Self.c, Self.d])
        var expected = world
        try expected.setTrainContinuation(Self.first, to: route)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.select(Self.marketTile)

            session.sendSelectedTrain()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .success, text: "Sent Train 1 to Market, platform (4, 2), 3 links from (1, 2). Set a rate to start.")
            )
        }
    }

    func testSendingToAStationTheTrainIsAtOrHeadingForCommitsTheEmptyRoute() async throws {
        let atPlatform = try makeStationWorld(trainAt: .atNode(Self.d, heading: .west), rate: 100)
        var onLink = try makeStationWorld(trainAt: .onLink(from: Self.a, to: Self.b, offset: 512), rate: 0)
        try onLink.setTrainContinuation(Self.first, to: [Self.c, Self.d])
        var onLinkExpected = onLink
        try onLinkExpected.setTrainContinuation(Self.first, to: [])
        await MainActor.run { [onLink, onLinkExpected] in
            let session = GameSession(world: atPlatform)
            session.select(Self.hillTile)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, atPlatform, "already stopped there: nothing to change")
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Train 1 stops at Hill, platform (4, 2)."))

            let heading = GameSession(world: onLink)
            heading.select(Self.centralTile)
            heading.sendSelectedTrain()
            XCTAssertEqual(heading.world, onLinkExpected, "its path is cleared; it runs to the platform and stops")
            XCTAssertEqual(
                heading.message,
                StatusMessage(kind: .success, text: "Train 1 stops at Central, platform (2, 2). Set a rate to start.")
            )
        }
    }

    func testNoRouteToAStationChangesNothing() async throws {
        var world = try makeStationWorld(trainAt: .atNode(Self.c, heading: .east), rate: 64)
        try world.setTrainContinuation(Self.first, to: [Self.d])
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            // Central is behind the train, past a dead end.
            session.select(Self.centralTile)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(
                session.message,
                StatusMessage(
                    kind: .failure,
                    text: "No route for Train 1 to Central: it needs track beside the station that the train can reach without turning back. Its path is unchanged."
                )
            )
            // Terminus has no platform at all.
            session.select(Self.terminusTile)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message?.kind, .failure)
        }
    }

    func testTheTrainToolSendsAPlacedTrainToTheSelectedStation() async throws {
        let world = try makeStationWorld(trainAt: .atNode(Self.a, heading: .east))
        var expected = world
        try expected.setTrainContinuation(Self.first, to: [Self.b])
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.select(Self.centralTile)

            session.applyTool()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .success, text: "Sent Train 1 to Central, platform (2, 2), 1 link from (1, 2). Set a rate to start.")
            )
        }
    }

    /// Send to a station, advance with the game loop, read the stop: the
    /// whole Stage N flow, checked against GameCore run directly.
    func testTheGameLoopBringsASentTrainToAStop() async throws {
        let world = try makeStationWorld(trainAt: .atNode(Self.a, heading: .east), rate: 384)
        var expected = world
        let route = try XCTUnwrap(expected.route(from: .atNode(Self.a, heading: .east), toStation: Self.hill))
        try expected.setTrainContinuation(Self.first, to: route)
        var arrived = expected
        try arrived.advance(ticks: 8)
        XCTAssertEqual(arrived.stationsStoppedAt(by: Self.first), [Self.market, Self.hill])
        await MainActor.run { [expected, arrived] in
            let session = GameSession(world: world)
            session.select(Self.hillTile)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, expected)
            XCTAssertNil(session.world.stationStopText(of: Self.first), "departing")

            // 3 links of 1024 at 384 a minute: 8 minutes.
            for _ in 0..<7 {
                session.advance(realElapsed: .milliseconds(100))
            }
            XCTAssertNil(session.world.stationStopText(of: Self.first), "not there yet")
            session.advance(realElapsed: .milliseconds(100))
            XCTAssertEqual(session.world, arrived)
            XCTAssertEqual(session.world.stationStopText(of: Self.first), "Stopped at Market, Hill")
            XCTAssertEqual(session.selectedTrain?.positionText, "At (4, 2), facing East")
            XCTAssertEqual(session.selectedTrain?.movement.pathText, "No path ahead")
        }
    }

    func testTheStopTextIsReadFromTheWorld() throws {
        var world = try makeStationWorld()
        XCTAssertNil(world.stationStopText(of: Self.first), "no such train")
        try world.purchaseTrain(named: "Train 1")
        XCTAssertNil(world.stationStopText(of: Self.first), "unplaced")
        try world.placeTrain(Self.first, at: .atNode(Self.c, heading: .east))
        XCTAssertNil(world.stationStopText(of: Self.first), "not at a platform")
        try world.unplaceTrain(Self.first)
        try world.placeTrain(Self.first, at: .atNode(Self.b, heading: .east))
        XCTAssertEqual(world.stationStopText(of: Self.first), "Stopped at Central")
        try world.unplaceTrain(Self.first)
        try world.placeTrain(Self.first, at: .atNode(Self.d, heading: .north))
        XCTAssertEqual(world.stationStopText(of: Self.first), "Stopped at Market, Hill")
        try world.setTrainContinuation(Self.first, to: [Self.e])
        XCTAssertNil(world.stationStopText(of: Self.first), "given somewhere to go")
    }
}
