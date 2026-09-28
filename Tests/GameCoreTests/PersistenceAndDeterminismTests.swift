import Foundation
import GameCore
import XCTest

final class PersistenceAndDeterminismTests: XCTestCase {
    /// A fixed sequence of player actions used by several tests.
    private func playScript(on world: inout GameWorld) throws {
        world.setSpeed(.normal)
        try world.buildStation(named: "West", at: GridPosition(x: 1, y: 5))
        for x in 2...8 {
            try world.buildTrack(at: GridPosition(x: x, y: 5), connections: [.east, .west])
        }
        try world.buildStation(named: "East", at: GridPosition(x: 9, y: 5))
        try world.buildTrack(at: GridPosition(x: 5, y: 6), connections: [.north, .south])
        try world.removeTrack(at: GridPosition(x: 5, y: 6))
        try world.purchaseTrain(named: "Local 1")
        try world.advance(ticks: 90)
        world.setSpeed(.double)
        try world.advance(ticks: 45)
    }

    private func encode(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(world)
    }

    func testCodableRoundTripPreservesWorld() throws {
        var world = try makeWorld(balance: 100_000)
        try playScript(on: &world)

        let decoded = try JSONDecoder().decode(GameWorld.self, from: try encode(world))

        XCTAssertEqual(decoded, world)
        XCTAssertEqual(decoded.stations.map(\.name), ["West", "East"])
        XCTAssertEqual(decoded.clock.now, GameTime(minutes: 180))
    }

    func testDecodedWorldContinuesAllocatingFreshIDs() throws {
        var world = try makeWorld(balance: 100_000)
        try playScript(on: &world)
        var decoded = try JSONDecoder().decode(GameWorld.self, from: try encode(world))

        let station = try decoded.buildStation(named: "North", at: GridPosition(x: 5, y: 0))

        XCTAssertFalse(world.stations.map(\.id).contains(station.id))
    }

    func testDecodingRejectsMapWithWrongTileCount() throws {
        let json = Data(#"{"width":2,"height":2,"tiles":[{"empty":{}}]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(GridMap.self, from: json)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
        }
    }

    func testDecodingRejectsStationWithoutMatchingTile() throws {
        var world = try makeWorld(balance: 100_000)
        try world.buildStation(named: "West", at: GridPosition(x: 1, y: 1))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(world)) as? [String: Any])
        var stations = try XCTUnwrap(object["stations"] as? [[String: Any]])
        stations[0]["position"] = ["x": 2, "y": 2]
        object["stations"] = stations
        let corrupted = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: corrupted)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
        }
    }

    // MARK: - Values no command can produce are refused as they load

    /// A saved world with its JSON object edited by `change`.
    private func savedWorld(_ change: (inout [String: Any]) throws -> Void) throws -> Data {
        var world = try makeWorld(balance: 100_000)
        try world.buildTrack(at: GridPosition(x: 1, y: 1), connections: [.east, .west])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try encode(world)) as? [String: Any])
        try change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func assertDataCorrupted<T: Decodable>(_ type: T.Type, _ data: Data, _ message: String = "", line: UInt = #line) {
        XCTAssertThrowsError(try JSONDecoder().decode(type, from: data), message, line: line) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("\(message): expected dataCorrupted, got \(error)", line: line)
            }
        }
    }

    /// A negative price is a refund that `GameEconomy.spend(_:)` treats as a
    /// programming error. A save holding one used to load, and the next
    /// purchase then trapped; it is refused as it loads, like other bad data.
    func testDecodingRejectsNegativeConstructionCosts() throws {
        for key in ["track", "station", "train"] {
            let data = try savedWorld { object in
                var economy = try XCTUnwrap(object["economy"] as? [String: Any])
                var costs = try XCTUnwrap(economy["costs"] as? [String: Any])
                costs[key] = -1
                economy["costs"] = costs
                object["economy"] = economy
            }
            assertDataCorrupted(GameWorld.self, data, key)
        }
        assertDataCorrupted(ConstructionCosts.self, Data(#"{"track": 1, "station": -9223372036854775808, "train": 1}"#.utf8))

        // Zero is a price, and saved costs load as they were.
        let free = try JSONDecoder().decode(ConstructionCosts.self, from: Data(#"{"track": 0, "station": 0, "train": 0}"#.utf8))
        XCTAssertEqual(free, ConstructionCosts(track: 0, station: 0, train: 0))
        let standard = try JSONDecoder().decode(ConstructionCosts.self, from: try JSONEncoder().encode(ConstructionCosts.standard))
        XCTAssertEqual(standard, .standard)
    }

    /// `resume()` returns to the last running speed, which is never
    /// `.paused`. A save claiming otherwise used to load a clock that
    /// `resume()` left paused; it is refused as it loads.
    func testDecodingRejectsAClockThatWouldResumePaused() throws {
        assertDataCorrupted(GameClock.self, Data(#"{"now": 0, "speed": "paused", "resumeSpeed": "paused"}"#.utf8))
        assertDataCorrupted(GameClock.self, Data(#"{"now": 5, "speed": "normal", "resumeSpeed": "paused"}"#.utf8))
        let data = try savedWorld { object in
            var clock = try XCTUnwrap(object["clock"] as? [String: Any])
            clock["resumeSpeed"] = "paused"
            object["clock"] = clock
        }
        assertDataCorrupted(GameWorld.self, data)

        // Every clock the commands can make still loads unchanged, and
        // resumes where it should.
        for start in GameSpeed.allCases {
            for next in GameSpeed.allCases {
                var clock = GameClock(now: GameTime(minutes: 7), speed: start)
                clock.setSpeed(next)
                clock.pause()
                let loaded = try JSONDecoder().decode(GameClock.self, from: try JSONEncoder().encode(clock))
                XCTAssertEqual(loaded, clock, "\(start) then \(next)")
                var resumed = loaded
                resumed.resume()
                XCTAssertEqual(resumed.speed, next == .paused ? (start == .paused ? .normal : start) : next, "\(start) then \(next)")
            }
        }
    }

    func testSameActionsProduceIdenticalWorlds() throws {
        var first = try makeWorld(balance: 100_000)
        var second = try makeWorld(balance: 100_000)

        try playScript(on: &first)
        try playScript(on: &second)

        XCTAssertEqual(first, second)
        XCTAssertEqual(try encode(first), try encode(second))
    }
}
