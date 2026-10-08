import Foundation
@testable import GameCore
import XCTest

/// The company's buildings (city building P0-C1, ARCHITECTURE decision 94):
/// a managed company pays for each building and the right to use its land,
/// keeps it on its books, and earns its rent; the people in it ride from the
/// stations near it. Every number below is worked out by hand.
final class CompanyBuildingsTests: XCTestCase {
    /// 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)
    /// Station S0 stands at the middle of cell (5, 5), where 1,000 people
    /// live.
    private static let stationPoint = PlanPoint(x: 22_528, y: 22_528)
    /// A house centred in cell (7, 5), whose middle (22,528, 30,720) is
    /// 8,192 south of the station: w = 1000 − ⌊8192² × 1000 / 51200²⌋ =
    /// 1000 − 25 = 975; served at 800 that is S = 780; reaching 2 stations
    /// and on empty land (base 1,000) the land is worth 1,000 + 15 × 780 +
    /// 1,000 × 2 = 14,700 cents a m².
    private static let housePoint = PlanPoint(x: 24_000, y: 30_000)

    /// A managed world whose land sets ridership with town growth on, the
    /// station measured at `service` and 2 stations reached, and `balance`.
    private func world(service: Int64 = 800, balance: Money = 1_000_000_000) throws -> GameWorld {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: balance, costs: testCosts), clock: GameClock(speed: .normal))
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0)])
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        try world.buildStation(named: "S0", at: Self.stationPoint)
        world.growLand(reached: [:])
        world.townGrowth!.places[0].lastService = service
        world.townGrowth!.places[0].lastReached = 2
        return world
    }

    // MARK: - The kinds

    func testEachKindsFloorAndCapacity() {
        // Footprints 256, 576 and 1,024 m²; 2, 2 and 6 storeys.
        XCTAssertEqual(PlacedBuildingKind.allCases.map(\.footprintArea), [256, 576, 1_024])
        XCTAssertEqual(PlacedBuildingKind.allCases.map(\.floorArea), [512, 1_152, 6_144])
        // Decision 74: homes 7, shops 2, offices 1 eighths at 48 m² a
        // resident, the rest jobs at 32 m².
        XCTAssertEqual(PlacedBuildingKind.house.capacity, BuildingCapacity(residents: 9, jobs: 2))   // 448 / 48, 64 / 32
        XCTAssertEqual(PlacedBuildingKind.shop.capacity, BuildingCapacity(residents: 6, jobs: 27))   // 288 / 48, 864 / 32
        XCTAssertEqual(PlacedBuildingKind.office.capacity, BuildingCapacity(residents: 16, jobs: 168)) // 768 / 48, 5,376 / 32
    }

    // MARK: - Paying for it

    func testAManagedCompanyPaysForTheBuildingAndItsLand() throws {
        var world = try world()
        XCTAssertEqual(world.landValue(row: 7, column: 5)?.value, 14_700)
        // The building: 512 m² at $40, 2,048,000 cents; the land: 256 m² at
        // 14,700 cents, 3,763,200.
        let quote = try XCTUnwrap(world.placedBuildingQuote(.house, at: Self.housePoint))
        XCTAssertEqual(quote, PlacedBuildingQuote(building: 2_048_000, land: 3_763_200))
        XCTAssertEqual(quote.total, 5_811_200)
        XCTAssertNil(world.placedBuildingQuote(.house, at: PlanPoint(x: -1, y: 0)))
        let balance = world.economy.balance
        let house = try world.placeBuilding(.house, at: Self.housePoint)
        XCTAssertEqual(world.economy.balance, balance - 5_811_200)
        XCTAssertEqual([house.buildingCost, house.landCost], [2_048_000, 3_763_200])
        XCTAssertEqual([house.residents, house.jobs], [0, 0], "empty when built")
        let record = try XCTUnwrap(world.accounts.assets.first { $0.kind == .building })
        XCTAssertEqual([record.owner, Int(record.cost.amount)], [1, 5_811_200])
        XCTAssertEqual(world.accounts.capitalDays.last?.capitalSpending.amount, 1_000 + 5_811_200, "the station and the house")
        XCTAssertEqual(world.balanceSheet().buildings, AssetClassBalance(cost: 5_811_200, depreciation: .zero))
        XCTAssertEqual(AssetClass.buildings.lifeDays, 10_800, "30 years of 360 days")
    }

    func testNotEnoughMoneyBuildsNothing() throws {
        var world = try world(balance: 5_000_000)
        let before = world
        XCTAssertThrowsGameError(try world.placeBuilding(.house, at: Self.housePoint), .insufficientFunds(required: 5_811_200, available: before.economy.balance))
        XCTAssertEqual(world, before)
    }

    func testFreePlayPaysNothingAndKeepsNoBooks() throws {
        var world = GameWorld(bounds: Self.small, economy: GameEconomy(balance: 100, costs: testCosts))
        XCTAssertEqual(world.placedBuildingQuote(.office, at: Self.housePoint), PlacedBuildingQuote(building: .zero, land: .zero))
        let office = try world.placeBuilding(.office, at: Self.housePoint)
        XCTAssertEqual(world.economy.balance, 100)
        XCTAssertEqual(office.cost, .zero)
        XCTAssertTrue(world.accounts.assets.isEmpty)
        XCTAssertEqual(world.demolitionCost(of: office), .zero)
        try world.removePlacedBuilding(office.id)
        XCTAssertEqual(world.economy.balance, 100)
        XCTAssertTrue(world.placedBuildings.isEmpty)
    }

    // MARK: - Filling and riding

    func testABuildingFillsWhileAStationServesItAndEmptiesWithout() throws {
        var world = try world()
        let id = try world.placeBuilding(.house, at: Self.housePoint).id
        try world.placeBuilding(.office, at: PlanPoint(x: 30_000, y: 30_000))
        // The house: S = 780, 20 + 780 × 80 / 1000 = 82 thousandths a night;
        // its 9 × 82 / 1000 and 2 × 82 / 1000 round down to 0: at least 1
        // each. The office in cell (7, 7), 8,192 east and south: w = 1000 −
        // ⌊2 × 8192² × 1000 / 51200²⌋ = 949, S = 759, 20 + 60 = 80
        // thousandths: 16 × 80 / 1000 = 1 and 168 × 80 / 1000 = 13.
        XCTAssertEqual(world.landTerms(of: world.placedBuildings[0]).service, 780)
        XCTAssertEqual(world.landTerms(of: world.placedBuildings[1]).service, 759)
        world.fillPlacedBuildings()
        XCTAssertEqual(world.placedBuildings.map(\.residents), [1, 1])
        XCTAssertEqual(world.placedBuildings.map(\.jobs), [1, 13])
        world.fillPlacedBuildings()
        XCTAssertEqual(world.placedBuildings.map(\.residents), [2, 2])
        XCTAssertEqual(world.placedBuildings.map(\.jobs), [2, 26], "the house's 2 jobs are its capacity")
        for _ in 0..<20 { world.fillPlacedBuildings() }
        XCTAssertEqual(world.placedBuilding(id: id).map { [$0.residents, $0.jobs] }, [9, 2], "full")
        XCTAssertEqual(world.placedBuildings[1].jobs, 168)
        // No service: 20 thousandths go, at least one.
        world.townGrowth!.places[0].lastService = 0
        world.fillPlacedBuildings()
        XCTAssertEqual(world.placedBuilding(id: id).map { [$0.residents, $0.jobs] }, [8, 1])
        XCTAssertEqual(world.placedBuildings[1].jobs, 168 - 3, "168 × 20 / 1000 = 3")
    }

    func testThePeopleInTheCompanysBuildingsRideFromTheStationsNearIt() throws {
        var world = try world()
        let station = world.stations[0].id
        // 1,000 residents: (1000 × 40 + 50) / 100 = 400 trips.
        XCTAssertEqual(world.stationDemand(of: station)?.dailyTrips, 400)
        try world.placeBuilding(.office, at: Self.housePoint)
        XCTAssertEqual(world.stationDemand(of: station)?.dailyTrips, 400, "empty: no one rides")
        world.fillPlacedBuildings()
        world.refreshLandDemand()
        // 1,000 + 1 residents and 13 office jobs: (1014 × 40 + 50) / 100 = 406.
        XCTAssertEqual(world.stationDemand(of: station)?.dailyTrips, 406)
        let shares = LandDemand.shares(of: world.land, among: world.stations, placed: world.placedBuildings)
        XCTAssertEqual(shares[station], LandDemand.Share(residents: 1_001, officeJobs: 13))
        // Beyond 800 m a building is no station's.
        let far = LandDemand.shares(of: Land(), among: world.stations, placed: [{
            var building = PlacedBuilding(id: PlacedBuildingID(rawValue: 9), kind: .house, centre: PlanPoint(x: 100_000, y: 80_000))
            building.residents = 5
            return building
        }()])
        XCTAssertNil(far[station])
    }

    // MARK: - Rent, upkeep and tax

    func testTheDaysRentUpkeepAndTax() throws {
        var world = try world()
        let id = try world.placeBuilding(.house, at: Self.housePoint).id
        world.fillPlacedBuildings()
        let house = try XCTUnwrap(world.placedBuilding(id: id))
        // (1 × 1000 + 1 × 1500) × (1000 + 780 / 2) × 14,700 / 10,000,000
        // = 2,500 × 1,390 × 14,700 / 10^7 = 5,108 cents.
        XCTAssertEqual(world.dailyRent(of: house), 5_108)
        // Upkeep: 2,048,000 × 2 / 10,000 = 409.6, rounded up 410; tax:
        // (3,763,200 + 5,000) / 10,000 = 376.
        XCTAssertEqual(world.dailyUpkeep(of: house).upkeep, 410)
        XCTAssertEqual(world.dailyUpkeep(of: house).tax, 376)
        let balance = world.economy.balance
        world.settleProperty(day: 0, time: world.clock.now)
        let row = try XCTUnwrap(world.accounts.entries.last)
        XCTAssertEqual(row.kind, .dailyProperty)
        XCTAssertEqual(row.amount, 5_108 - 410 - 376)
        XCTAssertEqual(row.breakdown, [
            LedgerLine(item: .propertyRent, amount: 5_108), LedgerLine(item: .propertyUpkeep, amount: -410), LedgerLine(item: .propertyTax, amount: -376),
        ])
        XCTAssertEqual(world.economy.balance, balance + 4_322)
        let day = try XCTUnwrap(world.accounts.days.last)
        XCTAssertEqual([day.propertyRevenue, day.propertyCost], [5_108, 786])
        XCTAssertEqual(day.totalCost, .zero, "the railway's costs are apart")
        let summary = world.accounts.report(.day, day: 0).current
        XCTAssertEqual(summary.propertyRevenue, 5_108)
        XCTAssertEqual(summary.operatingProfit, 4_322)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "a well-formed row")
    }

    /// A real midnight: with no train running, the station served nothing
    /// that day, so the house stays empty and earns no rent, but pays its
    /// upkeep and tax, and is written down a day.
    func testAMidnightChargesTheUpkeepOfAnEmptyBuilding() throws {
        var world = try world()
        try world.placeBuilding(.house, at: Self.housePoint)
        // The day is settled at the start of the minute after it.
        try world.advance(ticks: 1_441)
        let row = try XCTUnwrap(world.accounts.entries.first { $0.kind == .dailyProperty })
        XCTAssertEqual(row.time, GameTime(minutes: 1_439))
        XCTAssertEqual(row.breakdown.map(\.amount), [0, -410, -376])
        XCTAssertEqual(world.placedBuildings[0].residents + world.placedBuildings[0].jobs, 0, "served nothing: still empty")
        // Written down a day: ⌊5,811,200 / 10,800⌋ = 538.
        XCTAssertEqual(world.accounts.assets.first { $0.kind == .building }?.depreciation, 538)
    }

    // MARK: - Demolishing

    func testDemolishingCostsATenthAndWritesOffTheRest() throws {
        var world = try world()
        let id = try world.placeBuilding(.house, at: Self.housePoint).id
        world.fillPlacedBuildings()
        world.refreshLandDemand()
        let station = world.stations[0].id
        XCTAssertEqual(world.stationDemand(of: station)?.dailyTrips, 401)
        // ⌈5,811,200 × 10 / 100⌉ = 581,120.
        XCTAssertEqual(world.demolitionCost(of: world.placedBuildings[0]), 581_120)
        let balance = world.economy.balance
        try world.removePlacedBuilding(id)
        XCTAssertEqual(world.economy.balance, balance - 581_120)
        XCTAssertTrue(world.placedBuildings.isEmpty)
        XCTAssertFalse(world.accounts.assets.contains { $0.kind == .building })
        XCTAssertEqual(world.accounts.capitalDays.last?.writeOff, 5_811_200, "nothing written down yet: all of it")
        XCTAssertEqual(world.stationDemand(of: station)?.dailyTrips, 400, "its riders go with it")
        XCTAssertThrowsGameError(try world.removePlacedBuilding(id), .unknownPlacedBuilding(id))
        XCTAssertEqual(try world.placeBuilding(.house, at: Self.housePoint).id.rawValue, 2, "its ID is not handed out again")
    }

    func testDemolishingNeedsTheMoney() throws {
        var world = try world(balance: 6_000_000)
        let id = try world.placeBuilding(.house, at: Self.housePoint).id
        let before = world
        XCTAssertThrowsGameError(try world.removePlacedBuilding(id), .insufficientFunds(required: 581_120, available: before.economy.balance))
        XCTAssertEqual(world, before)
    }

    // MARK: - Saving

    func testABuildingsPeopleAndCostSaveAndReadBack() throws {
        var world = try world()
        try world.placeBuilding(.office, at: Self.housePoint)
        world.fillPlacedBuildings()
        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let building = try XCTUnwrap((object["placedBuildings"] as? [[String: Any]])?.first)
        XCTAssertEqual(building["residents"] as? Int, 1)
        XCTAssertEqual(building["jobs"] as? Int, 13)
        XCTAssertEqual(building["buildingCost"] as? Int, 6_144 * 4_000)
        XCTAssertEqual(building["landCost"] as? Int, 1_024 * 14_700)
        // More people than it holds is refused.
        var tooFull = object
        var buildings = try XCTUnwrap(object["placedBuildings"] as? [[String: Any]])
        buildings[0]["jobs"] = 169
        tooFull["placedBuildings"] = buildings
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: tooFull)))
    }

    func testStatementsWithoutBuildingsSaveAsBefore() throws {
        // A closed year's statement and balance sheet without buildings
        // write no new keys, so saves before version 22 read and write the
        // same.
        let sheet = BalanceSheet(cash: 5, track: .zero, stations: .zero, rollingStock: .zero, loan: .zero)
        let sheetObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(sheet)) as? [String: Any])
        XCTAssertNil(sheetObject["buildings"])
        XCTAssertEqual(try JSONDecoder().decode(BalanceSheet.self, from: JSONEncoder().encode(sheet)), sheet)
        let summary = FinanceSummary(index: 0, fareRevenue: 1, operatingCost: 0, maintenanceCost: 0, energyCost: 0, staffCost: 0, interestCost: 0)
        let summaryObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any])
        XCTAssertNil(summaryObject["propertyRevenue"])
        XCTAssertNil(summaryObject["propertyCost"])
        var withProperty = summary
        withProperty.propertyRevenue = 7
        XCTAssertEqual(try JSONDecoder().decode(FinanceSummary.self, from: JSONEncoder().encode(withProperty)), withProperty)
    }
}
