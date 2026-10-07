import Foundation
import GameCore
import XCTest

/// Stage C4: the versioned save. Version 1 is the world's `Codable` form;
/// version 2 (Stage E1) writes only the map's occupied tiles; version 3
/// (decision 49) can hold ring lines; version 4 (Stage E2) a real-world
/// map's anchor; version 5 (Stage F2) the spacing exemptions; version 6
/// (Stage F3d) the world's bounds in world units instead of a map of tiles.
/// Unknown versions are refused, and every committed save in
/// `SaveFixtures/` keeps loading (see its README).
final class SavedGameTests: XCTestCase {
    private static func currentVersion(of data: Data) -> Data {
        var text = String(decoding: data, as: UTF8.self)
        for version in 8..<SavedGame.currentVersion {
            text = text.replacingOccurrences(of: #""saveVersion" : \#(version),"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#)
        }
        return Data(text.utf8)
    }

    private func makeWorld() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
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
        XCTAssertEqual(object["saveVersion"] as? Int, SavedGame.currentVersion)
        XCTAssertEqual(SavedGame.currentVersion, 12)
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
        XCTAssertNoThrow(try decode(#"{"saveVersion": 5, "world": \#(world)}"#))
        XCTAssertNoThrow(try decode(#"{"saveVersion": 6, "world": \#(world)}"#))
        XCTAssertNoThrow(try decode(#"{"saveVersion": 7, "world": \#(world)}"#))
        XCTAssertNoThrow(try decode(#"{"saveVersion": 8, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": 13, "world": \#(world)}"#), "a later version is not guessed at")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 0, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": -1, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": "1", "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"world": \#(world)}"#), "no version")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 1}"#), "no world")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 1, "world": {}}"#), "GameCore refuses the world")
    }

    /// Version 6 (Stage F3d): the world is saved as its bounds in world
    /// units, with no map of tiles, and a train's movement no longer writes
    /// the grid's empty path. The forms before it, the map as its occupied
    /// tiles (version 2) and with every tile written out (version 1), still
    /// read into the same world, at 1024 units a tile.
    func testTheWorldIsSavedAsItsBoundsInWorldUnits() throws {
        var world = try makeWorld()
        let train = try world.purchaseTrain(named: "T1").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 2_048))
        try world.setTrainMovementRate(train, to: 64)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertNil(object["map"])
        let bounds = try XCTUnwrap(object["bounds"] as? [String: Any])
        XCTAssertEqual(bounds as? [String: Int], ["width": 16_384, "height": 8_192])
        let movement = try XCTUnwrap((object["trains"] as? [[String: Any]])?.first?["movement"] as? [String: Any])
        XCTAssertNil(movement["continuation"], "the grid's path is no longer written")
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(Self.replacingMap(of: world, with: Self.denseMap(of: world)).utf8)), world)
        XCTAssertEqual(
            try JSONDecoder().decode(GameWorld.self, from: Data(Self.replacingMap(of: world, with: #"{"width":16,"height":8,"occupied":[]}"#).utf8)),
            world
        )
    }

    /// Stage F3d's step from version 5: a world's map of `w × h` tiles is
    /// read as bounds `1024w × 1024h` units, whatever version says so, and
    /// a movement's empty `"continuation"` is read and dropped. A node or a
    /// station the map would not have held is refused as before.
    func testAMapOfTilesMigratesToBoundsAtTheTilesWidth() throws {
        let world = try makeWorld()
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        object["bounds"] = nil
        func load(width: Int, height: Int, version: Int = 5) throws -> GameWorld {
            var old = object
            old["map"] = ["width": width, "height": height, "occupied": [Any]()]
            let save = try JSONSerialization.data(withJSONObject: ["saveVersion": version, "world": old])
            return try JSONDecoder().decode(SavedGame.self, from: save).world
        }
        for version in 1...7 {
            XCTAssertEqual(try load(width: 16, height: 8, version: version), world, "version \(version)")
        }
        XCTAssertEqual(try load(width: 1_024, height: 1_024).bounds, .maximum)
        XCTAssertEqual(try load(width: 1_024, height: 9).bounds, try WorldBounds(width: 1_048_576, height: 9_216))
        XCTAssertEqual(try load(width: 10, height: 5).bounds, try WorldBounds(width: 10_240, height: 5_120), "the last node, at x 9216, and East, at y 4608, inside")
        // The line's last node, at x 9216, lies outside a map 9 tiles wide,
        // and East's point, at y 4608, outside one 4 tiles high.
        XCTAssertThrowsError(try load(width: 9, height: 5))
        XCTAssertThrowsError(try load(width: 10, height: 4))
        XCTAssertThrowsError(try load(width: 1_025, height: 8), "a map larger than any build wrote")

        // A save of the migrated world, in the current version, writes its
        // bounds.
        let migrated = try load(width: 16, height: 8)
        let saved = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: migrated))) as? [String: Any])
        XCTAssertEqual(saved["saveVersion"] as? Int, SavedGame.currentVersion)
        let savedWorld = try XCTUnwrap(saved["world"] as? [String: Any])
        XCTAssertNil(savedWorld["map"])
        XCTAssertEqual(savedWorld["bounds"] as? [String: Int], ["width": 16_384, "height": 8_192])
    }

    /// A world gives its bounds or its legacy map, exactly one of them.
    func testAWorldNeedsItsBoundsOrItsMapButNotBoth() throws {
        let world = try makeWorld()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        func load(_ change: (inout [String: Any]) -> Void) -> GameWorld? {
            var changed = object
            change(&changed)
            return try? JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: changed))
        }
        XCTAssertEqual(load { _ in }, world)
        XCTAssertNil(load { $0["bounds"] = nil }, "neither")
        XCTAssertNil(load { $0["map"] = ["width": 16, "height": 8, "occupied": [Any]()] }, "both")
        XCTAssertNil(load { $0["bounds"] = ["width": 16_384, "height": 0] }, "no height")
        XCTAssertNil(load { $0["bounds"] = ["width": 1_048_577, "height": 8_192] }, "too wide")
        XCTAssertNil(load { $0["bounds"] = ["width": 9_215, "height": 8_192] }, "the line's last node, at x 9216, outside")
        XCTAssertEqual(load { $0["bounds"] = ["width": 9_217, "height": 4_609] }?.bounds, try WorldBounds(width: 9_217, height: 4_609), "a unit beyond the last node and East")
    }

    /// A new game's 16 km map (Stage E1) saves in a few hundred bytes: the
    /// map that wrote every tile made it 13 MB.
    func testALargeMapSavesOnlyWhatStandsOnIt() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 1_048_576, height: 1_048_576), economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try world.buildStation(named: "Far", at: PlanPoint(x: 1_024_512, y: 1_044_992))
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertLessThan(data.count, 1_000)
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
    }

    func testMalformedLegacyMapsAreRefused() throws {
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
            ("grid track on the map", { $0["bounds"] = nil; $0["map"] = ["width": 16, "height": 8, "occupied": [["x": 1, "y": 1, "tile": ["track": ["connections": 10]]]]] }),
            ("a station on a tile of the map", { $0["bounds"] = nil; $0["map"] = ["width": 16, "height": 8, "occupied": [["x": 7, "y": 4, "tile": ["station": ["id": 2]]]]] }),
            ("a turnout in the old form of the map", { object in
                let tiles = (0..<(16 * 8)).map { $0 == 9 ? ["turnout": ["connections": 11, "stem": 1]] : ["empty": [String: Any]()] }
                object["bounds"] = nil
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
        movement["continuation"] = [Any]()
        XCTAssertNil(refusal(changingTrain("movement", to: movement)), "an empty path on the grid, as saves before version 6 wrote it")
    }

    /// `world`'s JSON with its bounds replaced by the legacy `map`.
    private static func replacingMap(of world: GameWorld, with map: String) throws -> String {
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        object["bounds"] = nil
        object["map"] = try JSONSerialization.jsonObject(with: Data(map.utf8))
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// `world`'s bounds as a map of 1024-unit tiles with every tile written
    /// out, as saves of version 1 wrote it: every tile empty ground.
    private static func denseMap(of world: GameWorld) throws -> String {
        let (width, height) = (Int(world.bounds.width / 1_024), Int(world.bounds.height / 1_024))
        let tiles = Array(repeating: #"{"empty":{}}"#, count: width * height)
        return #"{"width":\#(width),"height":\#(height),"tiles":[\#(tiles.joined(separator: ","))]}"#
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
        XCTAssertEqual(world.bounds, .maximum, "1024 tiles of 1024 units a side")
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
        XCTAssertEqual(world.bounds, .maximum)
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

    /// A version 4 save with a siding 192 (3 m) beside Line 1 (Stage F2,
    /// ARCHITECTURE decision 52): the version 4 build allowed it. It loads
    /// with that pair exempt, and saving it again gives the version 6 save
    /// byte for byte (the version 5 build gave the version 5 save).
    func testTheVersionFourSidingSaveKeepsItsSiding() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v4-demo-siding-90-minutes.json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 4)
        let network = try XCTUnwrap((object["world"] as? [String: Any])?["network"] as? [String: Any])
        XCTAssertNil(network["spacingExemptions"])

        let game = try JSONDecoder().decode(SavedGame.self, from: data)
        let world = game.world
        XCTAssertEqual(world.clock.now, GameTime(minutes: 90))
        XCTAssertEqual(world.network.edges.count, 11)
        let siding = try XCTUnwrap(world.network.edge(.edge(11)))
        XCTAssertEqual(world.network.node(siding.from)?.position, WorldCoordinate(x: 526_336, y: 524_096, z: 0))
        XCTAssertEqual(world.network.node(siding.to)?.position, WorldCoordinate(x: 529_408, y: 524_096, z: 0))
        XCTAssertEqual(world.network.spacingExemptions, [TrackEdgePair(.edge(1), .edge(11))])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let eight = try Data(contentsOf: Self.fixtures.appendingPathComponent("v8-demo-siding-90-minutes.json"))
        XCTAssertEqual(try encoder.encode(game), Self.currentVersion(of: eight))
    }

    /// The version 5 save (Stage F2): the same game, listing the siding and
    /// Line 1 as built too close before the rule.
    func testTheVersionFiveSaveReadsAsItWasWritten() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v5-demo-siding-90-minutes.json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 5)
        let network = try XCTUnwrap((object["world"] as? [String: Any])?["network"] as? [String: Any])
        XCTAssertEqual(network["spacingExemptions"] as? [[Int]], [[1, 11]])

        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        let four = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("v4-demo-siding-90-minutes.json"))).world
        XCTAssertEqual(world, four)
        XCTAssertEqual(world.lines.map(\.name), ["Line 1", "Line 2", "Ring Line"])
    }

    /// The version 6 save (Stage F3d): the version 5 save read by the
    /// Stage F3d build and saved again. Its world is `"bounds"` of 2^20
    /// units a side, the version 5 map of 1024 tiles; it has no `"map"`, and
    /// no movement writes `"continuation"`. It is the same world, and saving
    /// it again gives it byte for byte.
    func testTheVersionSixSaveReadsAsItWasWritten() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v6-demo-siding-90-minutes.json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 6)
        let saved = try XCTUnwrap(object["world"] as? [String: Any])
        XCTAssertNil(saved["map"])
        XCTAssertEqual(saved["bounds"] as? [String: Int], ["width": 1_048_576, "height": 1_048_576])
        let movements = try XCTUnwrap(saved["trains"] as? [[String: Any]]).compactMap { $0["movement"] as? [String: Any] }
        XCTAssertFalse(movements.isEmpty)
        XCTAssertTrue(movements.allSatisfy { $0["continuation"] == nil })

        let game = try JSONDecoder().decode(SavedGame.self, from: data)
        let five = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("v5-demo-siding-90-minutes.json"))).world
        XCTAssertEqual(game.world, five)
        XCTAssertEqual(game.world.bounds, .maximum)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let eight = try Data(contentsOf: Self.fixtures.appendingPathComponent("v8-demo-siding-90-minutes.json"))
        XCTAssertEqual(try encoder.encode(game), Self.currentVersion(of: eight), "saved again by a later build, the current version")
    }

    /// The version 7 save (Stage U2): the version 6 save read by the
    /// Stage U2 build and saved again: only its version differs, as no train
    /// in it follows another. Saving it again gives the version 8 save.
    func testTheVersionSevenSaveReadsAsItWasWritten() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v7-demo-siding-90-minutes.json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 7)
        let six = try Data(contentsOf: Self.fixtures.appendingPathComponent("v6-demo-siding-90-minutes.json"))
        let sixText = String(decoding: six, as: UTF8.self)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), sixText.replacingOccurrences(of: #""saveVersion" : 6"#, with: #""saveVersion" : 7"#))

        let game = try JSONDecoder().decode(SavedGame.self, from: data)
        XCTAssertEqual(game.world, try JSONDecoder().decode(SavedGame.self, from: six).world)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let eight = try Data(contentsOf: Self.fixtures.appendingPathComponent("v8-demo-siding-90-minutes.json"))
        XCTAssertEqual(try encoder.encode(game), Self.currentVersion(of: eight), "saved again by a later build, the current version")
    }

    /// The version 8 save (Stage V2): the version 7 save read by the
    /// Stage V2 build and saved again: only its version differs, as no
    /// service in it stands aside at a passing place. Saving it again gives
    /// it byte for byte.
    func testTheVersionEightSaveReadsAsItWasWritten() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v8-demo-siding-90-minutes.json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 8)
        let seven = try Data(contentsOf: Self.fixtures.appendingPathComponent("v7-demo-siding-90-minutes.json"))
        let sevenText = String(decoding: seven, as: UTF8.self)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), sevenText.replacingOccurrences(of: #""saveVersion" : 7"#, with: #""saveVersion" : 8"#))

        let game = try JSONDecoder().decode(SavedGame.self, from: data)
        XCTAssertEqual(game.world, try JSONDecoder().decode(SavedGame.self, from: seven).world)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        XCTAssertEqual(try encoder.encode(game), Self.currentVersion(of: data))
    }

    func testVersionNineKeepsActualVisitsAndResumesAtTheExactClearanceSecond() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for name in ["v9-scheduled-meet.json", "v9-scheduled-clearance.json"] {
            let data = try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
            let game = try JSONDecoder().decode(SavedGame.self, from: data)
            XCTAssertEqual(try encoder.encode(game), Self.currentVersion(of: data))
            XCTAssertNotNil(game.world.scheduledTrafficWait(of: TrainID(rawValue: 1)))
            var world = game.world
            if name.contains("clearance") {
                XCTAssertEqual(world.trains[1].trafficVisits.first?.departure, GameTime(seconds: 388))
                try world.advance(ticks: 270)
                XCTAssertNotNil(world.scheduledTrafficWait(of: TrainID(rawValue: 1)))
                try world.advance(ticks: 10)
                XCTAssertNil(world.scheduledTrafficWait(of: TrainID(rawValue: 1)))
            } else {
                try world.advance(ticks: 12_000)
                XCTAssertTrue(world.trains.allSatisfy { $0.execution == nil })
            }
        }
    }

    func testVersionEightMigratesWithoutInventingActualVisits() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v8-demo-siding-90-minutes.json"))
        let game = try JSONDecoder().decode(SavedGame.self, from: data)
        XCTAssertTrue(game.world.trains.allSatisfy { $0.trafficVisits.isEmpty })
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, SavedGame.currentVersion)
    }

    func testCorruptActualTrafficVisitsAreRefused() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v9-scheduled-clearance.json"))
        let original = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        func altered(_ visits: Any) throws -> Data {
            var object = original
            var world = object["world"] as! [String: Any]
            var trains = world["trains"] as! [[String: Any]]
            trains[1]["trafficVisits"] = visits
            world["trains"] = trains; object["world"] = world
            return try JSONSerialization.data(withJSONObject: object)
        }
        let trains = (original["world"] as! [String: Any])["trains"] as! [[String: Any]]
        let visit = (trains[1]["trafficVisits"] as! [[String: Any]])[0]
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: altered(NSNull())))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: altered([visit, visit])))
        for (key, value) in [("stop", -1), ("cycle", -1), ("station", 99), ("departure", 387), ("arrival", 391)] {
            var bad = visit; bad[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: altered([bad])), key)
        }
    }

    /// `SaveFixtures/` at the repository root, found from this source file.
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures", isDirectory: true)
    func testVersionTenPreservesItsSharedPhysicalPreferences() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v10-line-route-preferences.json"))
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        let route = try XCTUnwrap(world.lines[0].routePreferences.first)
        XCTAssertEqual(route.tracks.map(\.edge), [1, 4, 5].map(TrackEdgeID.edge))
        XCTAssertEqual(route.platform.edge, .edge(5))
        XCTAssertFalse(world.isTrafficControlEnabled)
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world, world)
        try world.advance(ticks: 610)
        XCTAssertEqual(world.trains[0].movement.remainingEdges.first, .edge(4))
    }

    /// Station operation modes (Phase 5F) need no new save version: a
    /// station is written with `"operationMode"` only when it is not open,
    /// and one written without it is open, so every earlier save reads as
    /// before and a version 11 save keeps a closed station.
    func testAVersionElevenSaveKeepsAClosedStation() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v11-network-transfer.json"))
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertTrue(world.stations.allSatisfy { $0.operationMode == .normalFlow })
        try world.setStationOperationMode(StationID(rawValue: 3), to: .closed)
        try world.setStationOperationMode(StationID(rawValue: 1), to: .flowControl)
        let saved = try JSONEncoder().encode(SavedGame(world: world))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, SavedGame.currentVersion)
        let stations = try XCTUnwrap((object["world"] as? [String: Any])?["stations"] as? [[String: Any]])
        XCTAssertEqual(stations.map { $0["operationMode"] as? String }, ["flowControl", nil, "closed"])
        let loaded = try JSONDecoder().decode(SavedGame.self, from: saved).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.station(id: StationID(rawValue: 3))?.operationMode, .closed)
        // Open again, the save is written as before.
        try world.setStationOperationMode(StationID(rawValue: 3), to: .normalFlow)
        try world.setStationOperationMode(StationID(rawValue: 1), to: .normalFlow)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(SavedGame(world: world)), as: UTF8.self).contains("operationMode"))
    }

    func testVersionElevenPreservesAWaitingTransferAndOlderSavesStayDirect() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v11-network-transfer.json"))
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world.passengerRoutingMode, .network)
        let transfer = try XCTUnwrap(world.waitingPassengers(at: StationID(rawValue: 2)).first)
        XCTAssertEqual(transfer.journey?.origin, StationID(rawValue: 1))
        XCTAssertEqual(transfer.journey?.current, 1)
        XCTAssertEqual(world.passengerLedger(of: StationID(rawValue: 1)).waiting, 5)
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self,
            from: JSONEncoder().encode(SavedGame(world: world))).world, world)
        try world.advance(ticks: 15)
        XCTAssertGreaterThanOrEqual(world.passengerLedger(of: StationID(rawValue: 1)).arrived, 5)

        let older = try Data(contentsOf: Self.fixtures.appendingPathComponent("v10-line-route-preferences.json"))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: older).world.passengerRoutingMode, .direct)
    }

    /// Version 12 (Phase 6a, ARCHITECTURE decision 72): the world's land.
    /// The save holds a town round the middle of a world 32 × 24 cells (the
    /// first town of seed 1 as Phase 6a first drew it, at half the density
    /// 6b settled on), keeps it byte for byte when saved again, and runs on;
    /// older saves have no land.
    func testVersionTwelveKeepsItsLand() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v12-land-towns.json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 12)
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world.land.cells.count, 437)
        XCTAssertEqual(world.land.totals, LandTotals(residents: 24_984, jobs: 16_614))
        XCTAssertFalse(world.landDemand, "the stations keep their own ridership")
        XCTAssertEqual(world.landCatchment(of: StationID(rawValue: 2)), LandTotals(residents: 24_984, jobs: 16_614))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Self.currentVersion(of: data))
        let land = world.land
        try world.advance(ticks: 60)
        XCTAssertEqual(world.land, land, "without demand from land, nothing changes it")

        let older = try Data(contentsOf: Self.fixtures.appendingPathComponent("v11-network-transfer.json"))
        XCTAssertTrue(try JSONDecoder().decode(SavedGame.self, from: older).world.land.isEmpty)
    }

    /// Version 12 with demand from land (Phase 6b, ARCHITECTURE decision
    /// 73): a served line through a town after two days and ten hours. The
    /// land has grown (four new cells) and set the stations' ridership; the
    /// save keeps it byte for byte, and the land goes on growing.
    func testVersionTwelveKeepsDemandFromLand() throws {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("v12-land-demand.json"))
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertTrue(world.landDemand)
        XCTAssertEqual(world.land.cells.count, 441)
        XCTAssertEqual(world.land.totals, LandTotals(residents: 51_256, jobs: 33_979))
        for station in world.stations {
            XCTAssertEqual(world.stationDemand(of: station.id), LandDemand.shares(of: world.land, among: world.stations)[station.id]?.demand)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), data)
        try world.advance(ticks: 1_440)
        XCTAssertGreaterThan(world.land.totals.residents, 51_256)
    }

}
