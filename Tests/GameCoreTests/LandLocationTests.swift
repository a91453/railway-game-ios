import Foundation
@testable import GameCore
import XCTest

/// Where land lies (decision 1025): a square's factor from the real-price
/// registry multiplies the base of its cells' land value; land without
/// one is worth what it was.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class LandLocationTests: XCTestCase {
    /// 32 × 24 cells: 8 × 6 squares.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)

    private func world(_ cells: [LandCell] = []) throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        try world.setLand(cells)
        world.setEconomyMode(.management)
        return world
    }

    func testANewWorldHasNoLocationsAndItsLandIsWorthWhatItWas() throws {
        let world = try world([LandCell(row: 1, column: 1, use: .residential, residents: 40, jobs: 0)])
        XCTAssertTrue(world.landLocations.isEmpty)
        // B 6,000 × D 1,000 ÷ 1,000 on a cell with no building.
        XCTAssertEqual(world.landValue(row: 1, column: 1)?.base, 6_000)
        // Empty land: 3,000.
        XCTAssertEqual(world.landValue(row: 10, column: 10)?.base, 3_000)
    }

    func testASquaresFactorMultipliesTheBaseOfEachOfItsCells() throws {
        var world = try world([
            LandCell(row: 1, column: 1, use: .residential, residents: 40, jobs: 0),
            LandCell(row: 5, column: 1, use: .commercial, residents: 0, jobs: 40),
        ])
        // Square (0, 0) holds cells 0–3; square (1, 0) cells 4–7.
        try world.setLandLocations([LandLocation(row: 0, column: 0, factor: 2_500), LandLocation(row: 1, column: 0, factor: 300)])
        XCTAssertEqual(world.landLocations.factor(row: 3, column: 3), 2_500)
        XCTAssertNil(world.landLocations.factor(row: 0, column: 4))
        // 6,000 × 2,500 ÷ 1,000 = 15,000.
        XCTAssertEqual(world.landValue(row: 1, column: 1)?.base, 15_000)
        XCTAssertEqual(world.landValue(row: 1, column: 1)?.value, 15_000)
        // Empty land in the same square: 3,000 × 2.5 = 7,500.
        XCTAssertEqual(world.landValue(row: 2, column: 2)?.base, 7_500)
        // A shop in the cheap square: 9,000 × 300 ÷ 1,000 = 2,700.
        XCTAssertEqual(world.landValue(row: 5, column: 1)?.base, 2_700)
        // Empty land there: 3,000 × 0.3 = 900, held up to the minimum 1,500.
        XCTAssertEqual(world.landValue(row: 6, column: 2)?.base, 900)
        XCTAssertEqual(world.landValue(row: 6, column: 2)?.value, 1_500)
        // A square without a factor is as it was.
        XCTAssertEqual(world.landValue(row: 1, column: 5)?.base, 3_000)
    }

    func testTheValueIsHeldToItsMaximum() throws {
        var world = try world([LandCell(row: 0, column: 0, use: .office, residents: 0, jobs: 40)])
        try world.setLandLocations([LandLocation(row: 0, column: 0, factor: 10_000)])
        // 10,500 × 10 = 105,000, under 150,000.
        XCTAssertEqual(world.landValue(row: 0, column: 0)?.value, 105_000)
        world.setCityBuildings(true)
        // A D1 building: 10,500 × 1,000 ÷ 1,000 × 10 = 105,000; its
        // existing stock is D4: 10,500 × 2 × 10 = 210,000, held to 150,000.
        let density = try XCTUnwrap(world.buildings.building(row: 0, column: 0)?.density)
        XCTAssertEqual(density, .d4)
        XCTAssertEqual(world.landValue(row: 0, column: 0)?.base, 210_000)
        XCTAssertEqual(world.landValue(row: 0, column: 0)?.value, 150_000)
    }

    func testASquareKeepsTheFactorItWasGiven() throws {
        var world = try world()
        try world.setLandLocations([LandLocation(row: 2, column: 3, factor: 1_800)])
        try world.setLandLocations([LandLocation(row: 2, column: 3, factor: 900), LandLocation(row: 2, column: 4, factor: 900)])
        XCTAssertEqual(world.landLocations.all, [LandLocation(row: 2, column: 3, factor: 1_800), LandLocation(row: 2, column: 4, factor: 900)])
    }

    func testLocationsOutsideTheWorldOrOutOfRangeAreRefusedChangingNothing() throws {
        var world = try world()
        let before = world
        for bad in [
            [LandLocation(row: 6, column: 0, factor: 1_000)],
            [LandLocation(row: 0, column: 8, factor: 1_000)],
            [LandLocation(row: -1, column: 0, factor: 1_000)],
            [LandLocation(row: 0, column: 0, factor: 99)],
            [LandLocation(row: 0, column: 0, factor: 10_001)],
            [LandLocation(row: 0, column: 0, factor: 1_000), LandLocation(row: 0, column: 1, factor: 1_000), LandLocation(row: 0, column: 0, factor: 2_000)],
        ] {
            XCTAssertThrowsError(try world.setLandLocations(bad)) { XCTAssertEqual($0 as? GameError, .invalidLand) }
            XCTAssertEqual(world, before)
        }
    }

    func testAZonedCellKeepsItsPlacesFactorUnderItsNewUse() throws {
        var world = try world()
        try world.setLandLocations([LandLocation(row: 0, column: 0, factor: 4_000)])
        XCTAssertEqual(world.landValue(row: 1, column: 1)?.base, 12_000, "empty: 3,000 × 4")
        _ = try world.setZone(.commercial, rows: 1...1, columns: 1...1)
        world.growLand(reached: [:])
        // Whatever the city puts there is worth its use's base times 4.
        if let cell = world.land.cell(row: 1, column: 1) {
            XCTAssertEqual(world.landValue(row: 1, column: 1)?.base, LandValueRules.base(of: cell.use) * 4)
        }
    }

    func testTheCompanysLandCountsItsNeighboursWhereTheyLie() throws {
        var world = try world()
        // The company's building at cell (5, 5)'s middle; its square (1, 1)
        // is cheap, the squares round it dear.
        try world.setLandLocations([
            LandLocation(row: 1, column: 1, factor: 500), LandLocation(row: 0, column: 1, factor: 3_000),
            LandLocation(row: 1, column: 0, factor: 3_000), LandLocation(row: 0, column: 0, factor: 3_000),
        ])
        let building = PlacedBuilding(id: PlacedBuildingID(rawValue: 1), kind: .shop, centre: PlanPoint(x: 5 * 4_096 + 2_048, y: 5 * 4_096 + 2_048))
        // Its own cell: 3,000 × 0.5 = 1,500. The eight round it (rows and
        // columns 4–6) all lie in square (1, 1): 1,500 each, no more.
        XCTAssertEqual(world.companyLandValue(of: building)?.base, 1_500)
        let corner = PlacedBuilding(id: PlacedBuildingID(rawValue: 1), kind: .shop, centre: PlanPoint(x: 4 * 4_096 + 2_048, y: 4 * 4_096 + 2_048))
        // At cell (4, 4): three of its eight neighbours ((3, 3), (3, 4),
        // (3, 5)) lie in square (0, 1) or (0, 0), two more ((4, 3), (5,
        // 3)) in (1, 0): five at 9,000, three at 1,500 → 49,500 ÷ 8 =
        // 6,187, the mean, above its own 1,500.
        XCTAssertEqual(world.companyLandValue(of: corner)?.base, 6_187)
    }

    func testLocationsAreSavedAsRunsAndReadBack() throws {
        var world = try world()
        try world.setLandLocations([
            LandLocation(row: 1, column: 2, factor: 1_200), LandLocation(row: 1, column: 3, factor: 1_300), LandLocation(row: 2, column: 0, factor: 700),
        ])
        let data = try JSONEncoder().encode(world)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let runs = try XCTUnwrap(object["landLocations"] as? [[String: Any]])
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0]["factors"] as? [Int], [1_200, 1_300])
        XCTAssertEqual(runs[0]["column"] as? Int, 2)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        let none = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try self.world())) as? [String: Any]
        XCTAssertNil(none?["landLocations"])
    }

    func testASaveWithABadLocationIsRefused() throws {
        let world = try world()
        for bad: Any in [NSNull(), [["row": 0, "column": 0, "factors": [50]]], [["row": 0, "column": 9, "factors": [1_000]]],
                         [["row": 0, "column": 0, "factors": [1_000]], ["row": 0, "column": 0, "factors": [1_000]]]] {
            var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
            object["landLocations"] = bad
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: data), "\(bad)")
        }
    }

    /// The version 116 fixture: land with its places' factors. Written
    /// once, by the build that introduced the version
    /// (`LAND_LOCATIONS_SAVE_NEW`); every later build reads it to the same
    /// world and the same land values.
    func testTheVersion116FixtureLoadsToTheWorldThisBuildMakes() throws {
        var world = try world([
            LandCell(row: 1, column: 1, use: .residential, residents: 40, jobs: 0),
            LandCell(row: 5, column: 6, use: .commercial, residents: 0, jobs: 60),
        ])
        try world.setLandLocations([
            LandLocation(row: 0, column: 0, factor: 2_500), LandLocation(row: 0, column: 1, factor: 2_100), LandLocation(row: 1, column: 1, factor: 640),
        ])
        try world.advance(ticks: 3)
        let url = SavedGameTests.fixtures.appendingPathComponent("v116-land-locations.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["LAND_LOCATIONS_SAVE_NEW"] != nil, SavedGame.currentVersion == 116 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 116)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        XCTAssertEqual(loaded.landValue(row: 1, column: 1)?.base, 15_000)
        // 9,000 × 640 ÷ 1,000 = 5,760.
        XCTAssertEqual(loaded.landValue(row: 5, column: 6)?.base, 5_760)
    }
}
