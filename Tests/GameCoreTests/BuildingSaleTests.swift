import Foundation
@testable import GameCore
import XCTest

/// Selling the company's buildings (city building P0-D, ARCHITECTURE
/// decision 130): the price is 95% of the right to use the land now and the
/// building's book value, in full at half full and pro rata below; the gain
/// or loss against the record's book value is realized, and the building
/// becomes the city's. Every number below is worked out by hand.
final class BuildingSaleTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// The world of ``CompanyBuildingsTests``: station S0 at the middle of
    /// cell (5, 5), where 1,000 people live, measured at 800 and reaching
    /// 2 stations, so the land of cell (7, 5) is worth 14,700 cents a m².
    private static let stationPoint = PlanPoint(x: 22_528, y: 22_528)
    /// A house centred in cell (7, 5): 2,048,000 for the building and
    /// 256 × 14,700 = 3,763,200 for the land, 5,811,200 together.
    private static let housePoint = PlanPoint(x: 24_000, y: 30_000)

    private func world(cityBuildings: Bool = false) throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)])
        world.setCityBuildings(cityBuildings)
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        try world.buildStation(named: "S0", at: Self.stationPoint)
        world.growLand(reached: [:])
        world.townGrowth!.places[0].lastService = 800
        world.townGrowth!.places[0].lastReached = 2
        return world
    }

    /// Puts `residents` and `jobs` in building `id`, as nights of filling
    /// would.
    private func occupy(_ world: inout GameWorld, _ id: PlacedBuildingID, residents: Int64, jobs: Int64) {
        let index = world.placedBuildings.firstIndex { $0.id == id }!
        world.placedBuildings[index].residents = residents
        world.placedBuildings[index].jobs = jobs
        world.refreshLandDemand()
    }

    // MARK: - The price

    func testAnEmptyBuildingSellsForItsLandAlone() throws {
        var world = try world()
        let id = try world.placeBuilding(.house, at: Self.housePoint).id
        XCTAssertEqual(world.landValue(row: 7, column: 5)?.value, 14_700)
        let quote = try XCTUnwrap(world.saleQuote(of: id))
        XCTAssertEqual(quote.landRight, 3_763_200)
        XCTAssertEqual(quote.land, 3_575_040, "3,763,200 × 95 / 100")
        XCTAssertEqual(quote.buildingBookValue, 2_048_000, "not written down yet")
        XCTAssertEqual([quote.occupants, quote.capacity], [0, 11])
        XCTAssertEqual(quote.occupancyFactor, 0)
        XCTAssertEqual(quote.building, .zero, "no one in it: the building brings nothing")
        XCTAssertEqual(quote.price, 3_575_040)
        XCTAssertEqual(quote.bookValue, 5_811_200)
        XCTAssertEqual(quote.gain, -2_236_160, "a loss of the land's twentieth and the whole building")
        XCTAssertNil(world.saleQuote(of: PlacedBuildingID(rawValue: 9)))
    }

    func testTheBuildingCountsInFullFromHalfFullAndProRataBelow() throws {
        var world = try world()
        let id = try world.placeBuilding(.house, at: Self.housePoint).id
        // A house holds 9 + 2 = 11. 4 people: 8 / 11 of 2,048,000 is
        // 1,489,454.5…, rounded down.
        occupy(&world, id, residents: 2, jobs: 2)
        XCTAssertEqual(world.saleQuote(of: id)?.building, 1_489_454)
        XCTAssertEqual(world.saleQuote(of: id)?.occupancyFactor, 727, "8,000 / 11")
        // 5 people: 10 / 11, 1,861,818.1….
        occupy(&world, id, residents: 3, jobs: 2)
        XCTAssertEqual(world.saleQuote(of: id)?.building, 1_861_818)
        // 6 people is more than half of 11: in full.
        occupy(&world, id, residents: 4, jobs: 2)
        XCTAssertEqual(world.saleQuote(of: id)?.building, 2_048_000)
        XCTAssertEqual(world.saleQuote(of: id)?.occupancyFactor, 1_000)
        occupy(&world, id, residents: 9, jobs: 2)
        XCTAssertEqual(world.saleQuote(of: id)?.price, 3_575_040 + 2_048_000, "full is no more than half full")
    }

    func testTheBuildingIsWrittenDownOnItsOwnAndTheLandSellsAtItsValueNow() throws {
        var world = try world()
        let id = try world.placeBuilding(.house, at: Self.housePoint).id
        // A real midnight: the record (5,811,200) is written down a day,
        // ⌊5,811,200 / 10,800⌋ = 538; the building alone ⌊2,048,000 /
        // 10,800⌋ = 189.
        try world.advance(ticks: 1_441)
        let record = try XCTUnwrap(world.accounts.assets.first { $0.kind == .building })
        XCTAssertEqual([record.days, record.depreciation.amount], [1, 538])
        occupy(&world, id, residents: 4, jobs: 2)
        let quote = try XCTUnwrap(world.saleQuote(of: id))
        XCTAssertEqual(quote.buildingBookValue, 2_048_000 - 189)
        XCTAssertEqual(quote.bookValue, 5_811_200 - 538)
        // The land is quoted at its value now, not at what was paid.
        let value = try XCTUnwrap(world.landValue(row: 7, column: 5)?.value)
        XCTAssertEqual(quote.landRight, Money(256 * value))
    }

    // MARK: - Selling

    func testSellingPaysThePriceAndRealizesTheGainOrLoss() throws {
        var world = try world()
        let id = try world.placeBuilding(.house, at: Self.housePoint).id
        try world.advance(ticks: 1_441)
        occupy(&world, id, residents: 4, jobs: 2)
        let quote = try XCTUnwrap(world.saleQuote(of: id))
        let land = quote.land
        // 95% of the land now and the building's 2,047,811 in full.
        XCTAssertEqual(quote.price, land + 2_047_811)
        let balance = world.economy.balance
        let equity = world.balanceSheet().equity
        let rows = world.accounts.entries
        XCTAssertEqual(try world.sellPlacedBuilding(id), quote)
        XCTAssertEqual(world.economy.balance, balance + quote.price)
        XCTAssertTrue(world.placedBuildings.isEmpty)
        XCTAssertFalse(world.accounts.assets.contains { $0.kind == .building })
        XCTAssertEqual(world.balanceSheet().buildings, .zero)
        XCTAssertEqual(world.balanceSheet().equity, equity + quote.gain, "the gain realized is all that equity moves by")
        let capital = try XCTUnwrap(world.accounts.capitalDays.last)
        XCTAssertEqual([capital.day, capital.saleProceeds.amount, capital.saleBookValue.amount], [1, quote.price.amount, 5_810_662])
        XCTAssertEqual(capital.writeOff, .zero, "a sale writes nothing off")
        // The day's statements: the gain in the net profit, the cash in the
        // investing activities; no ledger row, as buying wrote none.
        let day = world.financeReport(.day).current
        XCTAssertEqual(day.saleProceeds, quote.price)
        XCTAssertEqual(day.saleBookValue, 5_810_662)
        XCTAssertEqual(day.realizedGain, quote.gain)
        XCTAssertEqual(day.investingCashFlow, quote.price)
        XCTAssertEqual(day.netProfit, day.operatingProfit - day.interestCost - day.depreciationCost - day.writeOffCost + quote.gain)
        XCTAssertEqual(world.accounts.entries, rows)
        XCTAssertThrowsGameError(try world.sellPlacedBuilding(id), .unknownPlacedBuilding(id))
        XCTAssertEqual(try world.placeBuilding(.house, at: PlanPoint(x: 24_000, y: 40_000)).id.rawValue, 2, "its ID is not handed out again")
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testAnUnknownBuildingIsRefusedAndChangesNothing() throws {
        var world = try world()
        try world.placeBuilding(.house, at: Self.housePoint)
        let before = world
        XCTAssertThrowsGameError(try world.sellPlacedBuilding(PlacedBuildingID(rawValue: 2)), .unknownPlacedBuilding(PlacedBuildingID(rawValue: 2)))
        XCTAssertEqual(world, before)
    }

    func testFreePlaySellsForNothingAndTheCityStillTakesItOver() throws {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 100, costs: testCosts))
        let id = try world.placeBuilding(.office, at: Self.housePoint).id
        occupy(&world, id, residents: 3, jobs: 40)
        XCTAssertEqual(world.saleQuote(of: id)?.price, .zero)
        try world.sellPlacedBuilding(id)
        XCTAssertEqual(world.economy.balance, 100)
        XCTAssertTrue(world.accounts.capitalDays.isEmpty)
        XCTAssertEqual(world.land.cell(row: 7, column: 5), LandCell(row: 7, column: 5, use: .office, residents: 3, jobs: 40))
    }

    // MARK: - The city takes it over

    func testItsPeopleBecomeTheCitysOnTheCellUnderItAndItsCellsAreTheCitysAgain() throws {
        var world = try world(cityBuildings: true)
        let id = try world.placeBuilding(.house, at: Self.housePoint).id
        XCTAssertTrue(world.isClaimedByPlacedBuilding(row: 7, column: 5))
        occupy(&world, id, residents: 6, jobs: 2)
        let station = world.stations[0].id
        let trips = world.stationDemand(of: station)?.dailyTrips
        try world.sellPlacedBuilding(id)
        XCTAssertFalse(world.isClaimedByPlacedBuilding(row: 7, column: 5), "the city may grow there again")
        XCTAssertEqual(world.land.cell(row: 7, column: 5), LandCell(row: 7, column: 5, use: .residential, residents: 6, jobs: 2))
        // A D1 home holds 56 residents: the city's building on it is the
        // next number.
        let building = try XCTUnwrap(world.buildings.building(row: 7, column: 5))
        XCTAssertEqual([building.kind, building.use, building.density] as [AnyHashable], [BuildingKind.city, LandUse.residential, BuildingDensity.d1])
        XCTAssertEqual(building.id, world.buildings.all.last?.id)
        // The same people ride from the same station: 1,006 residents.
        XCTAssertEqual(world.stationDemand(of: station)?.dailyTrips, trips)
        XCTAssertNil(world.buildingProblem())
    }

    /// Decision 95: the city puts up nothing on a cell one of the company's
    /// buildings still claims. A house beside the one sold, in the same
    /// cell, keeps it; with no other cell under the one sold, its people
    /// leave, as growth's do.
    func testPeopleDoNotMoveOntoACellAnotherOfTheCompanysBuildingsClaims() throws {
        var world = try world(cityBuildings: true)
        let sold = try world.placeBuilding(.house, at: Self.housePoint).id
        try world.placeBuilding(.house, at: PlanPoint(x: 21_900, y: 30_000))
        occupy(&world, sold, residents: 6, jobs: 2)
        try world.sellPlacedBuilding(sold)
        XCTAssertTrue(world.isClaimedByPlacedBuilding(row: 7, column: 5), "the other house still claims the cell")
        XCTAssertNil(world.land.cell(row: 7, column: 5))
        XCTAssertNil(world.buildings.building(row: 7, column: 5))
        XCTAssertNil(world.buildingProblem())
    }

    func testAnEmptyBuildingLeavesNoLand() throws {
        var world = try world(cityBuildings: true)
        let id = try world.placeBuilding(.house, at: Self.housePoint).id
        let cells = world.land.cells.count
        try world.sellPlacedBuilding(id)
        XCTAssertEqual(world.land.cells.count, cells)
        XCTAssertNil(world.land.cell(row: 7, column: 5))
    }

    /// A house at the north-west corner of cell (7, 5), at (20,580, 28,772),
    /// claims no city building: its square grown by 2 m reaches x 21,220
    /// and y 29,412, short of the cell's middle square (21,248 and 29,440).
    private static let cornerPoint = PlanPoint(x: 20_580, y: 28_772)

    func testPeopleJoinACellOfTheCitysAndItsBuildingStaysWhileItHoldsThem() throws {
        var world = try world(cityBuildings: true)
        try world.setLand([
            LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0),
            LandCell(row: 7, column: 5, use: .residential, residents: 40, jobs: 0),
        ])
        let id = try world.placeBuilding(.house, at: Self.cornerPoint).id
        XCTAssertNotNil(world.land.cell(row: 7, column: 5), "not bought out")
        let standing = try XCTUnwrap(world.buildings.building(row: 7, column: 5))
        occupy(&world, id, residents: 9, jobs: 2)
        try world.sellPlacedBuilding(id)
        // 40 + 9 = 49 residents, within D1's 56: the same building.
        XCTAssertEqual(world.land.cell(row: 7, column: 5), LandCell(row: 7, column: 5, use: .residential, residents: 49, jobs: 2))
        XCTAssertEqual(world.buildings.building(row: 7, column: 5), standing)
        XCTAssertNil(world.buildingProblem())
    }

    func testACellTooFullForItsBuildingGetsOneThatHoldsIt() throws {
        var world = try world(cityBuildings: true)
        try world.setLand([
            LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0),
            LandCell(row: 7, column: 5, use: .residential, residents: 50, jobs: 0),
        ])
        let id = try world.placeBuilding(.house, at: Self.cornerPoint).id
        let standing = try XCTUnwrap(world.buildings.building(row: 7, column: 5))
        XCTAssertEqual(standing.density, .d1)
        occupy(&world, id, residents: 9, jobs: 2)
        try world.sellPlacedBuilding(id)
        // 59 residents: more than D1's 56, so D2 (168), numbered last.
        let building = try XCTUnwrap(world.buildings.building(row: 7, column: 5))
        XCTAssertEqual(building.density, .d2)
        XCTAssertEqual(building.id, world.buildings.all.last?.id)
        XCTAssertGreaterThan(building.id, standing.id)
        XCTAssertEqual(world.land.cell(row: 7, column: 5)?.residents, 59)
        XCTAssertNil(world.buildingProblem())
    }

    func testAParkUnderItTakesTheBuildingsUse() throws {
        var world = try world(cityBuildings: true)
        try world.setLand([
            LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0),
            LandCell(row: 7, column: 5, use: .park, residents: 0, jobs: 0),
        ])
        let id = try world.placeBuilding(.house, at: Self.cornerPoint).id
        XCTAssertEqual(world.land.cell(row: 7, column: 5)?.use, .park, "a house at the corner claims no park")
        occupy(&world, id, residents: 3, jobs: 1)
        try world.sellPlacedBuilding(id)
        XCTAssertEqual(world.land.cell(row: 7, column: 5), LandCell(row: 7, column: 5, use: .residential, residents: 3, jobs: 1))
        XCTAssertEqual(world.buildings.building(row: 7, column: 5)?.use, .residential)
        XCTAssertNil(world.buildingProblem())
    }

    func testAMarinaOverTheWaterHandsItsPeopleToTheBankUnderIt() throws {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts))
        world.setCityBuildings(true)
        // A river down column 10.
        try world.setWater((0..<24).map { CellPosition(row: $0, column: 10) })
        // Across the west bank (x 40,960): its square covers rows 14 and 15,
        // columns 9 and 10; its centre is over the water.
        let id = try world.placeBuilding(.marina, at: PlanPoint(x: 40_960, y: 61_440)).id
        XCTAssertTrue(world.terrain.isWater(row: 15, column: 10))
        occupy(&world, id, residents: 2, jobs: 30)
        try world.sellPlacedBuilding(id)
        XCTAssertEqual(world.land.cell(row: 14, column: 9), LandCell(row: 14, column: 9, use: .leisure, residents: 2, jobs: 30))
        XCTAssertNil(world.terrainProblem())
        XCTAssertNil(world.buildingProblem())
    }

    // MARK: - Saving

    func testASalesCapitalDayAndStatementSaveAndReadBack() throws {
        var day = CapitalDay(day: 3)
        day.saleProceeds = 7
        day.saleBookValue = 9
        let data = try JSONEncoder().encode(day)
        XCTAssertEqual(try JSONDecoder().decode(CapitalDay.self, from: data), day)
        // A day or year that sold nothing writes neither key, as before
        // version 29.
        let none = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(CapitalDay(day: 3))) as? [String: Any])
        XCTAssertEqual(Set(none.keys), ["day"])
        var summary = FinanceSummary(index: 0, fareRevenue: 1, operatingCost: 0, maintenanceCost: 0, energyCost: 0, staffCost: 0, interestCost: 0)
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any])
        XCTAssertNil(plain["saleProceeds"])
        XCTAssertNil(plain["saleBookValue"])
        summary.saleProceeds = 5
        summary.saleBookValue = 8
        XCTAssertEqual(summary.realizedGain, -3)
        XCTAssertEqual(summary.investingCashFlow, 5)
        XCTAssertEqual(try JSONDecoder().decode(FinanceSummary.self, from: JSONEncoder().encode(summary)), summary)
    }

    // MARK: - The version 29 save

    /// `SaveFixtures/` at the repository root.
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures", isDirectory: true)

    /// The world of `v29-building-sale.json` (decision 130): the world of
    /// these tests with the city's buildings on, a house and an office block
    /// bought beside S0, run past a midnight, the house filled to 6 of 11
    /// and the office to 3 and 20 of 184, both sold the next morning: the
    /// house's people on cell (7, 5), the office's on cell (7, 7); run ten
    /// minutes more.
    static func saleWorld() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 131_072, height: 98_304), economy: GameEconomy(balance: 1_000_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        try world.buildStation(named: "S0", at: PlanPoint(x: 22_528, y: 22_528))
        let house = try world.placeBuilding(.house, at: PlanPoint(x: 24_000, y: 30_000)).id
        let office = try world.placeBuilding(.office, at: PlanPoint(x: 30_000, y: 30_000)).id
        try world.advance(ticks: 1_450)
        for (id, people) in [(house, (Int64(4), Int64(2))), (office, (Int64(3), Int64(20)))] {
            let index = world.placedBuildings.firstIndex { $0.id == id }!
            world.placedBuildings[index].residents = people.0
            world.placedBuildings[index].jobs = people.1
        }
        world.refreshLandDemand()
        try world.sellPlacedBuilding(house)
        try world.sellPlacedBuilding(office)
        try world.advance(ticks: 10)
        return world
    }

    /// Version 29 (decision 130): two buildings sold, the capital day with
    /// their proceeds and book value, and their people the city's. It saves
    /// byte for byte and is the world this build makes.
    func testVersionTwentyNineKeepsTheSales() throws {
        let url = Self.fixtures.appendingPathComponent("v29-building-sale.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["BUILDING_SALE_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: try Self.saleWorld())).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 29)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, try Self.saleWorld())
        XCTAssertTrue(world.placedBuildings.isEmpty)
        XCTAssertFalse(world.accounts.assets.contains { $0.kind == .building })
        let sold = try XCTUnwrap(world.accounts.capitalDays.first { $0.saleProceeds > .zero })
        XCTAssertEqual(sold.day, 1)
        XCTAssertGreaterThan(sold.saleBookValue, sold.saleProceeds, "sold at a loss")
        XCTAssertEqual(world.land.cell(row: 7, column: 5)?.residents, 4)
        XCTAssertEqual(world.land.cell(row: 7, column: 7)?.jobs, 20)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 29,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
