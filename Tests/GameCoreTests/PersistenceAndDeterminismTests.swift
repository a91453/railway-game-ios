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

    func testSameActionsProduceIdenticalWorlds() throws {
        var first = try makeWorld(balance: 100_000)
        var second = try makeWorld(balance: 100_000)

        try playScript(on: &first)
        try playScript(on: &second)

        XCTAssertEqual(first, second)
        XCTAssertEqual(try encode(first), try encode(second))
    }
}
