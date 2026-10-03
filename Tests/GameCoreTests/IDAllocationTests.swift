import Foundation
import GameCore
import XCTest

/// Station and train IDs come from two independent counters. Each counter
/// holds the next ID to hand out: it starts at 1, a build or purchase takes
/// its value as the new ID and then adds 1, and every ID in the world is
/// below it (decoding checks that). The counter is an `Int`, so an ID can be
/// handed out only while adding 1 to the counter still fits: the last one is
/// `Int.max - 1`, which leaves the counter at `Int.max`. `Int.max` itself can
/// never be an ID, because no counter can be above it.
///
/// A world whose counter is at `Int.max` is exhausted for that kind: the
/// command is refused with `idsExhausted`, the world is unchanged, and the
/// other kind is unaffected. Such a world is reachable through commands
/// (from a save near the end), so it loads; counters no world can have
/// (not above every ID of their kind, or not positive) are refused as they
/// load. Before this was handled, the allocation after `Int.max - 1`
/// trapped on overflow, after the cost had been charged.
final class IDAllocationTests: XCTestCase {
    // Track on the network (Stage F3b, see `TestLine`): nodes at the
    // centres of tiles (0, 1) to (2, 1), edges 1 and 2 between them.
    // Stations stand at points (Stage F1).
    private let line = TestLine(tiles: 3)
    private let free = TestLine.centre(5, 5)

    private func encode(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(world)
    }

    private func object(_ world: GameWorld) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(world)) as? [String: Any])
    }

    /// The saved counters: the next station ID and the next train ID.
    private func counters(_ world: GameWorld) throws -> (station: Int, train: Int) {
        let saved = try object(world)
        return (try XCTUnwrap(saved["nextStationID"] as? Int), try XCTUnwrap(saved["nextTrainID"] as? Int))
    }

    /// A world with track, one station (ID 1) and one placed train (ID 1),
    /// saved with the given counters and loaded again.
    private func world(nextStationID: Int = 2, nextTrainID: Int = 2) throws -> GameWorld {
        var world = try makeWorld(balance: 10_000_000)
        try line.build(in: &world)
        try world.buildStation(named: "Yard", at: TestLine.centre(3, 1))
        let train = try world.purchaseTrain(named: "Local")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        world.setSpeed(.normal)
        var saved = try object(world)
        saved["nextStationID"] = nextStationID
        saved["nextTrainID"] = nextTrainID
        return try JSONDecoder().decode(GameWorld.self, from: try JSONSerialization.data(withJSONObject: saved))
    }

    // MARK: - Allocation

    func testIDsStartAtOneAndCountUpPerKind() throws {
        var world = try makeWorld(balance: 1_000_000)
        XCTAssertEqual(try counters(world).station, 1)
        XCTAssertEqual(try counters(world).train, 1)

        XCTAssertEqual(try world.buildStation(named: "A", at: TestLine.centre(0, 0)).id.rawValue, 1)
        XCTAssertEqual(try world.purchaseTrain(named: "A").id.rawValue, 1)
        XCTAssertEqual(try world.buildStation(named: "B", at: TestLine.centre(1, 0)).id.rawValue, 2)
        XCTAssertEqual(try world.purchaseTrain(named: "B").id.rawValue, 2)
        XCTAssertEqual(try world.purchaseTrain(named: "C").id.rawValue, 3)

        XCTAssertEqual(try counters(world).station, 3)
        XCTAssertEqual(try counters(world).train, 4)
    }

    func testIDsNearTheEndAreHandedOutAsUsual() throws {
        var world = try world(nextStationID: .max - 6, nextTrainID: .max - 5)
        let stations = try (0..<3).map { index in
            try world.buildStation(named: "S\(index)", at: TestLine.centre(index, 3)).id.rawValue
        }
        let trains = try (0..<3).map { index in try world.purchaseTrain(named: "T\(index)").id.rawValue }

        XCTAssertEqual(stations, [.max - 6, .max - 5, .max - 4])
        XCTAssertEqual(trains, [.max - 5, .max - 4, .max - 3])
        XCTAssertEqual(try counters(world).station, .max - 3)
        XCTAssertEqual(try counters(world).train, .max - 2)
    }

    /// `Int.max - 1` is handed out, as the last ID, with every usual effect.
    func testTheLastIDIsIntMaxMinusOne() throws {
        var world = try world(nextStationID: .max - 1, nextTrainID: .max - 1)
        let before = world

        let train = try world.purchaseTrain(named: "Last train")
        let station = try world.buildStation(named: "Last station", at: free)

        XCTAssertEqual(train.id, TrainID(rawValue: .max - 1))
        XCTAssertEqual(train.position, nil)
        XCTAssertEqual(world.trains.map(\.id), before.trains.map(\.id) + [train.id])
        XCTAssertEqual(station.id, StationID(rawValue: .max - 1))
        XCTAssertEqual(world.stations.map(\.id), before.stations.map(\.id) + [station.id])
        XCTAssertEqual(world.station(id: station.id)?.point, free)
        XCTAssertEqual(world.economy.balance, before.economy.balance - testCosts.train - testCosts.station)
        XCTAssertEqual(try counters(world).station, .max)
        XCTAssertEqual(try counters(world).train, .max)
    }

    // MARK: - Exhaustion

    /// The allocation after the last one is refused, every time, and the
    /// world stays exactly as it was: no charge, no train, no station, no
    /// counter change. It used to trap on overflow.
    func testAfterTheLastIDBuildingAndBuyingAreRefusedAndChangeNothing() throws {
        var world = try world(nextStationID: .max - 1, nextTrainID: .max - 1)
        try world.purchaseTrain(named: "Last train")
        try world.buildStation(named: "Last station", at: free)
        let exhausted = world
        let saved = try encode(world)

        for attempt in 1...3 {
            XCTAssertThrowsGameError(try world.purchaseTrain(named: "One too many"), .idsExhausted)
            XCTAssertThrowsGameError(try world.buildStation(named: "One too many", at: TestLine.centre(6, 6)), .idsExhausted)
            XCTAssertEqual(world, exhausted, "attempt \(attempt)")
            XCTAssertEqual(try encode(world), saved, "attempt \(attempt)")
        }
        // No ID was handed out twice, and none wrapped around.
        XCTAssertEqual(world.trains.map(\.id.rawValue), [1, .max - 1])
        XCTAssertEqual(world.stations.map(\.id.rawValue), [1, .max - 1])

        // The rest of the world still works.
        let node = try world.buildTrackNode(at: WorldCoordinate(x: TestLine.centre(3, 1).x, y: TestLine.centre(3, 1).y))
        let edge = try world.buildTrackEdge(from: line.node(2), to: node)
        try world.setTrainMovementRate(TrainID(rawValue: 1), to: 512)
        try world.setTrainContinuation(TrainID(rawValue: 1), along: line.path(from: 1, through: [2]) + [TrackTraversal(edge: edge, direction: .forward)])
        try world.advance(ticks: 1)
        XCTAssertNotEqual(world.train(id: TrainID(rawValue: 1))?.position, exhausted.train(id: TrainID(rawValue: 1))?.position)
    }

    /// The two counters are independent: running out of one kind does not
    /// stop the other.
    func testRunningOutOfOneKindLeavesTheOtherKindAlone() throws {
        var trainsExhausted = try world(nextTrainID: .max)
        XCTAssertThrowsGameError(try trainsExhausted.purchaseTrain(named: "No"), .idsExhausted)
        XCTAssertEqual(try trainsExhausted.buildStation(named: "Yes", at: free).id, StationID(rawValue: 2))

        var stationsExhausted = try world(nextStationID: .max)
        XCTAssertThrowsGameError(try stationsExhausted.buildStation(named: "No", at: free), .idsExhausted)
        XCTAssertEqual(try stationsExhausted.purchaseTrain(named: "Yes").id, TrainID(rawValue: 2))
    }

    /// Rejections keep their order: a bad name or point is reported first,
    /// then running out of IDs, and only then the price, which is checked
    /// last because paying is the first change a command makes. (A station
    /// at a point takes no tile, so track under it refuses nothing.)
    func testExhaustionIsCheckedAfterTheInputsAndBeforeThePrice() throws {
        let world = try world(nextStationID: .max, nextTrainID: .max)

        var copy = world
        XCTAssertThrowsGameError(try copy.purchaseTrain(named: "  "), .invalidName)
        XCTAssertThrowsGameError(try copy.buildStation(named: "  ", at: free), .invalidName)
        XCTAssertThrowsGameError(try copy.buildStation(named: "Off", at: PlanPoint(x: -1, y: 0)), .outOfBounds(GridPosition(x: -1, y: 0)))
        XCTAssertEqual(copy, world)

        // Without the money either, running out of IDs is what is reported.
        var broke = try makeWorld(balance: 0)
        var saved = try object(broke)
        saved["nextStationID"] = Int.max
        saved["nextTrainID"] = Int.max
        broke = try JSONDecoder().decode(GameWorld.self, from: try JSONSerialization.data(withJSONObject: saved))
        let brokeBefore = broke
        XCTAssertThrowsGameError(try broke.purchaseTrain(named: "Train"), .idsExhausted)
        XCTAssertThrowsGameError(try broke.buildStation(named: "Station", at: free), .idsExhausted)
        XCTAssertEqual(broke, brokeBefore)
    }

    // MARK: - Saving and loading

    /// Worlds near or at the end of the IDs are ordinary worlds: they save,
    /// load back equal, and carry on the same way after loading.
    func testWorldsNearAndAtTheEndSaveAndLoad() throws {
        for next in [Int.max - 2, Int.max - 1, Int.max] {
            let world = try world(nextStationID: next, nextTrainID: next)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: try encode(world))
            XCTAssertEqual(loaded, world, "next \(next)")
            XCTAssertEqual(try encode(loaded), try encode(world), "next \(next)")

            var original = world
            var reloaded = loaded
            let originalResult = Result { () throws(GameError) in try original.purchaseTrain(named: "Next").id }
            let reloadedResult = Result { () throws(GameError) in try reloaded.purchaseTrain(named: "Next").id }
            XCTAssertEqual(originalResult, reloadedResult, "next \(next)")
            XCTAssertEqual(reloaded, original, "next \(next)")
        }

        // A world that ran out through commands loads, and stays out.
        var world = try world(nextTrainID: .max - 1)
        try world.purchaseTrain(named: "Last")
        var loaded = try JSONDecoder().decode(GameWorld.self, from: try encode(world))
        XCTAssertEqual(loaded, world)
        XCTAssertThrowsGameError(try loaded.purchaseTrain(named: "One too many"), .idsExhausted)
        XCTAssertEqual(loaded, world)
    }

    /// Counters no world can have are refused as they load. A large counter
    /// is not one of them: `Int.max` loads (above).
    func testDecodingRejectsCountersNoWorldCanHave() throws {
        let world = try world()
        let invalid: [(String, Int)] = [
            // Not above the IDs already handed out (station 1, train 1).
            ("nextStationID", 1), ("nextTrainID", 1),
            // Not positive: counting starts at 1 and only goes up.
            ("nextStationID", 0), ("nextTrainID", 0),
            ("nextStationID", -1), ("nextTrainID", -1),
            ("nextStationID", .min), ("nextTrainID", .min),
        ]
        for (key, value) in invalid {
            var saved = try object(world)
            saved[key] = value
            assertDataCorrupted(try JSONSerialization.data(withJSONObject: saved), "\(key) \(value)")
        }

        // An ID at or above its counter, even at the very end.
        for (key, list) in [("nextTrainID", "trains"), ("nextStationID", "stations")] {
            var saved = try object(world)
            var entries = try XCTUnwrap(saved[list] as? [[String: Any]])
            entries[0]["id"] = Int.max
            saved[list] = entries
            saved[key] = Int.max
            assertDataCorrupted(try JSONSerialization.data(withJSONObject: saved), "\(list) ID Int.max")
        }

        // A counter past Int.max does not fit and is not read as anything else.
        let text = try XCTUnwrap(String(data: try encode(world), encoding: .utf8))
        for key in ["nextStationID", "nextTrainID"] {
            let tooLarge = text.replacingOccurrences(of: "\"\(key)\":2", with: "\"\(key)\":9223372036854775808")
            XCTAssertNotEqual(tooLarge, text)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(tooLarge.utf8)), key)
        }
    }

    private func assertDataCorrupted(_ data: Data, _ message: String, line: UInt = #line) {
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: data), message, line: line) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("\(message): expected dataCorrupted, got \(error)", line: line)
            }
        }
    }
}
