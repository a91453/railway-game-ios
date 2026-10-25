import Foundation
@testable import GameCore
import XCTest

/// The company's schools, hospitals and night markets (decision 361's
/// sequel): a school or a hospital raises the land round it and draws the
/// city's new homes there, a night market is a sight as a temple is, and
/// each kind's look is kept. Every expectation is worked out by hand from
/// the rules.
final class SchoolsHospitalsNightMarketsTests: XCTestCase {
    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)

    /// `ParksAndTemplesTests`' world: Home and Foot with a train, a 3-star
    /// town far from both (so tourism is on), in a managed company with cash.
    private func world() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: GameEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        try world.buildStation(named: "Home", at: PlanPoint(x: 10_000, y: 32_768))
        try world.buildStation(named: "Foot", at: PlanPoint(x: 30_000, y: 32_768))
        let line = try world.createLine(named: "Main", stops: [home, foot]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 0))
        try world.setStationDemand(foot, to: StationDemand(kind: .scenic, dailyTrips: 0))
        world.setOutsideConnections(true)
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "x", englishName: "x", point: PlanPoint(x: 120_000, y: 2_000), kind: .town, baseStars: 300)])
        return world
    }

    // MARK: - The kinds

    func testTheNewKindsHoldNoOneAndHaveTwoLooks() throws {
        for kind in [PlacedBuildingKind.school, .hospital, .nightMarket] {
            XCTAssertEqual(kind.capacity, BuildingCapacity(residents: 0, jobs: 0), "\(kind)")
            XCTAssertEqual(kind.looks, 2, "\(kind)")
            XCTAssertFalse(kind.standsOnShore)
        }
        XCTAssertEqual([PlacedBuildingKind.school, .hospital, .nightMarket].map(\.side), [3_072, 2_048, 2_048])
        XCTAssertEqual([PlacedBuildingKind.school, .hospital, .nightMarket].map(\.floors), [3, 6, 1])
        XCTAssertEqual([PlacedBuildingKind.school, .hospital, .nightMarket].map(\.use), [.civic, .civic, .commercial])
        XCTAssertEqual(PlacedBuildingKind.allCases.filter(\.isSight), [.temple, .nightMarket])
        XCTAssertEqual(PlacedBuildingKind.allCases.filter(\.isSubsidiary), [.departmentStore, .hotel, .amusementPark, .temple, .nightMarket])
        var world = try world()
        XCTAssertThrowsError(try world.placeBuilding(.school, at: PlanPoint(x: 20_000, y: 10_000), look: 2)) {
            XCTAssertEqual($0 as? GameError, .invalidBuildingLook)
        }
        let school = try world.placeBuilding(.school, at: PlanPoint(x: 20_000, y: 10_000), look: 1)
        XCTAssertEqual(world.placedBuilding(id: school.id)?.look, 1)
        XCTAssertEqual(world.dailyRent(of: school), .zero, "it lets nothing")
    }

    // MARK: - Schools and hospitals

    func testASchoolAndAHospitalRaiseTheLandRoundThem() throws {
        var world = try world()
        // Row 2, column 5 has its middle at (22,528, 10,240).
        XCTAssertEqual(world.landValue(row: 2, column: 5)?.civicPremium, 0)
        let before = try XCTUnwrap(world.landValue(row: 2, column: 5)?.value)
        try world.placeBuilding(.school, at: PlanPoint(x: 20_000, y: 10_000))
        XCTAssertEqual(world.landValue(row: 2, column: 5)?.civicPremium, 900)
        XCTAssertEqual(world.landValue(row: 2, column: 5)?.value, before + 900)
        // 400 m is 25,600 units: six cells east of the school's (20,000 →
        // 45,056, 25,056 off) is within, seven (49,152, 29,152) is not.
        XCTAssertEqual(world.landValue(row: 2, column: 10)?.civicPremium, 900)
        XCTAssertEqual(world.landValue(row: 2, column: 11)?.civicPremium, 0)
        try world.placeBuilding(.hospital, at: PlanPoint(x: 26_000, y: 10_000))
        XCTAssertEqual(world.landValue(row: 2, column: 5)?.civicPremium, 1_400, "a school's and a hospital's add")
        // A second school counts once.
        try world.placeBuilding(.school, at: PlanPoint(x: 20_000, y: 16_000))
        XCTAssertEqual(world.landValue(row: 2, column: 5)?.civicPremium, 1_400)
    }

    func testAHouseBesideASchoolLetsForMore() throws {
        var world = try world()
        let house = try world.placeBuilding(.house, at: PlanPoint(x: 20_000, y: 16_000))
        let under = { (world: GameWorld) in world.landValue(row: Land.cellIndex(house.centre.y), column: Land.cellIndex(house.centre.x))?.value }
        XCTAssertEqual(under(world), 1_000)
        try world.placeBuilding(.school, at: PlanPoint(x: 20_000, y: 10_000))
        XCTAssertEqual(under(world), 1_900)
    }

    /// Two homes of 100 residents the same way from a station, 320 m off
    /// (outside its front); a school within 400 m of the west one only.
    private func growingWorld(with kind: PlacedBuildingKind?) throws -> (world: GameWorld, station: Station) {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: GameEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        // Cells (10, 10) and (10, 20): middles (43,008, 43,008) and
        // (83,968, 43,008), 640 m apart.
        try world.setLand([
            LandCell(row: 10, column: 10, use: .residential, residents: 100, jobs: 0),
            LandCell(row: 10, column: 20, use: .residential, residents: 100, jobs: 0),
        ])
        let station = try world.buildStation(named: "S", at: PlanPoint(x: 63_488, y: 43_008))
        if let kind {
            // 13,008 units (203 m) from the west home, 53,968 (843 m) from the east.
            try world.placeBuilding(kind, at: PlanPoint(x: 30_000, y: 43_008))
        }
        return (world, station)
    }

    func testTheCitysNewHomesGrowNearASchoolOrAHospital() throws {
        func grown(with kind: PlacedBuildingKind?) throws -> [Int64] {
            var (world, station) = try growingWorld(with: kind)
            world.grow(around: station, residents: 290, jobs: 0)
            return [try XCTUnwrap(world.land.cell(row: 10, column: 10)).residents, try XCTUnwrap(world.land.cell(row: 10, column: 20)).residents]
        }
        // By residents alone: 145 each.
        XCTAssertEqual(try grown(with: nil), [245, 245])
        // Near a school the west home weighs 1.9 times: 1,900 to 1,000 of 290.
        XCTAssertEqual(try grown(with: .school), [290, 200])
        // Near a hospital 1.5 times: 1,500 to 1,000, so 174 and 116.
        XCTAssertEqual(try grown(with: .hospital), [274, 216])
        // A night market draws no homes.
        XCTAssertEqual(try grown(with: .nightMarket), [245, 245])
    }

    func testTheWeightsAreUntouchedWithoutASchoolOrAHospital() throws {
        let (world, _) = try growingWorld(with: nil)
        XCTAssertEqual(world.civicGrowthWeights([3, 1], of: [0, 1]), [3, 1])
        let (school, _) = try growingWorld(with: .school)
        XCTAssertEqual(school.civicGrowthWeights([3, 1], of: [0, 1]), [57, 10])
    }

    // MARK: - Night markets

    func testANightMarketIsATwoAndAHalfStarSightItsStationServes() throws {
        var world = try world()
        let far = try world.placeBuilding(.nightMarket, at: PlanPoint(x: 100_000, y: 10_000))
        XCTAssertEqual(world.subsidiaryCustomers(of: far, onDay: 0), 0, "no station within 800 m")
        let market = try world.placeBuilding(.nightMarket, at: PlanPoint(x: 31_000, y: 26_768), look: 1)
        let sight = try XCTUnwrap(world.companySight(of: market.id))
        XCTAssertEqual(world.stars(of: sight), 250)
        XCTAssertEqual(sight.englishName, "Night market")
        XCTAssertNil(world.attraction(id: sight.id), "never an attraction of its own")
        // 2.5 stars: 800 + 1,200 / 2 = 1,400 potential, a Monday:
        // 1,400 × 0.6 × 0.2 = 168.
        XCTAssertEqual(world.subsidiaryCustomers(of: market, onDay: 0), 168)
        let day = world.subsidiaryDay(of: market, onDay: 0)
        XCTAssertEqual(day.sales, Money(168 * SubsidiaryRules.nightMarketSpend))
        let staff = (market.cost.amount * SubsidiaryRules.staffBasisPoints + 9_999) / 10_000
        XCTAssertEqual(day.cost, Money(168 * SubsidiaryRules.nightMarketSpend * SubsidiaryRules.nightMarketVariableCostPercent / 100 + staff))
        // A temple beside it does not share its visitors; a second night
        // market within 800 m does: 84 each.
        let temple = try world.placeBuilding(.temple, at: PlanPoint(x: 35_000, y: 26_768))
        XCTAssertEqual(world.subsidiaryCustomers(of: market, onDay: 0), 168)
        XCTAssertEqual(world.subsidiaryCustomers(of: temple, onDay: 0), 96)
        let second = try world.placeBuilding(.nightMarket, at: PlanPoint(x: 31_000, y: 38_768))
        XCTAssertEqual(world.subsidiaryCustomers(of: market, onDay: 0), 84)
        XCTAssertEqual(world.subsidiaryCustomers(of: second, onDay: 0), 84)
    }

    func testANightMarketsVisitorsComeByTrainAndAreCounted() throws {
        var world = try world()
        let market = try world.placeBuilding(.nightMarket, at: PlanPoint(x: 31_000, y: 26_768))
        // The visitors ride from Home to Foot, the night market's station.
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 168)
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        let counted = try XCTUnwrap(world.placedBuilding(id: market.id))
        XCTAssertEqual(counted.visitors, 168)
        XCTAssertEqual(world.subsidiaryCustomers(of: counted, onDay: 0), counted.visitors, "yesterday as counted")
    }

    /// A night market built in a running game changes the trips at once,
    /// as in the same game loaded from a save.
    func testANightMarketBuiltMidDayRunsAsIfLoaded() throws {
        var world = try world()
        world.setSpeed(.normal)
        try world.advance(ticks: 60)
        try world.placeBuilding(.nightMarket, at: PlanPoint(x: 31_000, y: 26_768))
        var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        var running = world
        try running.advance(ticks: 300)
        try loaded.advance(ticks: 300)
        XCTAssertEqual(running, loaded)
    }

    // MARK: - Saving

    func testTheNewKindsRoundTripAndAreChecked() throws {
        var world = try world()
        try world.placeBuilding(.school, at: PlanPoint(x: 20_000, y: 10_000), look: 1)
        try world.placeBuilding(.hospital, at: PlanPoint(x: 26_000, y: 10_000))
        try world.placeBuilding(.nightMarket, at: PlanPoint(x: 31_000, y: 26_768), look: 1)
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        func edited(_ change: (inout [[String: Any]]) -> Void) throws -> Data {
            var save = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            var saved = try XCTUnwrap(save["world"] as? [String: Any])
            var buildings = try XCTUnwrap(saved["placedBuildings"] as? [[String: Any]])
            change(&buildings)
            saved["placedBuildings"] = buildings
            save["world"] = saved
            return try JSONSerialization.data(withJSONObject: save)
        }
        let written = try XCTUnwrap(((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["world"] as? [String: Any])?["placedBuildings"] as? [[String: Any]])
        XCTAssertEqual(written.map { $0["kind"] as? String }, ["school", "hospital", "nightMarket"])
        XCTAssertNil(written[0]["visitors"])
        XCTAssertNotNil(written[2]["visitors"])
        // A look its kind lacks, or a school with visitors, is refused.
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[1]["look"] = 2 }))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[0]["visitors"] = 3 }))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[2]["visitors"] = -1 }))
    }

    /// Decision 361's sequel: a version 74 save keeps the company's
    /// schools, hospitals and night markets, their looks and a night
    /// market's counted visitors. Written with
    /// `SCHOOL_HOSPITAL_MARKET_SAVE_NEW=1`, as the save was first made.
    func testVersionSeventyFourKeepsSchoolsHospitalsAndNightMarkets() throws {
        var world = try world()
        try world.placeBuilding(.school, at: PlanPoint(x: 20_000, y: 10_000), look: 1)
        try world.placeBuilding(.hospital, at: PlanPoint(x: 26_000, y: 10_000), look: 1)
        try world.placeBuilding(.nightMarket, at: PlanPoint(x: 31_000, y: 26_768), look: 1)
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)

        let url = SavedGameTests.fixtures.appendingPathComponent("v74-school-hospital-night-market.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["SCHOOL_HOSPITAL_MARKET_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 74)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.placedBuildings.map(\.kind), [.school, .hospital, .nightMarket])
        XCTAssertEqual(loaded.placedBuildings.map(\.look), [1, 1, 1])
        XCTAssertEqual(loaded.placedBuildings[2].visitors, 168)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 74,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
