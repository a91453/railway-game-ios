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

    // MARK: - Decision 728: the uses of the company's buildings lift the city's land round them

    func testTheTableLiftsByUseAndAFactoryDropsHomes() {
        XCTAssertEqual(LandValueRules.industryTenths(from: .commercial, to: .residential), 9)
        XCTAssertEqual(LandValueRules.industryTenths(from: .office, to: .residential), 5)
        XCTAssertEqual(LandValueRules.industryTenths(from: .residential, to: .office), 3)
        XCTAssertEqual(LandValueRules.industryTenths(from: .industrial, to: .residential), -9)
        XCTAssertEqual(LandValueRules.industryTenths(from: .civic, to: .residential), 0, "schools' and hospitals' own premium")
        XCTAssertEqual(LandValueRules.industryTenths(from: .commercial, to: .commercial), 0, "a use does not lift its own")
        XCTAssertEqual(LandValueRules.industryTenths(from: .park, to: .residential), 0, "parks are decision 91's")
        let centre = PlanPoint(x: 0, y: 0)
        // Strong 9 + middling 5 + weak 3 is 17, at most 14; the drop on top.
        let tenths = GameWorld.industryTenths(at: centre, of: .residential, [.commercial: [centre], .office: [centre], .leisure: [centre], .industrial: [centre]])
        XCTAssertEqual(tenths.lift, 14)
        XCTAssertEqual(tenths.drop, -9)
        // Two of a use count once; one 400 m away or more, not at all.
        XCTAssertEqual(GameWorld.industryTenths(at: centre, of: .residential, [.commercial: [centre, centre]]).lift, 9)
        XCTAssertEqual(GameWorld.industryTenths(at: centre, of: .residential, [.commercial: [PlanPoint(x: 25_600, y: 0)]]).lift, 0)
        XCTAssertEqual(GameWorld.industryTenths(at: centre, of: .residential, [.commercial: [PlanPoint(x: 25_599, y: 0)]]).lift, 9)
    }

    func testAHouseLiftsTheOfficesRoundItAndAShopLiftsThemMore() throws {
        var world = try world(offices: true)
        let before = try XCTUnwrap(world.landValue(row: 6, column: 5))
        XCTAssertEqual(before.companyPremium, 0)
        _ = try world.placeBuilding(.house, at: Self.housePoint)
        let afterHouse = try XCTUnwrap(world.landValue(row: 6, column: 5))
        XCTAssertEqual(afterHouse.companyPremium, 900, "homes lift offices weakly: 3 tenths × 300")
        XCTAssertEqual(afterHouse.value - before.value, 900)
        _ = try world.placeBuilding(.shop, at: PlanPoint(x: 24_000, y: 38_000))
        XCTAssertEqual(world.landValue(row: 6, column: 5)?.companyPremium, 2_400, "and shops middling: 3 + 5 tenths")
        // Empty land has no use to lift.
        XCTAssertEqual(world.landValue(row: 20, column: 20)?.companyPremium, 0)
    }

    func testWhatAShopIsBoughtAtIsWhatItsLandIsWorthOnceItStands() throws {
        var world = try world(offices: true)
        let quoted = try XCTUnwrap(world.placedBuildingQuote(.shop, at: Self.housePoint))
        let shop = try world.placeBuilding(.shop, at: Self.housePoint)
        // Its own use is left out of its land (decision 728), so standing
        // there adds nothing to what it is worth.
        XCTAssertEqual(world.saleQuote(of: shop.id)?.landRight, quoted.land)
        XCTAssertEqual(world.companyLandValue(of: shop)?.companyPremium, 0)
    }

    func testJobsGoMoreToLiftedCellsAndNoneAreLost() {
        // Two cells of 100 jobs, plain weights equal; the second lifted 9
        // tenths. 190 to share: by 10 and 19 tenths, 66 and 124, and the
        // second has room for only 100, so 24 go back to the first.
        let shares = GameWorld.steeredShares(190, plain: [100, 100], steered: [1_000, 1_900], room: [500, 100])
        XCTAssertEqual(shares, [90, 100])
        XCTAssertEqual(shares.reduce(0, +), 190)
        // Unlifted, the plain share.
        XCTAssertEqual(GameWorld.steeredShares(190, plain: [100, 100], steered: [1_000, 1_000], room: [500, 500]), [95, 95])
    }
}
