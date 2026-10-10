import Foundation
@testable import GameCore
import XCTest

/// Real coverage (ARCHITECTURE decision 147): a cell of land can know how
/// much of it real buildings cover. Its city building is bought out by that
/// ground rather than by its density's square: a cell real buildings leave
/// empty costs nothing, a dense one a lot. The land keeps and saves it.
final class RealCoverageTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// An office on the line between cells (5, 5) and (5, 6): an eighth of
    /// each.
    private static let betweenTheHomes = PlanPoint(x: 24_576, y: 22_528)

    /// A managed world with no stations, D1 homes of 48 residents and 8
    /// jobs on cells (5, 5) and (5, 6), covered `west` and `east` percent,
    /// the city's buildings and footprints and buying out by area on.
    private func world(west: Int64?, east: Int64?) throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .paused))
        try world.setLand([
            LandCell(row: 5, column: 5, use: .residential, residents: 48, jobs: 8, coverage: west),
            LandCell(row: 5, column: 6, use: .residential, residents: 48, jobs: 8, coverage: east),
        ])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setCityFootprints(true)
        world.setAreaBuyOut(true)
        return world
    }

    /// A known coverage sets the city building's ground and floor; an
    /// unknown one keeps its density's square (decisions 95 and 142).
    func testABuyOutStandsOnTheRealGround() throws {
        let world = try world(west: 0, east: 50)
        let empty = try XCTUnwrap(world.land.cell(row: 5, column: 5))
        let half = try XCTUnwrap(world.land.cell(row: 5, column: 6))
        XCTAssertEqual(world.buyOutPrice(of: empty), .zero, "nothing stands there")
        // Half of 4,096 m², two storeys of it at $40, and its land at 2,000
        // a m², a fifth more.
        XCTAssertEqual(world.buyOutPrice(of: half), Money((2 * 2_048 * 4_000 + 2_048 * 2_000) * 120 / 100))
        let unknown = try self.world(west: nil, east: nil)
        XCTAssertEqual(unknown.buyOutPrice(of: try XCTUnwrap(unknown.land.cell(row: 5, column: 5))), 15_705_600)
        // A full cell: 4,096 m² of ground.
        var full = try self.world(west: 100, east: nil)
        full.setCityBuildings(false)
        XCTAssertEqual(full.buyOutPrice(of: try XCTUnwrap(full.land.cell(row: 5, column: 5))),
                       Money((2 * 4_096 * 4_000 + 4_096 * 2_000) * 120 / 100))
    }

    func testAShareOfACarParkCostsNothingAndOfADenseCellALot() throws {
        let world = try world(west: 0, east: 50)
        let quote = try XCTUnwrap(world.placedBuildingQuote(.office, at: Self.betweenTheHomes))
        XCTAssertEqual(quote.buyOut, Money(24_576_000 / 8))
        XCTAssertEqual(quote.cleared, [])
    }

    /// The land keeps a cell's coverage as its people move and grow.
    func testACellKeepsItsCoverageAsItsPeopleChange() throws {
        var world = try world(west: 0, east: 50)
        _ = try world.placeBuilding(.office, at: Self.betweenTheHomes)
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.coverage, 0)
        XCTAssertEqual(world.land.cell(row: 5, column: 6)?.coverage, 50)
        XCTAssertEqual(world.land.cell(row: 5, column: 6)?.residents, 42)
        let cell = try XCTUnwrap(world.land.cell(row: 5, column: 6))
        XCTAssertEqual(cell.with(residents: 1, jobs: 2), LandCell(row: 5, column: 6, use: .residential, residents: 1, jobs: 2, coverage: 50))
        XCTAssertEqual(cell.with(use: .office, residents: 1, jobs: 2).coverage, 50)
    }

    func testACoverageOutOfRangeIsRefused() throws {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 0, costs: testCosts), clock: GameClock(speed: .paused))
        XCTAssertThrowsError(try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 4, jobs: 0, coverage: 101)]))
        XCTAssertThrowsError(try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 4, jobs: 0, coverage: -1)]))
        XCTAssertNoThrow(try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 4, jobs: 0, coverage: 100)]))
    }

    /// A run of land with known coverage writes `"coverage"`, one a cell;
    /// a cell with none starts a run of its own; land with none writes
    /// none, as before.
    func testTheLandSavesItsCoverageInItsRuns() throws {
        var land = Land()
        land.insert(LandCell(row: 1, column: 1, use: .residential, residents: 4, jobs: 0, coverage: 20))
        land.insert(LandCell(row: 1, column: 2, use: .residential, residents: 5, jobs: 0, coverage: 30))
        land.insert(LandCell(row: 1, column: 3, use: .residential, residents: 6, jobs: 0))
        let data = try JSONEncoder().encode(land)
        let runs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0]["coverage"] as? [Int], [20, 30])
        XCTAssertNil(runs[1]["coverage"])
        XCTAssertEqual(try JSONDecoder().decode(Land.self, from: data), land)

        var none = Land()
        none.insert(LandCell(row: 1, column: 1, use: .residential, residents: 4, jobs: 0))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(none), as: UTF8.self).contains("coverage"))
        // A run whose coverage does not match its cells is refused.
        let bad = Data(#"[{"row": 1, "column": 1, "use": "residential", "residents": [4, 5], "coverage": [20]}]"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Land.self, from: bad))
    }

    /// Version 35 (decision 147): `world(west: 0, east: 50)` with the
    /// office between the homes, run ten minutes. It saves byte for byte
    /// and is the world this build makes.
    func testVersionThirtyFiveKeepsTheLandsCoverage() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v35-real-coverage.json")
        var made = try world(west: 0, east: 50)
        _ = try made.placeBuilding(.office, at: Self.betweenTheHomes)
        made.setSpeed(.normal)
        try made.advance(ticks: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["REAL_COVERAGE_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 35)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.land.cell(row: 5, column: 6)?.coverage, 50)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 35,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
