@testable import GameCore
import XCTest

/// Decision 727 (the subsidiary design's step 2): the land under the
/// company's building is worth at least the mean base of the eight cells
/// round it, so that land the town grows round rises with it.
final class CompanyLandValueTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// The station of ``BuildingSaleTests``: the middle of cell (5, 5).
    private static let stationPoint = PlanPoint(x: 22_528, y: 22_528)
    /// A house centred in cell (7, 5).
    private static let housePoint = PlanPoint(x: 24_000, y: 30_000)

    /// The world of ``BuildingSaleTests``, and with `offices`, offices of
    /// 400 jobs on the eight cells round (7, 5).
    private func world(offices: Bool) throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: fixtureEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        var cells = [LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)]
        if offices {
            for row in 6...8 {
                for column in 4...6 where (row, column) != (7, 5) {
                    cells.append(LandCell(row: row, column: column, use: .office, residents: 0, jobs: 400))
                }
            }
        }
        try world.setLand(cells)
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        try world.buildStation(named: "S0", at: Self.stationPoint)
        world.growLand(reached: [:])
        world.townGrowth!.places[0].lastService = 800
        world.townGrowth!.places[0].lastReached = 2
        return world
    }

    /// The base the eight cells round (`row`, `column`) count for
    /// `building`, worked out from the city's buildings one by one.
    private func meanBase(round row: Int, _ column: Int, for building: PlacedBuilding, in world: GameWorld) -> Int64? {
        var sum: Int64 = 0, count: Int64 = 0
        for r in (row - 1)...(row + 1) {
            for c in (column - 1)...(column + 1) where (r, c) != (row, column) {
                let side = world.cityBuildingSide(row: r, column: c)
                if GameWorld.claims(building, row: r, column: c, side: side) || world.isClaimedByPlacedBuilding(row: r, column: c) { continue }
                if let city = world.buildings.building(row: r, column: c) {
                    sum += LandValueRules.base(of: city.use) * LandValueRules.densityFactor(city.density) / 1_000
                } else {
                    sum += LandValueRules.vacantBase
                }
                count += 1
            }
        }
        return count == 0 ? nil : sum / count
    }

    func testABuildingOnEmptyLandIsWorthWhatItWas() throws {
        var world = try world(offices: false)
        let building = try world.placeBuilding(.house, at: Self.housePoint)
        let city = try XCTUnwrap(world.landValue(row: 7, column: 5))
        XCTAssertEqual(world.companyLandValue(of: building), city, "empty land round it raises nothing")
        XCTAssertEqual(city.value, 44_100, "BuildingSaleTests' number")
        XCTAssertEqual(world.saleQuote(of: building.id)?.landRight, 11_289_600)
    }

    func testOfficesRoundItRaiseItsLandToTheirMeanBase() throws {
        var world = try world(offices: true)
        let quote = try XCTUnwrap(world.placedBuildingQuote(.house, at: Self.housePoint))
        let building = try world.placeBuilding(.house, at: Self.housePoint)
        let city = try XCTUnwrap(world.landValue(row: 7, column: 5))
        let mean = try XCTUnwrap(meanBase(round: 7, 5, for: building, in: world))
        XCTAssertGreaterThan(mean, city.base, "offices are worth more than the house's own cell")
        let company = try XCTUnwrap(world.companyLandValue(of: building))
        XCTAssertEqual(company.base, mean)
        XCTAssertEqual(company.value - company.base, city.value - city.base, "the premiums are the city's")
        XCTAssertGreaterThan(company.value, city.value)
        // What it was bought at, what it sells for and its rent all read it.
        XCTAssertEqual(quote.land, Money(PlacedBuildingKind.house.footprintArea * company.value))
        XCTAssertEqual(world.saleQuote(of: building.id)?.landRight, Money(PlacedBuildingKind.house.footprintArea * company.value))
        // No more than the offices' own land: a D1 to D4 office's base.
        XCTAssertLessThanOrEqual(company.base, LandValueRules.base(of: .office) * LandValueRules.densityFactor(.d4) / 1_000)
        // The city's own layer is as it was.
        XCTAssertEqual(world.landValues(rows: 7...7, columns: 5...5), [city])
    }

    func testCellsTheCompanyClaimsDoNotCount() throws {
        var world = try world(offices: true)
        let building = try world.placeBuilding(.house, at: Self.housePoint)
        let before = try XCTUnwrap(world.companyLandValue(of: building))
        // A second house in the cell beside it pulls that office down and
        // claims its cell: the mean is of the seven left.
        _ = try world.placeBuilding(.house, at: PlanPoint(x: 24_000 + 4_096, y: 30_000))
        let after = try XCTUnwrap(world.companyLandValue(of: building))
        let mean = try XCTUnwrap(meanBase(round: 7, 5, for: building, in: world))
        let own = try XCTUnwrap(world.landValue(row: 7, column: 5)).base
        XCTAssertEqual(after.base, max(mean, own))
        XCTAssertTrue(world.isClaimedByPlacedBuilding(row: 7, column: 6))
        XCTAssertLessThanOrEqual(after.base, before.base)
    }
}
