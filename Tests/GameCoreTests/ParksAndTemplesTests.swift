import Foundation
@testable import GameCore
import XCTest

/// The company's parks and temples (decision 361): a park raises the land
/// round it as a city park does, a temple is a 2-star sight whose visitors
/// are its customers, and each kind's look is kept. Every expectation is
/// worked out by hand from the rules.
final class ParksAndTemplesTests: XCTestCase {
    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)

    /// `TourismHotelTests`' world: Home and Foot with a train, a 3-star town
    /// far from both (so tourism is on), in a managed company with cash.
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

    // MARK: - Looks

    func testEachKindHasItsLooks() throws {
        XCTAssertEqual(PlacedBuildingKind.allCases.map(\.looks), [1, 1, 1, 1, 1, 2, 3, 1, 3, 2, 2, 2, 2])
        var world = try world()
        XCTAssertThrowsError(try world.placeBuilding(.park, at: PlanPoint(x: 20_000, y: 10_000), look: 3)) {
            XCTAssertEqual($0 as? GameError, .invalidBuildingLook)
        }
        XCTAssertThrowsError(try world.placeBuilding(.house, at: PlanPoint(x: 20_000, y: 10_000), look: 1)) {
            XCTAssertEqual($0 as? GameError, .invalidBuildingLook)
        }
        XCTAssertThrowsError(try world.placeBuilding(.temple, at: PlanPoint(x: 20_000, y: 10_000), look: -1))
        XCTAssertTrue(world.placedBuildings.isEmpty, "nothing changes")
        let park = try world.placeBuilding(.park, at: PlanPoint(x: 20_000, y: 10_000), look: 2)
        XCTAssertEqual(park.look, 2)
        XCTAssertEqual(world.placedBuilding(id: park.id)?.look, 2)
    }

    // MARK: - Parks

    func testAParkHoldsNoOneAndRaisesTheLandRoundIt() throws {
        var world = try world()
        XCTAssertEqual(PlacedBuildingKind.park.capacity, BuildingCapacity(residents: 0, jobs: 0))
        // Row 2, column 5 has its middle at (22,528, 10,240).
        XCTAssertEqual(world.landValue(row: 2, column: 5)?.parkPremium, 0)
        let park = try world.placeBuilding(.park, at: PlanPoint(x: 20_000, y: 10_000))
        XCTAssertEqual(world.dailyRent(of: park), .zero)
        XCTAssertEqual(world.landValue(row: 2, column: 5)?.parkPremium, 600)
        // 400 m is 25,600 units: six cells east of the park's (20,000 →
        // 45,056, 25,056 off) is within, seven (49,152, 29,152) is not.
        XCTAssertEqual(world.landValue(row: 2, column: 10)?.parkPremium, 600)
        XCTAssertEqual(world.landValue(row: 2, column: 11)?.parkPremium, 0)
    }

    func testAHouseBesideAParkLetsForMore() throws {
        var world = try world()
        let house = try world.placeBuilding(.house, at: PlanPoint(x: 20_000, y: 16_000))
        // Rent is by the land value under the house's centre (V in
        // ``GameWorld/dailyRent(of:)``): 1,000 bare, 1,600 near a park.
        let under = { (world: GameWorld) in world.landValue(row: Land.cellIndex(house.centre.y), column: Land.cellIndex(house.centre.x))?.value }
        XCTAssertEqual(under(world), 1_000)
        try world.placeBuilding(.park, at: PlanPoint(x: 20_000, y: 10_000))
        XCTAssertEqual(under(world), 1_600)
    }

    // MARK: - Temples

    func testATempleIsATwoStarSightItsStationServes() throws {
        var world = try world()
        let far = try world.placeBuilding(.temple, at: PlanPoint(x: 100_000, y: 10_000))
        XCTAssertEqual(world.subsidiaryCustomers(of: far, onDay: 0), 0, "no station within 800 m")
        let temple = try world.placeBuilding(.temple, at: PlanPoint(x: 31_000, y: 26_768), look: 1)
        let sight = try XCTUnwrap(world.companySight(of: temple.id))
        XCTAssertEqual(world.stars(of: sight), 200)
        XCTAssertNil(world.attraction(id: sight.id), "never an attraction of its own")
        XCTAssertEqual(world.tourism?.attractions.count, 1)
        // 2 stars: 800 potential, a Monday: 800 × 0.6 × 0.2 = 96.
        XCTAssertEqual(world.subsidiaryCustomers(of: temple, onDay: 0), 96)
        let day = world.subsidiaryDay(of: temple, onDay: 0)
        XCTAssertEqual(day.sales, Money(96 * SubsidiaryRules.templeSpend))
        let staff = (temple.cost.amount * SubsidiaryRules.staffBasisPoints + 9_999) / 10_000
        XCTAssertEqual(day.cost, Money(96 * SubsidiaryRules.templeSpend * SubsidiaryRules.templeVariableCostPercent / 100 + staff))
        // A second temple within 800 m shares them: 48 each.
        let second = try world.placeBuilding(.temple, at: PlanPoint(x: 35_000, y: 26_768))
        XCTAssertEqual(world.subsidiaryCustomers(of: temple, onDay: 0), 48)
        XCTAssertEqual(world.subsidiaryCustomers(of: second, onDay: 0), 48)
    }

    func testATempleDrawsNothingWithoutTourism() throws {
        var world = try world()
        let temple = try world.placeBuilding(.temple, at: PlanPoint(x: 31_000, y: 26_768))
        world.setTourism(nil)
        XCTAssertNil(world.companySight(of: temple.id))
        XCTAssertEqual(world.subsidiaryCustomers(of: temple, onDay: 0), 0)
    }

    func testATemplesVisitorsComeByTrainAndAreCounted() throws {
        var world = try world()
        let temple = try world.placeBuilding(.temple, at: PlanPoint(x: 31_000, y: 26_768))
        // The tourists ride from Home to Foot, the temple's station.
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 96)
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        let counted = try XCTUnwrap(world.placedBuilding(id: temple.id))
        XCTAssertEqual(counted.visitors, 96)
        XCTAssertEqual(world.subsidiaryCustomers(of: counted, onDay: 0), counted.visitors, "yesterday as counted")
        XCTAssertNil(world.tourism?.attractions.first { $0.id.rawValue < 0 })
    }

    /// A temple built or sold in a running game changes the trips at once,
    /// as in the same game loaded from a save (the plan worked out before
    /// is not kept).
    func testATempleBuiltOrSoldMidDayRunsAsIfLoaded() throws {
        var world = try world()
        world.setSpeed(.normal)
        try world.advance(ticks: 60)
        func continuesAsLoaded(_ label: String) throws {
            var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
            var running = world
            try running.advance(ticks: 300)
            try loaded.advance(ticks: 300)
            XCTAssertEqual(running, loaded, label)
        }
        let temple = try world.placeBuilding(.temple, at: PlanPoint(x: 31_000, y: 26_768))
        try continuesAsLoaded("built")
        try world.advance(ticks: 60)
        try world.sellPlacedBuilding(temple.id)
        try continuesAsLoaded("sold")
    }

    // MARK: - Saving

    func testParksAndTemplesRoundTripAndOldBuildingsHaveTheFirstLook() throws {
        var world = try world()
        try world.placeBuilding(.park, at: PlanPoint(x: 20_000, y: 10_000), look: 1)
        try world.placeBuilding(.house, at: PlanPoint(x: 20_000, y: 16_000))
        try world.placeBuilding(.temple, at: PlanPoint(x: 31_000, y: 26_768), look: 1)
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
        let buildings = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["world"] as? [String: Any])
        let written = try XCTUnwrap(buildings["placedBuildings"] as? [[String: Any]])
        XCTAssertEqual(written.map { $0["look"] as? Int }, [1, nil, 1], "a first look is not written")
        XCTAssertNil(written[0]["visitors"])
        XCTAssertNotNil(written[2]["visitors"])
        // Without "look" a building has its kind's first, as every old one did.
        let old = try JSONDecoder().decode(SavedGame.self, from: edited { $0[0]["look"] = nil }).world
        XCTAssertEqual(old.placedBuildings[0].look, 0)
        // A look its kind lacks, or a park with visitors, is refused.
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[0]["look"] = 3 }))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[1]["look"] = 1 }))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[0]["visitors"] = 3 }))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[2]["visitors"] = -1 }))
    }

    /// Decision 361: a version 71 save keeps the company's parks and
    /// temples, their looks and a temple's counted visitors. Written with
    /// `PARK_TEMPLE_SAVE_NEW=1`, as the save was first made.
    func testVersionSeventyOneKeepsParksAndTemples() throws {
        var world = try world()
        try world.placeBuilding(.park, at: PlanPoint(x: 20_000, y: 10_000), look: 2)
        try world.placeBuilding(.temple, at: PlanPoint(x: 31_000, y: 26_768), look: 1)
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)

        let url = SavedGameTests.fixtures.appendingPathComponent("v71-park-temple.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["PARK_TEMPLE_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 71)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.placedBuildings.map(\.kind), [.park, .temple])
        XCTAssertEqual(loaded.placedBuildings.map(\.look), [2, 1])
        XCTAssertGreaterThan(loaded.placedBuildings[1].visitors, 0)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 71,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
