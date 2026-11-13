import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 726: Hong Kong's map has its own ground, the Lands
/// Department's terrain model, and its own water, OpenStreetMap's sea,
/// rivers and reservoirs, in its map pack (`heights.dat`, `water.json`,
/// `tools/hk-map/build_hk_ground_grids.py`).
@MainActor
final class HongKongGroundTests: XCTestCase {
    private func ground() throws -> (heights: HeightGrid, water: WaterGrid) {
        let ground = try HongKongMapTests.ground()
        return (try XCTUnwrap(ground.heights), try XCTUnwrap(ground.water))
    }

    /// The highest of the ground within some 160 m of a place, every 27 m.
    private func top(_ heights: HeightGrid, _ latitude: Double, _ longitude: Double) -> Double {
        var best = -Double.infinity
        for row in -6...6 {
            for column in -6...6 {
                best = max(best, heights.height(latitude: latitude + Double(row) * 0.00025, longitude: longitude + Double(column) * 0.00025))
            }
        }
        return best
    }

    /// The hills stand where they are, as high as they are: Tai Mo Shan
    /// 957 m, Victoria Peak 552 m, Lion Rock 495 m (each cell is the mean
    /// of its 58 m, so a sharp top is a little lower).
    func testTheHillsStandWhereTheyAre() throws {
        let heights = try ground().heights
        for (name, latitude, longitude, metres) in [
            ("Tai Mo Shan", 22.41056, 114.12444, 957.0), ("Victoria Peak", 22.2759, 114.1455, 552.0), ("Lion Rock", 22.3523, 114.1870, 495.0),
        ] {
            XCTAssertEqual(top(heights, latitude, longitude), metres, accuracy: 30, name)
        }
    }

    /// The harbours are water, the sea at 0 m; the land the city reclaimed
    /// from them is low; Shenzhen across the border is land, not sea.
    func testTheSeaIsWaterAndTheShoreIsLow() throws {
        let (heights, water) = try ground()
        for (name, latitude, longitude) in [("Victoria Harbour", 22.2880, 114.1720), ("Tolo Harbour", 22.4400, 114.2200)] {
            XCTAssertTrue(water.isWater(latitude: latitude, longitude: longitude), name)
        }
        XCTAssertEqual(heights.height(latitude: 22.2880, longitude: 114.1720), 0, "the middle of Victoria Harbour")
        for (name, latitude, longitude) in [("Central", 22.2833, 114.1580), ("Kowloon Station", 22.3049, 114.1615), ("Tsim Sha Tsui", 22.2960, 114.1720)] {
            XCTAssertFalse(water.isWater(latitude: latitude, longitude: longitude), name)
            XCTAssertTrue((0...15).contains(heights.height(latitude: latitude, longitude: longitude)), name)
        }
        XCTAssertFalse(water.isWater(latitude: 22.54, longitude: 114.05), "Shenzhen")
        XCTAssertTrue(water.hasLand(nearLatitude: 22.2880, longitude: 114.1720, within: 1_000), "the harbour's shores")
    }

    /// The rules see the sea: a station built by the harbour reads its
    /// land in with the water round it, and no one lives on the water.
    func testTheRulesSeeTheSea() throws {
        let ground = try HongKongMapTests.ground()
        let session = GameSession(world: .newOverseasGame(ground, balance: Money(100_000_000_000)), language: .english)
        session.population = ground.population
        session.water = ground.water
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let position = frame.worldPosition(latitude: 22.2960, longitude: 114.1720)
        let tsimShaTsui = PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
        try session.performEdit { world throws(GameError) in _ = try world.buildStation(named: "Tsim Sha Tsui", at: tsimShaTsui) }
        XCTAssertGreaterThan(session.world.terrain.waterCellCount, 1_000, "Victoria Harbour")
        XCTAssertFalse(session.world.land.cells.isEmpty)
        XCTAssertFalse(session.world.land.cells.contains { session.world.isWater(row: $0.row, column: $0.column) })
    }

    /// The pack lists the files, where they come from and under what
    /// licence; the hill shading is in it for the flat map.
    func testThePackListsItsGround() throws {
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.hongKong))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: pack.file("pack", "json")) as? [String: Any])
        let files = try XCTUnwrap(manifest["files"] as? [String: Any])
        for name in ["heights.dat", "water.json", "terrain.pmtiles"] {
            let entry = try XCTUnwrap(files[name] as? [String: Any], name)
            let size = try Data(contentsOf: pack.root.appendingPathComponent(name)).count
            XCTAssertEqual(entry["bytes"] as? Int, size, name)
            XCTAssertLessThan(size, 1_000_000, name)
        }
        let licences = try XCTUnwrap(manifest["licences"] as? [String: String])
        XCTAssertNotNil(licences["Lands Department DTM"])
        XCTAssertNotNil(pack.terrainFile)
    }
}
