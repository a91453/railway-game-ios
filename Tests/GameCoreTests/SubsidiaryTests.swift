import Foundation
@testable import GameCore
import XCTest

/// Subsidiary businesses (ARCHITECTURE decision 173): a department store, a
/// hotel and an amusement park take in what the passengers of the stations
/// within 800 m spend, and keep their own books.
///
/// Expected values are worked out by hand from the rule and written out,
/// never taken from a previous run.
final class SubsidiaryTests: XCTestCase {
    // As DoorCrowdingTests: Alpha, Beta and Gamma a tile apart on a line.
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let one = TrainID(rawValue: 1)

    /// A managed world with the line Main (Alpha to Gamma, one train in
    /// service) and demand at Alpha of `alphaKind` and 1,000 trips a day.
    private func makeWorld(alphaKind: StationDemandKind = .shopping, trips: Int64 = 1_000, managed: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 32_768, height: 32_768), economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .x10)
        )
        if managed { world.setEconomyMode(.management) }
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(one, to: main)
        try world.setStationDemand(alpha, to: StationDemand(kind: alphaKind, dailyTrips: trips))
        try world.setStationDemand(gamma, to: StationDemand(kind: .office, dailyTrips: 0))
        return world
    }

    /// 1,000 less 1,000 d² ÷ R², rounded down, of a point `dx` east and `dy` south of a station.
    private func weight(_ dx: Int64, _ dy: Int64) -> Int64 {
        1_000 - 1_000 * (dx * dx + dy * dy) / (SubsidiaryRules.reach * SubsidiaryRules.reach)
    }

    /// Puts `kind` `dx` east and `dy` south of Alpha (which stands at
    /// (1,536, 512), north of the track at y = 1,536).
    @discardableResult
    private func place(_ kind: PlacedBuildingKind, _ dx: Int64, _ dy: Int64, in world: inout GameWorld) throws -> PlacedBuilding {
        let point = try XCTUnwrap(world.station(id: alpha)?.point)
        return try world.placeBuilding(kind, at: PlanPoint(x: point.x + dx, y: point.y + dy))
    }

    // MARK: - The kinds

    func testTheNewKindsHaveTheirSizesStoreysAndUses() {
        XCTAssertEqual(PlacedBuildingKind.departmentStore.side, 3_072)
        XCTAssertEqual(PlacedBuildingKind.hotel.side, 2_048)
        XCTAssertEqual(PlacedBuildingKind.amusementPark.side, 7_168)
        XCTAssertEqual(PlacedBuildingKind.departmentStore.floors, 8)
        XCTAssertEqual(PlacedBuildingKind.hotel.floors, 14)
        XCTAssertEqual(PlacedBuildingKind.amusementPark.floors, 1)
        XCTAssertEqual(PlacedBuildingKind.departmentStore.use, .commercial)
        XCTAssertEqual(PlacedBuildingKind.hotel.use, .commercial)
        XCTAssertEqual(PlacedBuildingKind.amusementPark.use, .leisure)
        // 48 m × 48 m × 8 storeys at $40 a m².
        XCTAssertEqual(PlacedBuildingKind.departmentStore.floorArea, 18_432)
        XCTAssertEqual(PlacedBuildingKind.allCases.filter(\.isSubsidiary), [.departmentStore, .hotel, .amusementPark])
    }

    // MARK: - A day's trade

    /// 1,000 trips at Alpha, a shopping station: 1,000 × 60‰ × 1.5 × the
    /// weight of 3,200 units (997) = 89.7, 89 customers at $18.
    func testADepartmentStoreTakesItsShareOfTheStationsTrips() throws {
        var world = try makeWorld()
        let store = try place(.departmentStore, 0, 3_200, in: &world)
        XCTAssertEqual(weight(0, 3_200), 997)
        XCTAssertEqual(world.subsidiaryCustomers(of: store, onDay: 0), 89)
        let day = world.subsidiaryDay(of: store, onDay: 0)
        XCTAssertEqual(day.sales, Money(89 * 1_800))
        // 65 % of the sales, and 0.04 % of what it cost, rounded up.
        let staff = (store.cost.amount * 4 + 9_999) / 10_000
        XCTAssertEqual(day.cost, Money(89 * 1_800 * 65 / 100 + staff))
    }

    /// A trade that is not shopping counts one tenth less: an office
    /// station's 1,000 trips make 1,000 × 60‰ × 997 = 59.8, 59 customers.
    func testAShoppingStationDrawsOneAndAHalfTimesTheTrips() throws {
        var world = try makeWorld(alphaKind: .office)
        let store = try place(.departmentStore, 0, 3_200, in: &world)
        XCTAssertEqual(world.subsidiaryCustomers(of: store, onDay: 0), 59)
    }

    /// A hotel takes 10‰ of a scenic station's 2,000 trips at a weight of 999: 19.98.
    /// Without a sight or an intercity station it takes nobody.
    func testAHotelTakesTheScenicTrips() throws {
        var scenic = try makeWorld(alphaKind: .scenic, trips: 2_000)
        let hotel = try place(.hotel, 0, 2_200, in: &scenic)
        XCTAssertEqual(scenic.subsidiaryCustomers(of: hotel, onDay: 0), 19)
        XCTAssertEqual(scenic.subsidiaryDay(of: hotel, onDay: 0).sales, Money(19 * 8_500))
        var homes = try makeWorld(alphaKind: .residential, trips: 2_000)
        let empty = try place(.hotel, 0, 2_200, in: &homes)
        XCTAssertEqual(homes.subsidiaryCustomers(of: empty, onDay: 0), 0)
    }

    /// An amusement park takes 40‰ of all the trips in reach, 1,000 × 40‰ ×
    /// 987 = 39.5, and 5‰ of the other stops of the line (Gamma has none).
    func testAnAmusementParkTakesAllTheTripsInReach() throws {
        var world = try makeWorld(alphaKind: .residential)
        let park = try place(.amusementPark, 3_600, 4_800, in: &world)
        XCTAssertEqual(weight(3_600, 4_800), 987)
        // 1,000 × 40 × 10 × 987 = 394,800,000 → 39.
        XCTAssertEqual(world.subsidiaryCustomers(of: park, onDay: 0), 39)
        try world.setStationDemand(gamma, to: StationDemand(kind: .office, dailyTrips: 0))
    }

    /// A station no train calls at draws no one.
    func testAStationWithNoTrainDrawsNoCustomers() throws {
        var world = try makeWorld()
        let store = try place(.departmentStore, 0, 3_200, in: &world)
        try world.unassignTrain(one)
        XCTAssertEqual(world.subsidiaryCustomers(of: store, onDay: 0), 0)
    }

    /// Two stores within 800 m share the customers.
    func testSubsidiariesOfAKindWithinReachShareTheCustomers() throws {
        var world = try makeWorld()
        let first = try place(.departmentStore, 0, 3_200, in: &world)
        XCTAssertEqual(world.subsidiaryCustomers(of: first, onDay: 0), 89, "alone")
        let second = try place(.departmentStore, 0, 6_400, in: &world)
        let alone = world.subsidiaryCustomers(of: first, onDay: 0)
        let shared = world.subsidiaryCustomers(of: second, onDay: 0)
        // 1,000 × 900 × 997 ÷ 10,000,000 = 89.7 and × 985 = 88.6, each
        // halved: 44.
        XCTAssertEqual(weight(0, 6_400), 985)
        XCTAssertEqual(alone, 44, "the first now shares with the second")
        XCTAssertEqual(shared, 44)
    }

    // MARK: - The books

    func testMidnightBooksTheDayAndWritesALedgerRow() throws {
        var world = try makeWorld()
        let store = try place(.departmentStore, 0, 3_200, in: &world)
        let day = world.subsidiaryDay(of: store, onDay: 0)
        world.settleProperty(day: 0, time: world.clock.now)
        let books = try XCTUnwrap(world.placedBuilding(id: store.id)).books
        XCTAssertEqual(books.thisMonth.sales, day.sales)
        XCTAssertEqual(books.totalCost, day.cost)
        XCTAssertEqual(books.totalProfit, day.sales - day.cost)
        let entry = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailySubsidiary })
        XCTAssertEqual(entry.breakdown, [LedgerLine(item: .subsidiarySales, amount: day.sales), LedgerLine(item: .subsidiaryCost, amount: .zero - day.cost)])
        XCTAssertEqual(entry.amount, day.sales - day.cost)
        // It lets nothing: no rent.
        XCTAssertEqual(world.dailyRent(of: store), .zero)
    }

    func testFreePlayKeepsNoBooks() throws {
        var world = try makeWorld(managed: false)
        let store = try place(.departmentStore, 0, 3_200, in: &world)
        world.settleProperty(day: 0, time: world.clock.now)
        XCTAssertFalse(try XCTUnwrap(world.placedBuilding(id: store.id)).books.hasTraded)
    }

    func testMonthsCloseEveryThirtyDaysAndTwelveAreKept() {
        var books = SubsidiaryBooks()
        books.record(sales: 100, cost: 40, day: 3)
        books.record(sales: 100, cost: 40, day: 29)
        XCTAssertEqual(books.thisMonth, SubsidiaryMonth(sales: 200, cost: 80))
        XCTAssertEqual(books.lastMonth, SubsidiaryMonth())
        books.record(sales: 50, cost: 10, day: 30)
        XCTAssertEqual(books.lastMonth, SubsidiaryMonth(sales: 200, cost: 80))
        XCTAssertEqual(books.thisMonth, SubsidiaryMonth(sales: 50, cost: 10))
        XCTAssertEqual(books.totalProfit, Money(120 + 40))
        XCTAssertEqual(books.trailingProfit, Money(160))
        // A silent stretch closes empty months between.
        books.record(sales: 10, cost: 0, day: 30 * 4)
        XCTAssertEqual(books.closed.map(\.sales), [200, 50, 0, 0])
        // Twelve months are kept, the oldest first dropped.
        for month in 5...20 { books.record(sales: Money(Int64(month)), cost: 0, day: Int64(month) * 30) }
        XCTAssertEqual(books.closed.count, 12)
        XCTAssertEqual(books.closed.last?.sales, 19)
        // The last twelve months: eleven closed and this one.
        XCTAssertEqual(books.trailingProfit, Money((9...19).reduce(0, +) + 20))
    }

    // MARK: - Selling

    /// A sale brings the larger of the property's price and six times the
    /// profit of the last twelve months; a loss-maker's business is worth
    /// nothing.
    func testASaleBringsSixTimesTheYearsProfitWhenThatIsMore() throws {
        var world = try makeWorld()
        let store = try place(.departmentStore, 0, 3_200, in: &world)
        let property = try XCTUnwrap(world.saleQuote(of: store.id))
        XCTAssertEqual(property.businessValue, .zero)
        XCTAssertEqual(property.price, property.propertyPrice)
        let index = try XCTUnwrap(world.placedBuildings.firstIndex { $0.id == store.id })
        world.placedBuildings[index].books.record(sales: 900_000_000, cost: 100_000_000, day: 5)
        let quote = try XCTUnwrap(world.saleQuote(of: store.id))
        XCTAssertEqual(quote.businessValue, Money(6 * 800_000_000))
        XCTAssertEqual(quote.price, Money(4_800_000_000))
        let before = world.economy.balance
        try world.sellPlacedBuilding(store.id)
        XCTAssertEqual(world.economy.balance, before + Money(4_800_000_000))
        // A building that lost has no business value.
        var losing = try makeWorld()
        let other = try place(.hotel, 0, 2_200, in: &losing)
        let at = try XCTUnwrap(losing.placedBuildings.firstIndex { $0.id == other.id })
        losing.placedBuildings[at].books.record(sales: 10, cost: 500, day: 1)
        XCTAssertEqual(losing.saleQuote(of: other.id)?.businessValue, .zero)
    }

    // MARK: - Saving

    func testBooksSaveAndTheOldKindsWriteNone() throws {
        var world = try makeWorld()
        let house = try place(.house, 6_000, 3_000, in: &world)
        let store = try place(.departmentStore, 0, 3_200, in: &world)
        world.settleProperty(day: 0, time: world.clock.now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: encoder.encode(SavedGame(world: world)), encoding: .utf8))
        XCTAssertEqual(json.components(separatedBy: "\"books\"").count - 1, 1, "only the store has books")
        let loaded = try JSONDecoder().decode(SavedGame.self, from: Data(json.utf8)).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.placedBuilding(id: house.id)?.books, SubsidiaryBooks())
        XCTAssertEqual(loaded.placedBuilding(id: store.id)?.books, world.placedBuilding(id: store.id)?.books)
    }

    /// Version 46 (decision 173): a department store, a hotel and an
    /// amusement park beside Alpha, one night traded (day 0), and a month
    /// closed by a day in the next. It saves byte for byte and is the world this
    /// build makes.
    func testVersionFortySixKeepsTheSubsidiariesBooks() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v46-subsidiary.json")
        var made = try makeWorld(alphaKind: .scenic, trips: 4_000)
        try place(.departmentStore, 0, 3_200, in: &made)
        try place(.hotel, 0, 8_400, in: &made)
        try place(.amusementPark, 9_000, 4_800, in: &made)
        made.settleProperty(day: 0, time: made.clock.now)
        for index in made.placedBuildings.indices {
            made.placedBuildings[index].books.record(sales: 1_000, cost: 400, day: 31)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["SUBSIDIARY_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 46)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.placedBuildings.map(\.kind), [.departmentStore, .hotel, .amusementPark])
        XCTAssertTrue(world.placedBuildings.allSatisfy { $0.books.hasTraded })
        XCTAssertEqual(world.placedBuildings.map { $0.books.closed.count }, [1, 1, 1])
        XCTAssertEqual(world.accounts.entries.filter { $0.kind == .dailySubsidiary }.count, 1)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 46,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
