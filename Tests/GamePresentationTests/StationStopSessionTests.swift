import GameCore
import GamePresentation
import XCTest

/// Stage N in the train tool: selecting a station sends the train to the
/// station with `GameWorld.path(from:toStation:length:)`, committed
/// unchanged, and the stop shown is read from
/// `GameWorld.stationsStoppedAt(by:)`. On the track network since Stage
/// F3c.
///
/// Each test compares the session's world with the same commands applied to
/// GameCore directly.
final class StationStopSessionTests: XCTestCase {
    // A dead-end line of the track network on row 2 (nodes at columns
    // 0–5, edges 1–5 eastward, see `TestLine`) with stations beside it:
    //
    //   row 1:           C       M
    //   row 2:   o - o - o - o - o - o      T
    //
    // Central beside column 2 and Market beside column 4, each with
    // platforms on the half of each edge there nearer it; Terminus has no
    // platform.
    private static let line = TestLine(tiles: 6, row: 2)
    private static let central = StationID(rawValue: 1)
    private static let market = StationID(rawValue: 2)
    private static let terminus = StationID(rawValue: 3)
    private static let first = TrainID(rawValue: 1)

    private func makeStationWorld(trainAt position: TrainPosition? = nil, rate: Int64 = 0) throws -> GameWorld {
        var world = try makeWorld(balance: 100_000, speed: .normal)
        try Self.line.build(in: &world)
        try Self.line.buildStation(named: "Central", beside: 2, at: 1, in: &world)
        try Self.line.buildStation(named: "Market", beside: 4, at: 1, in: &world)
        try world.buildStation(named: "Terminus", at: TestLine.centre(7, 2))
        if let position {
            try world.purchaseTrain(named: "Train 1")
            try world.placeTrain(Self.first, at: position)
            try world.setTrainMovementRate(Self.first, to: rate)
        }
        return world
    }

    /// `world` with Train 1 sent to `station` along GameCore's path.
    private static func sent(_ world: GameWorld, to station: StationID) throws -> GameWorld {
        var world = world
        let train = try XCTUnwrap(world.train(id: first))
        let path = try XCTUnwrap(world.path(from: try XCTUnwrap(train.position), toStation: station, length: train.length))
        try world.setTrainContinuation(first, along: path.traversals, stoppingAt: path.end)
        try world.useTrainPerformanceForMovement(first)
        return world
    }

    func testSendingToAStationCommitsGameCoresPathUnchanged() async throws {
        let world = try makeStationWorld(trainAt: Self.line.at(1, facingEast: true))
        let path = try XCTUnwrap(world.path(from: Self.line.at(1, facingEast: true), toStation: Self.market, length: 0))
        // To the end of Market's platform on edge 4, at column 4.
        XCTAssertEqual(path.traversals, Self.line.path(from: 1, through: [2, 3, 4]))
        XCTAssertEqual(path.distance, 3_072)
        let expected = try Self.sent(world, to: Self.market)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectStation(Self.market)

            session.sendSelectedTrain()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .success, text: "Sent Train 1 to Market, 3072 units along the track.")
            )
        }
    }

    func testSendingToAStationTheTrainIsAtOrHeadingForStopsItThere() async throws {
        let atPlatform = try makeStationWorld(trainAt: Self.line.at(4, facingEast: true), rate: 100)
        XCTAssertEqual(atPlatform.stationsStoppedAt(by: Self.first), [Self.market])
        let atPlatformExpected = try Self.sent(atPlatform, to: Self.market)
        let onEdge = try Self.sent(try makeStationWorld(trainAt: Self.line.between(1, 2, offset: 512)), to: Self.market)
        let onEdgeExpected = try Self.sent(onEdge, to: Self.central)
        await MainActor.run { [onEdge, onEdgeExpected] in
            let session = GameSession(world: atPlatform)
            session.selectStation(Self.market)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, atPlatformExpected, "already stopped there: nowhere to go")
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Train 1 stops at Market."))

            let heading = GameSession(world: onEdge)
            heading.selectStation(Self.central)
            heading.sendSelectedTrain()
            XCTAssertEqual(heading.world, onEdgeExpected, "the rest of edge 2 to Central's platform end")
            XCTAssertEqual(
                heading.message,
                StatusMessage(kind: .success, text: "Sent Train 1 to Central, 512 units along the track.")
            )
        }
    }

    func testNoPathToAStationChangesNothing() async throws {
        let world = try Self.sent(try makeStationWorld(trainAt: Self.line.at(3, facingEast: true), rate: 64), to: Self.market)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            // Central is behind the train, past a dead end.
            session.selectStation(Self.central)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(
                session.message,
                StatusMessage(
                    kind: .failure,
                    text: "No route for Train 1 to Central: it needs a platform on the track network as long as the train, that it can reach without turning back. Its path is unchanged."
                )
            )
            // Terminus has no platform at all.
            session.selectStation(Self.terminus)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message?.kind, .failure)
        }
    }

    func testTheTrainToolSendsAPlacedTrainToTheSelectedStation() async throws {
        let world = try makeStationWorld(trainAt: Self.line.at(1, facingEast: true))
        let expected = try Self.sent(world, to: Self.central)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectTool(.train)
            session.selectStation(Self.central)

            session.applyTool()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .success, text: "Sent Train 1 to Central, 1024 units along the track.")
            )
        }
    }

    /// Send to a station, advance with the game loop, read the stop: the
    /// whole Stage N flow, checked against GameCore run directly.
    func testTheGameLoopBringsASentTrainToAStop() async throws {
        var world = try makeStationWorld(trainAt: Self.line.at(1, facingEast: true))
        try world.setTrainPerformance(Self.first, to: .standard.withTopSpeed(1))
        let expected = try Self.sent(world, to: Self.market)
        var arrived = expected
        try arrived.advance(ticks: 3)
        XCTAssertEqual(arrived.stationsStoppedAt(by: Self.first), [Self.market])
        await MainActor.run { [expected, arrived] in
            let session = GameSession(world: world)
            session.selectStation(Self.market)
            session.sendSelectedTrain()
            XCTAssertEqual(session.world, expected)
            XCTAssertNil(session.world.stationStopText(of: Self.first, in: .english), "departing")

            // 48 metres at 1 km/h takes 2.88 minutes: it stops in minute 3.
            for _ in 0..<2 {
                session.advance(realElapsed: .milliseconds(100))
            }
            XCTAssertNil(session.world.stationStopText(of: Self.first, in: .english), "not there yet")
            session.advance(realElapsed: .milliseconds(100))
            XCTAssertEqual(session.world, arrived)
            XCTAssertEqual(session.world.stationStopText(of: Self.first, in: .english), "Stopped at Market")
            XCTAssertEqual(session.selectedTrain?.positionText(in: .english), "Edge #4 forward, 1024 units along")
            XCTAssertEqual(session.selectedTrain?.pathText(in: .english), "No path ahead")
        }
    }

    func testTheStopTextIsReadFromTheWorld() throws {
        var world = try makeStationWorld()
        XCTAssertNil(world.stationStopText(of: Self.first, in: .english), "no such train")
        try world.purchaseTrain(named: "Train 1")
        XCTAssertNil(world.stationStopText(of: Self.first, in: .english), "unplaced")
        try world.placeTrain(Self.first, at: Self.line.at(3, facingEast: true))
        XCTAssertNil(world.stationStopText(of: Self.first, in: .english), "not at a platform")
        try world.unplaceTrain(Self.first)
        try world.placeTrain(Self.first, at: Self.line.at(2, facingEast: true))
        XCTAssertEqual(world.stationStopText(of: Self.first, in: .english), "Stopped at Central")
        try world.setTrainContinuation(Self.first, along: Self.line.path(from: 2, through: [3]), stoppingAt: nil)
        XCTAssertNil(world.stationStopText(of: Self.first, in: .english), "given somewhere to go")
    }
}
