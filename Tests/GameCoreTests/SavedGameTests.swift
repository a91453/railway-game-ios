import Foundation
import GameCore
import XCTest

/// Stage C4: the versioned save. Version 1 is the world's `Codable` form;
/// version 2 (Stage E1) writes only the map's occupied tiles. Unknown
/// versions are refused, and every committed save in `SaveFixtures/` keeps
/// loading (see its README).
final class SavedGameTests: XCTestCase {
    private func makeWorld() throws -> GameWorld {
        var world = try GameWorld(
            width: 16, height: 8, economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 3_072))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 2_048, y: 3_072)).id
        let east = try world.buildStation(named: "East", at: GridPosition(x: 7, y: 4)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 3_072)
        try world.addTrackPlatform(east, on: edge, from: 6_144, to: 8_192)
        try world.createLine(named: "Main", stops: [west, east])
        try world.advance(ticks: 3)
        return world
    }

    func testASaveIsTheVersionAndTheWorld() throws {
        let world = try makeWorld()
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["saveVersion", "world"])
        XCTAssertEqual(object["saveVersion"] as? Int, 2)
        XCTAssertEqual(SavedGame.currentVersion, 2)
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        // The world inside is exactly the world's own form.
        let world2 = try JSONSerialization.data(withJSONObject: object["world"] as Any)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: world2), world)
    }

    func testUnknownVersionsAndBadWorldsAreRefused() throws {
        let world = String(decoding: try JSONEncoder().encode(try makeWorld()), as: UTF8.self)
        func decode(_ json: String) throws -> SavedGame {
            try JSONDecoder().decode(SavedGame.self, from: Data(json.utf8))
        }
        XCTAssertNoThrow(try decode(#"{"saveVersion": 1, "world": \#(world)}"#))
        XCTAssertNoThrow(try decode(#"{"saveVersion": 2, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": 3, "world": \#(world)}"#), "a later version is not guessed at")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 0, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": -1, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": "1", "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"world": \#(world)}"#), "no version")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 1}"#), "no world")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 1, "world": {}}"#), "GameCore refuses the world")
    }

    /// Version 2 (Stage E1): the map is its size and the tiles that are not
    /// empty ground, each with its position, in row-major order. The form
    /// before it, every tile written out, still reads into the same world.
    func testTheMapIsSavedAsItsOccupiedTiles() throws {
        var world = try makeWorld()
        // Grid track from an old save stays on the map as a tile.
        world = try JSONDecoder().decode(GameWorld.self, from: Data(try Self.replacingMap(of: world, with: Self.denseMap(of: world, track: (x: 2, y: 6))).utf8))
        XCTAssertEqual(world.network.tracks.map(\.position), [GridPosition(x: 2, y: 6)])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        let map = try XCTUnwrap(object["map"] as? [String: Any])
        XCTAssertEqual(Set(map.keys), ["width", "height", "occupied"])
        XCTAssertEqual(map["width"] as? Int, 16)
        XCTAssertEqual(map["height"] as? Int, 8)
        let occupied = try XCTUnwrap(map["occupied"] as? [[String: Any]])
        XCTAssertEqual(occupied.map { [$0["x"] as? Int, $0["y"] as? Int] }, [[7, 4], [2, 6]])
        XCTAssertEqual(occupied[0]["tile"] as? [String: [String: Int]], ["station": ["id": 2]])
        XCTAssertEqual(occupied[1]["tile"] as? [String: [String: Int]], ["track": ["connections": 10]])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    /// A new game's 16 km map (Stage E1) saves in a few hundred bytes: the
    /// map that wrote every tile made it 13 MB.
    func testALargeMapSavesOnlyWhatStandsOnIt() throws {
        var world = try GameWorld(width: 1_024, height: 1_024, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try world.buildStation(named: "Far", at: GridPosition(x: 1_000, y: 1_020))
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertLessThan(data.count, 1_000)
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
    }

    func testMalformedMapsAreRefused() throws {
        let world = try makeWorld()
        func load(_ map: String) -> GameWorld? {
            try? JSONDecoder().decode(GameWorld.self, from: Data(Self.replacingMap(of: world, with: map).utf8))
        }
        let station = #"{"station":{"id":2}}"#
        XCTAssertEqual(load(#"{"width":16,"height":8,"occupied":[{"x":7,"y":4,"tile":\#(station)}]}"#), world)
        XCTAssertEqual(load(try Self.denseMap(of: world)), world)
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[]}"#), "the station's tile is missing")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":16,"y":4,"tile":\#(station)}]}"#), "off the map")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":-1,"y":4,"tile":\#(station)}]}"#), "off the map")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":7,"y":4,"tile":\#(station)},{"x":7,"y":4,"tile":\#(station)}]}"#), "repeated")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":7,"y":4,"tile":\#(station)},{"x":1,"y":1,"tile":{"track":{"connections":10}}}]}"#), "out of order")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":1,"y":1,"tile":{"empty":{}}},{"x":7,"y":4,"tile":\#(station)}]}"#), "an empty tile listed")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":1,"y":1,"tile":{"track":{"connections":0}}},{"x":7,"y":4,"tile":\#(station)}]}"#), "track without exits")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":7,"y":4}]}"#), "no tile")
        XCTAssertNil(load(#"{"width":16,"height":8}"#), "neither form")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":7,"y":4,"tile":\#(station)}],"tiles":[]}"#), "both forms")
        XCTAssertNil(load(#"{"width":1025,"height":8,"occupied":[{"x":7,"y":4,"tile":\#(station)}]}"#), "too wide")
        XCTAssertNil(load(#"{"width":0,"height":8,"occupied":[]}"#), "no size")
    }

    /// `world`'s JSON with its map replaced by `map`.
    private static func replacingMap(of world: GameWorld, with map: String) throws -> String {
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        object["map"] = try JSONSerialization.jsonObject(with: Data(map.utf8))
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// `world`'s map with every tile written out, as saves of version 1
    /// wrote it, and an east–west grid track piece at `track` if given.
    private static func denseMap(of world: GameWorld, track: (x: Int, y: Int)? = nil) throws -> String {
        let tiles = world.map.tiles.map { tile -> String in
            if let track, tile.position == GridPosition(x: track.x, y: track.y) {
                return #"{"track":{"connections":10}}"#
            }
            switch tile.type {
            case .empty: return #"{"empty":{}}"#
            case .station(let id): return #"{"station":{"id":\#(id.rawValue)}}"#
            }
        }
        return #"{"width":\#(world.map.width),"height":\#(world.map.height),"tiles":[\#(tiles.joined(separator: ","))]}"#
    }

    /// Every committed save of every version still loads, round-trips and
    /// runs on.
    func testEveryCommittedSaveStillLoads() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path).filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            let data = try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
            let game = try JSONDecoder().decode(SavedGame.self, from: data)
            let again = try JSONDecoder().decode(SavedGame.self, from: try JSONEncoder().encode(game))
            XCTAssertEqual(again, game, name)
            var world = game.world
            XCTAssertNoThrow(try world.advance(ticks: 60), name)
        }
    }

    /// The version 1 save: the demo map after 90 minutes (Stage C4), with
    /// stations at points, an elevated edge, lines, trains under traffic
    /// control, waiting passengers and the company's accounts.
    func testTheVersionOneSaveReadsAsItWasWritten() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v1-demo-90-minutes.json"))
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world.clock.now, GameTime(minutes: 90))
        XCTAssertEqual(world.stations.map(\.name), ["West", "Central", "East", "North", "South"])
        XCTAssertEqual(world.stations[1].point, PlanPoint(x: 16_384, y: 12_288))
        XCTAssertEqual(world.trackPlatforms(of: world.stations[1].id).count, 2)
        XCTAssertEqual(world.network.edges.map(\.structure), [.surface, .elevated])
        XCTAssertEqual(world.lines.map(\.name), ["Line 1", "Line 2"])
        XCTAssertEqual(world.trains.map(\.name), ["Train 1", "Train 2"])
        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertEqual(world.accounts.mode, .management)
        XCTAssertEqual(world.economy.balance, Money(-60_600))
    }

    /// The version 2 save (Stage E1): the demo map after 90 minutes, in the
    /// middle of a new game's 16 km map, which is saved as its size and no
    /// occupied tiles.
    func testTheVersionTwoSaveReadsAsItWasWritten() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v2-demo-90-minutes.json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 2)
        let map = try XCTUnwrap((object["world"] as? [String: Any])?["map"] as? [String: Any])
        XCTAssertEqual(map["width"] as? Int, 1_024)
        XCTAssertEqual(map["height"] as? Int, 1_024)
        XCTAssertEqual((map["occupied"] as? [Any])?.count, 0)

        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world.map.width, 1_024)
        XCTAssertEqual(world.clock.now, GameTime(minutes: 90))
        XCTAssertEqual(world.stations.map(\.name), ["West", "Central", "East", "North", "South"])
        XCTAssertEqual(world.stations[1].point, PlanPoint(x: 524_288, y: 524_288))
        XCTAssertEqual(world.trackPlatforms(of: world.stations[1].id).count, 2)
        XCTAssertEqual(world.network.edges.map(\.structure), [.surface, .elevated])
        XCTAssertEqual(world.lines.map(\.name), ["Line 1", "Line 2"])
        XCTAssertEqual(world.trains.map(\.name), ["Train 1", "Train 2"])
        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertEqual(world.accounts.mode, .management)
        XCTAssertEqual(world.economy.balance, Money(131_595_600))
    }

    /// `SaveFixtures/` at the repository root, found from this source file.
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures", isDirectory: true)
}
