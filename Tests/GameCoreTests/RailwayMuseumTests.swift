import Foundation
@testable import GameCore
import XCTest

/// The company's railway museum (decision 684): one a world, a sight as a
/// temple is, rated by the types of train the company has owned, and a
/// subsidiary that takes its visitors' tickets. Every expectation is worked
/// out by hand from the rules.
final class RailwayMuseumTests: XCTestCase {
    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)
    private let site = PlanPoint(x: 31_000, y: 26_768)

    /// `ParksAndTemplesTests`' world: Home and Foot with a train of the
    /// standard car, a 3-star town far from both (so tourism is on), in a
    /// managed company with cash.
    private func world() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: fixtureEconomy(balance: 1_000_000_000_000, costs: testCosts))
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

    // MARK: - The kind

    func testTheKind() {
        let kind = PlacedBuildingKind.railwayMuseum
        XCTAssertEqual(kind.rawValue, "railwayMuseum")
        XCTAssertEqual(kind.side, 4_096)
        XCTAssertEqual(kind.floors, 2)
        XCTAssertEqual(kind.footprintArea, 4_096)
        XCTAssertEqual(kind.floorArea, 8_192)
        XCTAssertEqual(kind.use, .leisure)
        XCTAssertEqual(kind.capacity, BuildingCapacity(residents: 0, jobs: 0))
        XCTAssertEqual(kind.looks, 1)
        XCTAssertFalse(kind.standsOnShore)
        XCTAssertTrue(kind.isSight)
        XCTAssertTrue(kind.isSubsidiary)
    }

    func testTheStarsOfItsExhibits() {
        XCTAssertEqual(Tourism.museumStars(exhibits: 0), 150)
        XCTAssertEqual(Tourism.museumStars(exhibits: 1), 165)
        XCTAssertEqual(Tourism.museumStars(exhibits: 4), 210)
        XCTAssertEqual(Tourism.museumStars(exhibits: 12), 330)
        XCTAssertEqual(Tourism.museumStars(exhibits: 13), 330, "twelve count")
        XCTAssertEqual(Tourism.museumStars(exhibits: -1), 150)
        XCTAssertGreaterThanOrEqual(TrainType.allCases.count, Tourism.exhibitsCounted, "the catalog can fill it")
    }

    // MARK: - Building it

    func testAWorldHasOneMuseumAndTheSecondChangesNothing() throws {
        var world = try world()
        XCTAssertNil(world.railwayMuseum)
        let museum = try world.placeBuilding(.railwayMuseum, at: site)
        XCTAssertEqual(world.railwayMuseum?.id, museum.id)
        // 8,192 m² of floor at NT$120.
        XCTAssertEqual(museum.buildingCost, Money(8_192 * 12_000))
        let before = world
        XCTAssertThrowsError(try world.placeBuilding(.railwayMuseum, at: PlanPoint(x: 64_000, y: 10_000))) {
            XCTAssertEqual($0 as? GameError, .museumAlreadyBuilt(museum.id))
        }
        XCTAssertEqual(world, before, "a refused command changes nothing")
        XCTAssertThrowsError(try world.buildingPlacement(.railwayMuseum, at: PlanPoint(x: 64_000, y: 10_000))) {
            XCTAssertEqual($0 as? GameError, .museumAlreadyBuilt(museum.id))
        }
        // The look is asked first, as of every kind.
        XCTAssertThrowsError(try world.placeBuilding(.railwayMuseum, at: PlanPoint(x: 64_000, y: 10_000), look: 1)) {
            XCTAssertEqual($0 as? GameError, .invalidBuildingLook)
        }
        // Sold to the city, the company can build another.
        try world.sellPlacedBuilding(museum.id)
        XCTAssertNil(world.railwayMuseum)
        XCTAssertNoThrow(try world.placeBuilding(.railwayMuseum, at: PlanPoint(x: 64_000, y: 10_000)))
    }

    // MARK: - Exhibits

    func testItShowsTheTypesTheCompanyOwnsWhenBuilt() throws {
        var world = try world()
        XCTAssertEqual(world.ownedTrainTypes(), [], "a train of the standard car is of no type")
        try world.purchaseTrain(named: "B1", as: .b)
        try world.purchaseTrain(named: "A1", as: .a)
        try world.purchaseTrain(named: "A2", as: .a)
        XCTAssertEqual(world.ownedTrainTypes(), [.a, .b], "each once, in the catalog's order")
        let museum = try world.placeBuilding(.railwayMuseum, at: site)
        XCTAssertEqual(museum.exhibits, [.a, .b])
        let sight = try XCTUnwrap(world.companySight(of: museum.id))
        XCTAssertEqual(sight.englishName, "Railway museum")
        XCTAssertEqual(sight.name, "鐵道博物館")
        XCTAssertEqual(world.stars(of: sight), 180)
        XCTAssertNil(world.attraction(id: sight.id), "never an attraction of its own")
        // The other kinds have none.
        XCTAssertEqual(try world.placeBuilding(.temple, at: PlanPoint(x: 64_000, y: 10_000)).exhibits, [])
    }

    func testATypeBoughtLaterGoesOnShowAtMidnightAndStaysWhenSold() throws {
        var world = try world()
        let museum = try world.placeBuilding(.railwayMuseum, at: site)
        XCTAssertEqual(museum.exhibits, [])
        let train = try world.purchaseTrain(named: "C1", as: .c)
        XCTAssertEqual(world.railwayMuseum?.exhibits, [], "not before midnight")
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        XCTAssertEqual(world.railwayMuseum?.exhibits, [.c])
        XCTAssertEqual(world.railwayMuseum?.visitors, 66, "counted at the rating they came for")
        try world.sellTrain(train.id)
        try world.purchaseTrain(named: "A1", as: .a)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.railwayMuseum?.exhibits, [.a, .c], "the sold type stays")
        let sight = try XCTUnwrap(world.companySight(of: museum.id))
        XCTAssertEqual(world.stars(of: sight), 180)
    }

    // MARK: - Visitors and money

    func testItsVisitorsAreItsCustomersAndBuyTickets() throws {
        var world = try world()
        let far = try world.placeBuilding(.railwayMuseum, at: PlanPoint(x: 100_000, y: 10_000))
        XCTAssertEqual(world.subsidiaryCustomers(of: far, onDay: 0), 0, "no station within 800 m")
        XCTAssertEqual(world.companySightStatus(of: far.id), .noStation)
        try world.sellPlacedBuilding(far.id)
        let museum = try world.placeBuilding(.railwayMuseum, at: site)
        XCTAssertEqual(world.companySightStatus(of: museum.id), .ok)
        XCTAssertEqual(world.servingStationID(of: try XCTUnwrap(world.companySight(of: museum.id))), foot)
        // 1.5 stars: 300 + 500 / 2 = 550 potential, a Monday:
        // 550 × 0.6 × 0.2 = 66.
        XCTAssertEqual(world.subsidiaryCustomers(of: museum, onDay: 0), 66)
        let day = world.subsidiaryDay(of: museum, onDay: 0)
        XCTAssertEqual(day.sales, Money(66 * 15_000))
        let staff = (museum.cost.amount * 4 + 9_999) / 10_000
        XCTAssertEqual(day.cost, Money(66 * 15_000 * 50 / 100 + staff))
        // Its visitors ride from Home to Foot, its station.
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 66)
        // A temple or a night market beside it does not share them.
        let temple = try world.placeBuilding(.temple, at: PlanPoint(x: 35_000, y: 26_768))
        XCTAssertEqual(world.subsidiaryCustomers(of: museum, onDay: 0), 66)
        XCTAssertEqual(world.subsidiaryCustomers(of: temple, onDay: 0), 96)
    }

    func testMoreExhibitsDrawMoreVisitors() throws {
        var world = try world()
        for (index, type) in [TrainType.a, .b, .c, .l].enumerated() { try world.purchaseTrain(named: "X\(index)", as: type) }
        let museum = try world.placeBuilding(.railwayMuseum, at: site)
        // 2.1 stars: 800 + 1,200 / 10 = 920 potential: 110 on a Monday.
        XCTAssertEqual(world.subsidiaryCustomers(of: museum, onDay: 0), 110)
        // Saturday, day 5: 920 × 1.6 × 0.2 = 294.
        XCTAssertEqual(world.subsidiaryCustomers(of: museum, onDay: 5), 294)
        // Each exhibit that counts is kept for NT$1,000 a day.
        let staff = (museum.cost.amount * 4 + 9_999) / 10_000
        XCTAssertEqual(world.subsidiaryDay(of: museum, onDay: 0).cost, Money(110 * 15_000 / 2 + staff + 4 * 100_000))
    }

    func testItsDayIsOnTheSubsidiaryLedgerRow() throws {
        var world = try world()
        let museum = try world.placeBuilding(.railwayMuseum, at: site)
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        let counted = try XCTUnwrap(world.railwayMuseum)
        XCTAssertEqual(counted.visitors, 66)
        XCTAssertEqual(world.subsidiaryCustomers(of: counted, onDay: 0), 66, "yesterday as counted")
        let staff = (museum.cost.amount * 4 + 9_999) / 10_000
        XCTAssertEqual(counted.books.totalSales, Money(66 * 15_000))
        XCTAssertEqual(counted.books.totalCost, Money(66 * 15_000 / 2 + staff))
        let row = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailySubsidiary })
        XCTAssertEqual(row.amount, counted.books.totalSales - counted.books.totalCost)
    }

    /// A museum built in a running game changes the trips at once, as in
    /// the same game loaded from a save.
    func testAMuseumBuiltMidDayRunsAsIfLoaded() throws {
        var world = try world()
        try world.purchaseTrain(named: "A1", as: .a)
        world.setSpeed(.normal)
        try world.advance(ticks: 60)
        try world.placeBuilding(.railwayMuseum, at: site)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        var running = world
        try running.advance(ticks: 3_000)
        try loaded.advance(ticks: 3_000)
        XCTAssertEqual(running, loaded)
    }

    /// A world without a museum runs as it did: buying a typed train keeps
    /// no exhibits anywhere.
    func testWithoutAMuseumNothingIsKept() throws {
        var world = try world()
        try world.placeBuilding(.temple, at: site)
        try world.purchaseTrain(named: "A1", as: .a)
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        XCTAssertTrue(world.placedBuildings.allSatisfy(\.exhibits.isEmpty))
    }

    // MARK: - Saving

    func testItRoundTripsAndIsChecked() throws {
        var world = try world()
        try world.purchaseTrain(named: "A1", as: .a)
        try world.purchaseTrain(named: "B1", as: .b)
        try world.placeBuilding(.temple, at: PlanPoint(x: 64_000, y: 10_000))
        try world.placeBuilding(.railwayMuseum, at: site)
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
        let save = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(save["saveVersion"] as? Int, 87)
        let written = try XCTUnwrap((save["world"] as? [String: Any])?["placedBuildings"] as? [[String: Any]])
        XCTAssertEqual(written.map { $0["kind"] as? String }, ["temple", "railwayMuseum"])
        XCTAssertNil(written[0]["exhibits"])
        XCTAssertEqual(written[1]["exhibits"] as? [String], ["A", "B"])
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: edited { _ in }))
        // Exhibits anywhere but in a museum, out of the catalog's order,
        // twice or of no type the catalog has, and a second museum, are
        // refused.
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[0]["exhibits"] = ["A"] }))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[1]["exhibits"] = ["B", "A"] }))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[1]["exhibits"] = ["A", "A"] }))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[1]["exhibits"] = ["NO SUCH TYPE"] }))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited { $0[1]["visitors"] = -1 }))
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: edited {
            $0[0]["kind"] = "railwayMuseum"
            $0[0]["visitors"] = 0
        }))
    }

    /// Decision 684: a version 87 save keeps the company's railway museum,
    /// its exhibits and its counted visitors. Written with
    /// `RAILWAY_MUSEUM_SAVE_NEW=1`, as the save was first made.
    func testVersionEightySevenKeepsTheMuseum() throws {
        var world = try world()
        try world.purchaseTrain(named: "A1", as: .a)
        try world.purchaseTrain(named: "E1", as: .emu3000)
        try world.placeBuilding(.railwayMuseum, at: site)
        try world.purchaseTrain(named: "S1", as: .steam)
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)

        let url = SavedGameTests.fixtures.appendingPathComponent("v87-railway-museum.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["RAILWAY_MUSEUM_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 87)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        let museum = try XCTUnwrap(loaded.railwayMuseum)
        XCTAssertEqual(museum.exhibits.map(\.rawValue), ["A", "STEAM", "EMU3000"].sorted { TrainType(rawValue: $0)!.row < TrainType(rawValue: $1)!.row })
        XCTAssertEqual(museum.exhibits.count, 3)
        // Two exhibits on day 0: 1.8 stars, 700 × 0.6 × 0.2 = 84.
        XCTAssertEqual(museum.visitors, 84)
        XCTAssertTrue(museum.books.hasTraded)
        XCTAssertEqual(loaded.stars(of: try XCTUnwrap(loaded.companySight(of: museum.id))), 195)
        // It runs on as the game it was saved from.
        try loaded.advance(ticks: 1_440)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(loaded.railwayMuseum?.visitors, world.railwayMuseum?.visitors)
        XCTAssertEqual(loaded.economy.balance, world.economy.balance)
    }
}
