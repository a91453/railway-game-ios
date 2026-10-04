import Foundation
import GameCore
import XCTest

/// Stage C4: the versioned save. Version 1 is the world's `Codable` form;
/// version 2 (Stage E1) writes only the map's occupied tiles; version 3
/// (decision 49) can hold ring lines; version 4 (Stage E2) a real-world
/// map's anchor. Unknown versions are refused, and
/// every committed save in `SaveFixtures/` keeps loading (see its README).
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
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 7_680, y: 4_608)).id
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
        XCTAssertEqual(object["saveVersion"] as? Int, 4)
        XCTAssertEqual(SavedGame.currentVersion, 4)
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
        XCTAssertNoThrow(try decode(#"{"saveVersion": 3, "world": \#(world)}"#))
        XCTAssertNoThrow(try decode(#"{"saveVersion": 4, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": 5, "world": \#(world)}"#), "a later version is not guessed at")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 0, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": -1, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": "1", "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"world": \#(world)}"#), "no version")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 1}"#), "no world")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 1, "world": {}}"#), "GameCore refuses the world")
    }

    /// Version 2 (Stage E1): the map is its size and the tiles that are not
    /// empty ground, each with its position, in row-major order: none since
    /// Stage F3c, when the grid's track and tile stations went. The form
    /// before it, every tile written out, still reads into the same world.
    func testTheMapIsSavedAsItsOccupiedTiles() throws {
        let world = try makeWorld()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        let map = try XCTUnwrap(object["map"] as? [String: Any])
        XCTAssertEqual(Set(map.keys), ["width", "height", "occupied"])
        XCTAssertEqual(map["width"] as? Int, 16)
        XCTAssertEqual(map["height"] as? Int, 8)
        XCTAssertEqual((map["occupied"] as? [Any])?.count, 0)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(Self.replacingMap(of: world, with: Self.denseMap(of: world)).utf8)), world)
    }

    /// A new game's 16 km map (Stage E1) saves in a few hundred bytes: the
    /// map that wrote every tile made it 13 MB.
    func testALargeMapSavesOnlyWhatStandsOnIt() throws {
        var world = try GameWorld(width: 1_024, height: 1_024, economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try world.buildStation(named: "Far", at: PlanPoint(x: 1_024_512, y: 1_044_992))
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertLessThan(data.count, 1_000)
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
    }

    func testMalformedMapsAreRefused() throws {
        let world = try makeWorld()
        func load(_ map: String) -> GameWorld? {
            try? JSONDecoder().decode(GameWorld.self, from: Data(Self.replacingMap(of: world, with: map).utf8))
        }
        XCTAssertEqual(load(#"{"width":16,"height":8,"occupied":[]}"#), world)
        XCTAssertEqual(load(try Self.denseMap(of: world)), world)
        let empty = #"{"empty":{}}"#
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":1,"y":1,"tile":\#(empty)}]}"#), "an empty tile listed")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":16,"y":4,"tile":\#(empty)}]}"#), "off the map")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":7,"y":4}]}"#), "no tile")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[{"x":7,"y":4,"tile":{"lake":{}}}]}"#), "an unknown kind of tile")
        XCTAssertNil(load(#"{"width":16,"height":8,"tiles":[\#(empty)]}"#), "too few tiles")
        XCTAssertNil(load(#"{"width":16,"height":8}"#), "neither form")
        XCTAssertNil(load(#"{"width":16,"height":8,"occupied":[],"tiles":[]}"#), "both forms")
        XCTAssertNil(load(#"{"width":1025,"height":8,"occupied":[]}"#), "too wide")
        XCTAssertNil(load(#"{"width":0,"height":8,"occupied":[]}"#), "no size")
    }

    /// ARCHITECTURE decision 51: a save with anything of the grid in it,
    /// which only a save made by hand could hold (the app built nothing on
    /// the grid in any save it wrote, see `SaveFixtures/`), is refused with
    /// the reason, not loaded without it: grid track or a station on a tile
    /// in the map, a station on tiles, a train at a grid node or on a grid
    /// link, with a body or a path on the grid, or holding grid track. A
    /// path that is `[]`, as every save writes it, still loads.
    func testHandMadeSavesWithGridContentAreRefusedWithTheReason() throws {
        var world = try makeWorld()
        let train = try world.purchaseTrain(named: "T1").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 2_048))
        let saved = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        func refusal(_ change: (inout [String: Any]) -> Void) -> String? {
            var object = saved
            change(&object)
            do {
                let data = try JSONSerialization.data(withJSONObject: object)
                _ = try JSONDecoder().decode(GameWorld.self, from: data)
                return nil
            } catch {
                return "\(error)"
            }
        }
        func changingTrain(_ key: String, to value: Any) -> (inout [String: Any]) -> Void {
            { object in
                var trains = object["trains"] as! [[String: Any]]
                trains[0][key] = value
                object["trains"] = trains
            }
        }
        func changingStation(_ change: @escaping (inout [String: Any]) -> Void) -> (inout [String: Any]) -> Void {
            { object in
                var stations = object["stations"] as! [[String: Any]]
                change(&stations[1])
                object["stations"] = stations
            }
        }
        let tile: [String: Any] = ["x": 1, "y": 1]
        var movement = (saved["trains"] as! [[String: Any]])[0]["movement"] as? [String: Any] ?? ["rate": 0, "cursor": 0]
        movement["continuation"] = [tile]
        let changes: [(String, (inout [String: Any]) -> Void)] = [
            ("grid track on the map", { $0["map"] = ["width": 16, "height": 8, "occupied": [["x": 1, "y": 1, "tile": ["track": ["connections": 10]]]]] }),
            ("a station on a tile of the map", { $0["map"] = ["width": 16, "height": 8, "occupied": [["x": 7, "y": 4, "tile": ["station": ["id": 2]]]]] }),
            ("a turnout in the old form of the map", { object in
                let tiles = (0..<(16 * 8)).map { $0 == 9 ? ["turnout": ["connections": 11, "stem": 1]] : ["empty": [String: Any]()] }
                object["map"] = ["width": 16, "height": 8, "tiles": tiles]
            }),
            ("a station on tiles", changingStation { $0["position"] = ["x": 7, "y": 4]; $0["point"] = nil }),
            ("a station grown onto tiles", changingStation { $0["annexes"] = [tile] }),
            ("a train at a grid node", changingTrain("position", to: ["atNode": ["tile": tile, "heading": "east"]])),
            ("a train on a grid link", changingTrain("position", to: ["onLink": ["from": tile, "to": ["x": 2, "y": 1], "offset": 512]])),
            ("a train with a body on the grid", changingTrain("trail", to: [tile])),
            ("a train with a path on the grid", changingTrain("movement", to: movement)),
            ("a train holding a grid tile", changingTrain("reservation", to: [["tile": tile]])),
            ("a train holding a grid link", changingTrain("reservation", to: [["link": [tile, ["x": 2, "y": 1]]]])),
        ]
        for (what, change) in changes {
            let reason = refusal(change)
            XCTAssertNotNil(reason, "\(what) loaded")
            XCTAssertTrue(reason?.contains("the grid was removed in Stage F3c") == true, "\(what): \(reason ?? "loaded")")
        }
        XCTAssertNil(refusal { _ in }, "the save as written loads")
        XCTAssertNil(refusal(changingTrain("trail", to: [Any]())), "an empty body on the grid is no body")
    }

    /// `world`'s JSON with its map replaced by `map`.
    private static func replacingMap(of world: GameWorld, with map: String) throws -> String {
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        object["map"] = try JSONSerialization.jsonObject(with: Data(map.utf8))
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// `world`'s map with every tile written out, as saves of version 1
    /// wrote it: every tile empty ground.
    private static func denseMap(of world: GameWorld) throws -> String {
        let tiles = Array(repeating: #"{"empty":{}}"#, count: world.map.width * world.map.height)
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

    /// The version 3 save (decision 49): the demo map after 90 minutes,
    /// with the Ring Line round Central on two tracks, a train each way,
    /// both sent out since it opened.
    func testTheVersionThreeSaveReadsAsItWasWritten() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v3-demo-90-minutes.json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 3)
        let lines = try XCTUnwrap((object["world"] as? [String: Any])?["lines"] as? [[String: Any]])
        XCTAssertEqual(lines.map { $0["ring"] as? Bool }, [nil, nil, true])

        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world.clock.now, GameTime(minutes: 90))
        XCTAssertEqual(world.stations.map(\.name), ["West", "Central", "East", "North", "South"])
        XCTAssertEqual(world.network.edges.count, 10)
        XCTAssertEqual(world.lines.map(\.name), ["Line 1", "Line 2", "Ring Line"])
        XCTAssertEqual(world.lines.map(\.isRing), [false, false, true])
        XCTAssertEqual(world.trains.map(\.name), ["Train 1", "Train 2", "Ring Train 1", "Ring Train 2"])
        let ring = world.lines[2]
        XCTAssertEqual(ring.trains.map { ring.ringDirection(of: $0) }, [.inner, .outer])
        XCTAssertNotNil(ring.lastDispatch)
        XCTAssertNotNil(ring.outerLastDispatch)
        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertEqual(world.accounts.mode, .management)
    }

    /// The version 4 save (Stage E2): the same demo map after 90 minutes,
    /// laid over the Earth with its middle at Taipei Main Station.
    func testTheVersionFourSaveReadsAsItWasWritten() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v4-real-world-demo-90-minutes.json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 4)
        let anchor = try XCTUnwrap((object["world"] as? [String: Any])?["geoAnchor"] as? [String: Int64])
        XCTAssertEqual(anchor, ["latitude": 250_479_308, "longitude": 1_215_170_046])

        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world.geoAnchor, GeoAnchor(latitude: 250_479_308, longitude: 1_215_170_046))
        XCTAssertEqual(world.clock.now, GameTime(minutes: 90))
        XCTAssertEqual(world.map.width, 1_024)
        XCTAssertEqual(world.stations.map(\.name), ["West", "Central", "East", "North", "South"])
        XCTAssertEqual(world.lines.map(\.name), ["Line 1", "Line 2", "Ring Line"])
        XCTAssertEqual(world.lines.map(\.isRing), [false, false, true])
        XCTAssertEqual(world.economy.balance, Money(69_962_900))

        // The anchor is the only difference from the version 3 save.
        let three = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("v3-demo-90-minutes.json"))).world
        var blank = world
        blank.setGeoAnchor(nil)
        XCTAssertEqual(blank, three)
    }

    /// `SaveFixtures/` at the repository root, found from this source file.
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures", isDirectory: true)
}
