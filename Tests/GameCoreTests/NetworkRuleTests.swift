import Foundation
import GameCore
import XCTest

/// Rules that do not depend on the kind of track but were tested only on
/// the grid, written again on the track network before the grid's tests
/// go with it (Stage F3c). Each test names the grid test it replaces.
/// Expected values are worked out by hand from the rules.
final class NetworkRuleTests: XCTestCase {
    // A straight line of the track network along row 5, columns 0–7
    // (nodes 1–8, edges 1–7 eastward, see `TestLine`), with a turnout at
    // column 4: from node 5 a quarter turn south leaves east beside edge
    // 5 (edge 8, to node 9 at (5, 6)), then a straight on south (edge 9,
    // to node 10 at (5, 7)).
    //
    //   o - o - o - o - o - o - o - o
    //                    \
    //                     o
    //                     |
    //                     o
    private static let line = TestLine(tiles: 8, row: 5)
    private static let first = TrainID(rawValue: 1)
    private static let second = TrainID(rawValue: 2)

    private static func makeLineWorld(trains: Int = 1, speed: GameSpeed = .normal) throws -> GameWorld {
        var world = try makeWorld(balance: 1_000_000)
        try line.build(in: &world)
        let junction = try XCTUnwrap(world.network.node(line.node(4))).position
        let bend = TestLine.centre(5, 6)
        let end = TestLine.centre(5, 7)
        let b1 = try world.buildTrackNode(at: WorldCoordinate(x: bend.x, y: bend.y))
        let b2 = try world.buildTrackNode(at: WorldCoordinate(x: end.x, y: end.y))
        let quarter: Int64 = 563
        try world.buildTrackEdge(
            from: line.node(4), to: b1,
            curve: .cubic(PlanPoint(x: junction.x + quarter, y: junction.y), PlanPoint(x: bend.x, y: bend.y - quarter))
        )
        try world.buildTrackEdge(from: b1, to: b2)
        for number in 0..<trains {
            try world.purchaseTrain(named: "T\(number + 1)")
        }
        world.setSpeed(speed)
        return world
    }

    private static func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private static func encode(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(world)
    }

    func testTheBranchIsATurnout() throws {
        let world = try Self.makeLineWorld()
        // Edge 4 arrives at node 5 from the west; edges 5 and 8 leave it
        // eastward and both join it, never each other.
        XCTAssertEqual(world.transitions(after: Self.forward(4)), [Self.forward(5), Self.forward(8)])
        XCTAssertEqual(world.network.node(.node(5))?.end(of: .edge(5))?.exits, [.edge(4)])
        XCTAssertEqual(world.network.node(.node(5))?.end(of: .edge(8))?.exits, [.edge(4)])
    }

    // MARK: - Movement (TrainMovementTests)

    /// `testAHugeRateEndsWithTheContinuationWithoutOverflow`: the largest
    /// rate runs to the end of the path and no further, and once there more
    /// minutes change nothing.
    func testAHugeRateEndsAtThePathsEndWithoutOverflow() throws {
        var world = try Self.makeLineWorld()
        try world.placeTrain(Self.first, at: Self.line.between(0, 1, offset: 1_023))
        try world.setTrainContinuation(Self.first, along: Self.line.path(from: 1, through: [2, 3, 4, 5, 6, 7]))
        try world.setTrainMovementRate(Self.first, to: .max)

        try world.advance(ticks: 1)

        let train = try XCTUnwrap(world.train(id: Self.first))
        XCTAssertEqual(train.position, Self.line.at(7, facingEast: true))
        XCTAssertEqual(train.movement.rate, .max)
        XCTAssertEqual(train.movement.remainingEdges, [])
        let atEnd = world
        try world.advance(ticks: 1_000)
        XCTAssertEqual(world.trains, atEnd.trains)
    }

    /// `testZeroDistanceChangesNothing`: no ticks change nothing; ticks at
    /// rate 0 move nothing.
    func testZeroTicksAndARateOfZeroMoveNothing() throws {
        var world = try Self.makeLineWorld()
        try world.placeTrain(Self.first, at: Self.line.between(0, 1, offset: 256))
        try world.setTrainContinuation(Self.first, along: Self.line.path(from: 1, through: [2]))
        let before = world

        try world.advance(ticks: 0)
        XCTAssertEqual(world, before)

        try world.advance(ticks: 3)
        XCTAssertEqual(world.train(id: Self.first)?.position, Self.line.between(0, 1, offset: 256), "rate 0")
        XCTAssertEqual(world.clock.now, GameTime(minutes: 3))
    }

    /// `testTheWaitingTrainChecksOnlyItsOwnNextLink`: at the turnout the
    /// edge its path names is gone; the straight way on is open but is not
    /// taken instead.
    func testAWaitingTrainChecksOnlyTheEdgeItsPathNames() throws {
        var world = try Self.makeLineWorld()
        try world.placeTrain(Self.first, at: Self.line.at(3, facingEast: true))
        try world.setTrainContinuation(Self.first, along: [Self.forward(4), Self.forward(8), Self.forward(9)])
        try world.setTrainMovementRate(Self.first, to: 5_000)
        try world.removeTrackEdge(.edge(8))

        try world.advance(ticks: 4)

        XCTAssertEqual(world.train(id: Self.first)?.position, Self.line.at(4, facingEast: true))
        XCTAssertEqual(world.train(id: Self.first)?.movement.cursor, 1)
        XCTAssertEqual(world.train(id: Self.first)?.movement.remainingEdges, [.edge(8), .edge(9)])
    }

    /// `testEachTrainMovesAsIfItWereAlone`: two moving trains end where each
    /// would alone, and stay in ID order.
    func testEachTrainMovesAsIfItWereAlone() throws {
        var together = try Self.makeLineWorld(trains: 2)
        try together.placeTrain(Self.first, at: Self.line.between(0, 1, offset: 5))
        try together.setTrainContinuation(Self.first, along: Self.line.path(from: 1, through: [2, 3, 4]) + [Self.forward(8), Self.forward(9)])
        try together.setTrainMovementRate(Self.first, to: 333)
        try together.placeTrain(Self.second, at: Self.line.between(7, 6, offset: 1_000))
        try together.setTrainContinuation(Self.second, along: Self.line.path(from: 6, through: [5, 4, 3]))
        try together.setTrainMovementRate(Self.second, to: 97)
        var onlyFirst = together
        try onlyFirst.setTrainMovementRate(Self.second, to: 0)
        var onlySecond = together
        try onlySecond.setTrainMovementRate(Self.first, to: 0)

        try together.advance(ticks: 25)
        try onlyFirst.advance(ticks: 25)
        try onlySecond.advance(ticks: 25)

        XCTAssertEqual(together.train(id: Self.first)?.position, onlyFirst.train(id: Self.first)?.position)
        XCTAssertEqual(together.train(id: Self.first)?.movement.cursor, onlyFirst.train(id: Self.first)?.movement.cursor)
        XCTAssertEqual(together.train(id: Self.second)?.position, onlySecond.train(id: Self.second)?.position)
        XCTAssertNotEqual(together.train(id: Self.first)?.position, Self.line.between(0, 1, offset: 5), "it moved")
        XCTAssertEqual(together.trains.map(\.id), [Self.first, Self.second], "trains stay in ID order")
    }

    /// A world a few seconds from the end of time with one train moving 1
    /// unit a minute, 1 unit along edge 1.
    private static func worldNearTheEndOfTime(secondsLeft: Int64, speed: GameSpeed) throws -> GameWorld {
        var world = try GameWorld(
            width: 20, height: 20,
            economy: GameEconomy(balance: 100_000, costs: testCosts),
            clock: GameClock(now: GameTime(seconds: .max - secondsLeft), speed: speed)
        )
        try TestLine(tiles: 3, row: 5).build(in: &world)
        try world.purchaseTrain(named: "Late")
        try world.placeTrain(first, at: .onEdge(forward(1), offset: 1))
        try world.setTrainMovementRate(first, to: 1)
        return world
    }

    /// `testTheLastMinutesCanBeReachedExactly`: the last three minutes of
    /// seconds, not on a whole minute, give the train its share of each,
    /// 1 + 1 + 1 + 0 units at 1 a minute.
    func testTheLastMinutesCanBeReachedExactlyWithATrainMoving() throws {
        var world = try Self.worldNearTheEndOfTime(secondsLeft: 180, speed: .normal)
        try world.advance(ticks: 0)
        try world.advance(ticks: 3)
        XCTAssertEqual(world.clock.now, GameTime(seconds: .max))
        XCTAssertEqual(world.train(id: Self.first)?.position, .onEdge(Self.forward(1), offset: 4))

        var double = try Self.worldNearTheEndOfTime(secondsLeft: 240, speed: .double)
        try double.advance(ticks: 2)
        XCTAssertEqual(double.clock.now, GameTime(seconds: .max))

        var realTime = try Self.worldNearTheEndOfTime(secondsLeft: 1, speed: .x1)
        try realTime.advance(ticks: 19)
        XCTAssertEqual(realTime.clock.now, GameTime(seconds: .max))
        XCTAssertEqual(realTime.clock.pendingTenths, 9)
    }

    /// `testABatchPastTheEndOfTimeIsRejectedWhole` and
    /// `testPausedBatchesNeverOverflow`: a batch that would pass the last
    /// second is refused whole, the train unmoved; paused, nothing
    /// overflows.
    func testABatchPastTheEndOfTimeIsRejectedWholeWithATrainMoving() throws {
        let cases: [(secondsLeft: Int64, speed: GameSpeed, ticks: Int)] = [
            (180, .normal, 4), (240, .double, 3), (300, .double, 3), (59, .normal, 1),
            (1, .x1, 20), (.max, .double, .max), (1_000, .x1, .max),
        ]
        for (secondsLeft, speed, ticks) in cases {
            var world = try Self.worldNearTheEndOfTime(secondsLeft: secondsLeft, speed: speed)
            let before = world
            XCTAssertThrowsGameError(try world.advance(ticks: ticks), .clockOverflow)
            XCTAssertEqual(world, before, "\(secondsLeft) \(speed) \(ticks): no train or second moved")
        }
        var paused = try Self.worldNearTheEndOfTime(secondsLeft: 0, speed: .paused)
        let before = paused
        try paused.advance(ticks: .max)
        XCTAssertEqual(paused, before)
    }

    /// `testIdleTrainsAreSavedWithoutAMovementAndOldSavesReadAsIdle`.
    func testIdleTrainsAreSavedWithoutAMovementAndOldSavesReadAsIdle() throws {
        var world = try Self.makeLineWorld(trains: 2)
        try world.placeTrain(Self.first, at: Self.line.at(1, facingEast: true))
        try world.placeTrain(Self.second, at: Self.line.at(3, facingEast: true))
        try world.setTrainMovementRate(Self.second, to: 10)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.encode(world)) as? [String: Any])
        let trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
        XCTAssertNil(trains[0]["movement"])
        XCTAssertNotNil(trains[1]["movement"])

        let old = try JSONDecoder().decode(Train.self, from: Data(#"{"id": 1, "name": "A", "position": {"onEdge": {"edge": 2, "direction": "forward", "offset": 512}}}"#.utf8))
        XCTAssertEqual(old.movement, .idle)
    }

    /// `testMalformedMovementIsRejectedNotReadAsIdle`: a train's movement
    /// on the network is refused, never read as idle, unless it is well
    /// formed and fits where the train is.
    func testMalformedNetworkMovementIsRejectedNotReadAsIdle() {
        // On edge 3 going forward, 300 along.
        let onEdge3 = #"{"onEdge": {"edge": 3, "direction": "forward", "offset": 300}}"#
        func movement(rate: String = "10", edges: String? = "[4, 5]", cursor: String = "0", end: String? = nil, continuation: String = "[]") -> String {
            let edges = edges.map { #", "edges": \#($0)"# } ?? ""
            let end = end.map { #", "end": \#($0)"# } ?? ""
            return #"{"rate": \#(rate), "continuation": \#(continuation), "cursor": \#(cursor)\#(edges)\#(end)}"#
        }
        func saved(_ position: String?, _ movement: String) -> Data {
            let position = position.map { #", "position": \#($0)"# } ?? ""
            return Data(#"{"id": 1, "name": "A"\#(position), "movement": \#(movement)}"#.utf8)
        }
        let malformed: [(position: String?, movement: String)] = [
            (onEdge3, "null"),
            (onEdge3, "{}"),
            (onEdge3, movement(rate: "-1")),
            (onEdge3, movement(rate: "1.5")),
            (onEdge3, movement(rate: #""fast""#)),
            (onEdge3, movement(cursor: "-1")),
            (onEdge3, movement(cursor: "2")), // spent but not emptied
            (onEdge3, movement(edges: "[]", cursor: "1")),
            (onEdge3, movement(edges: "null")),
            (onEdge3, movement(edges: "[0]")), // edges are numbered from 1
            (onEdge3, movement(edges: "[4, 4]")), // straight back along itself
            (onEdge3, movement(edges: "[3, 4]")), // the first edge left is the one it is on
            (onEdge3, movement(edges: "[2, 4]", cursor: "1")), // entered edge 2, but it is on edge 3
            (onEdge3, movement(end: "-1")),
            (onEdge3, movement(end: "0")), // above 0 while edges are left
            (onEdge3, movement(end: "null")),
            (onEdge3, movement(edges: nil, end: "100")), // the path would end behind it
            (onEdge3, movement(edges: nil, continuation: #"[{"x": 4, "y": 5}]"#)), // a grid continuation on the network
            (onEdge3, movement(continuation: #"[{"x": 4, "y": 5}]"#)),
            (nil, movement()), // an unplaced train is idle
            (nil, movement(edges: nil)),
        ]
        for (position, movement) in malformed {
            XCTAssertThrowsError(try JSONDecoder().decode(Train.self, from: saved(position, movement)), movement)
        }

        // The same shapes, consistent: accepted.
        let valid: [(position: String?, movement: String)] = [
            (onEdge3, movement()),
            (onEdge3, movement(edges: nil)),
            (onEdge3, movement(edges: nil, end: "300")),
            (onEdge3, movement(edges: nil, end: "700")),
            (onEdge3, movement(end: "1")),
            (onEdge3, movement(edges: "[3, 4]", cursor: "1")),
        ]
        for (position, movement) in valid {
            XCTAssertNoThrow(try JSONDecoder().decode(Train.self, from: saved(position, movement)), movement)
        }
    }

    // MARK: - Positions (TrainPositionTests)

    /// `testSharedTrackStaysProtectedUntilNoTrainIsOnIt`: an edge two trains
    /// stand on cannot be removed until both have left it.
    func testSharedTrackStaysProtectedUntilNoTrainIsOnIt() throws {
        var world = try Self.makeLineWorld(trains: 2)
        try world.placeTrain(Self.first, at: Self.line.between(1, 2, offset: 512))
        try world.placeTrain(Self.second, at: Self.line.between(2, 1, offset: 100))

        try world.unplaceTrain(Self.first)
        let before = world
        XCTAssertThrowsGameError(try world.removeTrackEdge(.edge(2)), .trackEdgeInUse(.edge(2)))
        XCTAssertEqual(world, before)

        try world.reverseTrain(Self.second)
        XCTAssertThrowsGameError(try world.removeTrackEdge(.edge(2)), .trackEdgeInUse(.edge(2)))

        try world.unplaceTrain(Self.second)
        try world.removeTrackEdge(.edge(2))
        XCTAssertNil(world.network.edge(.edge(2)))
    }

    /// `testTrainsSavedBeforePositionsExistedDecodeAsUnplaced`: a world
    /// whose trains have only an ID and a name loads with them unplaced,
    /// and IDs carry on.
    func testTrainsSavedWithoutAPositionLoadUnplaced() throws {
        var world = try Self.makeLineWorld(trains: 2)
        try world.placeTrain(Self.first, at: Self.line.at(2, facingEast: true))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.encode(world)) as? [String: Any])
        let trains = try XCTUnwrap(object["trains"] as? [[String: Any]]).map { train in
            var train = train
            train["position"] = nil
            return train
        }
        XCTAssertEqual(trains.map { Set($0.keys) }, [["id", "name"], ["id", "name"]])
        object["trains"] = trains

        var decoded = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))

        try world.unplaceTrain(Self.first)
        XCTAssertEqual(decoded, world)
        XCTAssertEqual(try decoded.purchaseTrain(named: "T3").id, TrainID(rawValue: 3))
    }

    // MARK: - Routes (TrainRouteTests)

    /// `testALargeGridIsSearchedWithoutTrouble`: a route along a line of
    /// 199 edges, and none to a node no track reaches.
    func testALongLineIsSearchedWithoutTrouble() throws {
        var world = try makeWorld(width: 200, height: 3, balance: 1_000_000_000)
        let long = TestLine(tiles: 200, row: 1)
        try long.build(in: &world)
        let island = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 2_560))
        let start = long.at(0, facingEast: true)
        XCTAssertEqual(world.route(from: start, to: long.node(199)), long.path(from: 0, through: Array(1...199)).dropFirst().map { $0 })
        XCTAssertNil(world.route(from: start, to: island))
    }

    // MARK: - Stops (StationStopTests)

    /// `testWaitingAtAPlatformForRemovedTrackIsNotAStop`: a train on a
    /// platform with path left, waiting for an edge that was removed, is
    /// not stopped there; once its path is cleared it is.
    func testWaitingAtAPlatformForRemovedTrackIsNotAStop() throws {
        var world = try Self.makeLineWorld()
        let station = try world.buildStation(named: "Mid", at: TestLine.centre(1, 4)).id
        try world.addTrackPlatform(station, on: .edge(1), from: 0, to: 1_024)
        try world.placeTrain(Self.first, at: Self.line.between(0, 1, offset: 256))
        try world.setTrainContinuation(Self.first, along: Self.line.path(from: 1, through: [2, 3]))
        try world.setTrainMovementRate(Self.first, to: 1_024)
        try world.removeTrackEdge(.edge(2))

        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: Self.first)?.position, Self.line.at(1, facingEast: true), "on the platform's end")
        XCTAssertEqual(world.stationsStoppedAt(by: Self.first), [], "waiting, not stopped")

        try world.setTrainContinuation(Self.first, along: [])
        XCTAssertEqual(world.stationsStoppedAt(by: Self.first), [station])
    }

    /// `testStationsAreListedInAscendingIDOrder`: where two stations'
    /// platforms touch, a train standing there is at both, listed by ID
    /// whatever order the platforms were added in.
    func testStationsAreListedInAscendingIDOrder() throws {
        var world = try Self.makeLineWorld()
        let low = try world.buildStation(named: "Low", at: TestLine.centre(2, 4)).id
        let high = try world.buildStation(named: "High", at: TestLine.centre(1, 4)).id
        try world.addTrackPlatform(high, on: .edge(2), from: 0, to: 512)
        try world.addTrackPlatform(low, on: .edge(2), from: 512, to: 1_024)
        try world.placeTrain(Self.first, at: Self.line.between(1, 2, offset: 512))
        try world.setTrainContinuation(Self.first, along: [], stoppingAt: 512)
        XCTAssertEqual(world.stationsStoppedAt(by: Self.first), [low, high])
    }

    /// `testAnUnknownStationHasNoPlatforms` and the unknown train in
    /// `testATrainStandingOnAPlatformWithNoContinuationIsStopped`.
    func testUnknownStationsAndTrainsHaveNoPlatformsOrStops() throws {
        let world = try Self.makeLineWorld()
        XCTAssertEqual(world.trackPlatforms(of: StationID(rawValue: 9)), [])
        XCTAssertEqual(world.stationsStoppedAt(by: TrainID(rawValue: 9)), [])
    }

    // MARK: - Cars (StationFacilityTests)

    /// `testCarsAreSetOffTheTrack`: 1 to 16 cars, set only off the track,
    /// refused in the order unknown train, invalid length, placed; taken
    /// off the track, a train keeps its cars.
    func testCarsAreSetOffTheTrack() throws {
        var world = try Self.makeLineWorld()
        let id = Self.first
        XCTAssertEqual(world.train(id: id)?.cars, 1)
        XCTAssertEqual(world.train(id: id)?.length, 0)

        XCTAssertThrowsGameError(try world.setTrainCars(TrainID(rawValue: 9), to: 17), .unknownTrain(TrainID(rawValue: 9)))
        XCTAssertThrowsGameError(try world.setTrainCars(id, to: 0), .invalidTrainLength)
        XCTAssertThrowsGameError(try world.setTrainCars(id, to: 17), .invalidTrainLength)

        try world.setTrainCars(id, to: 16)
        XCTAssertEqual(world.train(id: id)?.length, 15 * 1_024)
        try world.setTrainCars(id, to: 3)
        XCTAssertEqual(world.train(id: id)?.length, 2_048)

        try world.placeTrain(id, at: Self.line.at(5, facingEast: true))
        XCTAssertThrowsGameError(try world.setTrainCars(id, to: 17), .invalidTrainLength)
        XCTAssertThrowsGameError(try world.setTrainCars(id, to: 2), .trainAlreadyPlaced(id))
        XCTAssertEqual(world.train(id: id)?.cars, 3)
        XCTAssertEqual(world.train(id: id)?.trailEdges, [.edge(4)])

        // Taken off the track, it keeps its cars and loses its body.
        try world.unplaceTrain(id)
        XCTAssertEqual(world.train(id: id)?.cars, 3)
        XCTAssertEqual(world.train(id: id)?.trailEdges, [])
    }

    /// `testSavesKeepStationsAndBodies`: one car is saved without `cars`;
    /// `null`, 0 or 17 cars are refused.
    func testCarsAreSavedOnlyAboveOneAndRefusedOutOfRange() throws {
        var world = try Self.makeLineWorld(trains: 2)
        try world.setTrainCars(Self.first, to: 3)
        try world.placeTrain(Self.first, at: Self.line.at(5, facingEast: true))
        try world.placeTrain(Self.second, at: Self.line.at(7, facingEast: true))
        let data = try Self.encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let trains = try XCTUnwrap(json["trains"] as? [[String: Any]])
        XCTAssertEqual(trains[0]["cars"] as? Int, 3)
        XCTAssertNil(trains[1]["cars"])
        for (what, value) in [("null cars", NSNull() as Any), ("no cars", 0), ("too many cars", 17)] {
            var copy = json
            var changed = trains
            changed[0]["cars"] = value
            copy["trains"] = changed
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: copy)), what)
        }
    }

    // MARK: - Track counts (TrackResourceTests)

    /// The unknown-line part of `testParallelTracksCountTracksThatShareNoLink`.
    func testAnUnknownLineHasNoTrackCounts() throws {
        XCTAssertNil(try Self.makeLineWorld().lineTrackCounts(LineID(rawValue: 9)))
    }
}
