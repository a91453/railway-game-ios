import Foundation
import GameCore
import XCTest

/// Stage C4: the versioned save. Version 1 is the world's `Codable` form;
/// unknown versions are refused, and every committed save in
/// `SaveFixtures/` keeps loading (see its README).
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
        XCTAssertEqual(object["saveVersion"] as? Int, 1)
        XCTAssertEqual(SavedGame.currentVersion, 1)
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
        XCTAssertThrowsError(try decode(#"{"saveVersion": 2, "world": \#(world)}"#), "a later version is not guessed at")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 0, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": -1, "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"saveVersion": "1", "world": \#(world)}"#))
        XCTAssertThrowsError(try decode(#"{"world": \#(world)}"#), "no version")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 1}"#), "no world")
        XCTAssertThrowsError(try decode(#"{"saveVersion": 1, "world": {}}"#), "GameCore refuses the world")
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

    /// `SaveFixtures/` at the repository root, found from this source file.
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures", isDirectory: true)
}
