import Foundation
@testable import GameCore
import XCTest

/// Day passes (ARCHITECTURE decision 324). Every expectation is worked out
/// by hand from the rules.
final class DayPassTests: XCTestCase {
    // MARK: - The rules

    func testHalfTheTouristsBuyUpToHalfTheValueThenFewerToNoneAtIt() {
        let value = Money(2_000)
        XCTAssertEqual(DayPass.uptake(price: Money(500), value: value), 500)
        XCTAssertEqual(DayPass.uptake(price: Money(1_000), value: value), 500, "half the value")
        XCTAssertEqual(DayPass.uptake(price: Money(1_500), value: value), 250)
        XCTAssertEqual(DayPass.uptake(price: Money(1_900), value: value), 50)
        XCTAssertEqual(DayPass.uptake(price: Money(2_000), value: value), 0, "worth no more than its rides")
        XCTAssertEqual(DayPass.uptake(price: Money(3_000), value: value), 0)
        XCTAssertEqual(DayPass.uptake(price: Money(100), value: .zero), 0, "no rides, no buyers")
    }

    func testTheSuggestedPriceIsThreeShortestFares() {
        XCTAssertEqual(DayPass.suggestedPrice(for: .standard), Money(1_500))
        XCTAssertEqual(DayPass.suggestedPrice(for: .distance(FareRules.standardBands)), Money(165))
        XCTAssertEqual(DayPass.suggestedPrice(for: .flat(.zero)), Money(1_500), "a fare of 0 is charged as 5")
    }

    // MARK: - A world

    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2), peak = StationID(rawValue: 3)
    private let falls = AttractionID(rawValue: 1), temple = AttractionID(rawValue: 2)

    /// Home (1) by the map's edge, an outside connection; Foot (2) and Peak
    /// (3) inland, 470 m apart, each beside a 3-star town; one line through
    /// all three with a train, in a managed company. Every tourist sets out
    /// from Home: 240 to each sight on day 0, a Monday.
    private func world() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 262_144, height: 262_144), economy: GameEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        try world.buildStation(named: "Home", at: PlanPoint(x: 10_000, y: 131_072))
        try world.buildStation(named: "Foot", at: PlanPoint(x: 100_000, y: 131_072))
        try world.buildStation(named: "Peak", at: PlanPoint(x: 130_000, y: 131_072))
        let line = try world.createLine(named: "Main", stops: [home, foot, peak]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 0))
        try world.setStationDemand(foot, to: StationDemand(kind: .scenic, dailyTrips: 0))
        try world.setStationDemand(peak, to: StationDemand(kind: .scenic, dailyTrips: 0))
        world.setOutsideConnections(true)
        world.setTourism([
            Attraction(id: falls, name: "瀑布", englishName: "Falls", point: PlanPoint(x: 101_000, y: 131_072), kind: .town, baseStars: 300),
            Attraction(id: temple, name: "廟", englishName: "Temple", point: PlanPoint(x: 131_000, y: 131_072), kind: .town, baseStars: 300),
        ])
        return world
    }

    func testWithoutAPassNothingChanges() throws {
        let world = try world()
        XCTAssertTrue(world.isOutsideConnection(home))
        XCTAssertFalse(world.isOutsideConnection(foot))
        XCTAssertEqual(world.touristsExpected(at: falls, onDay: 0), 240)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 240)
        XCTAssertEqual(world.dailyDemand(from: foot, to: peak), 0)
        XCTAssertEqual(world.dayPassToday(), DayPassDay())
    }

    /// At $15 the trips are worth $20: $5 there and $5 back (the outside
    /// connection's fare is not the company's), and $5 on to the other
    /// sight and $5 back. A quarter of each sight's 240 buy: 60 and 60.
    func testTouristsBuyByWhatTheRidesAreWorthAndRideOnToTheNextSight() throws {
        var world = try world()
        try world.setDayPass(Money(1_500))
        let passes = world.dayPassToday()
        XCTAssertEqual(passes.sold, 120)
        XCTAssertEqual(passes.sales, Money(180_000))
        XCTAssertEqual(passes.journeyFares, Money(120_000))
        XCTAssertEqual(passes.rides, 240)
        XCTAssertEqual(passes.rideFares, Money(120_000))
        XCTAssertEqual(passes.net, Money(60_000), "$5 a pass more than the trips there and back")
        XCTAssertEqual(passes.visits, [foot: 120, peak: 120])
        // The Falls' 60 ride on to the Temple and back, the Temple's to the
        // Falls and back.
        XCTAssertEqual(world.dailyDemand(from: foot, to: peak), 120)
        XCTAssertEqual(world.dailyDemand(from: peak, to: foot), 120)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 240, "the trips there are the same")

        try world.setDayPass(Money(2_000))
        XCTAssertEqual(world.dayPassToday(), DayPassDay(), "nobody pays what the rides cost")
        XCTAssertEqual(world.dailyDemand(from: foot, to: peak), 0)
        try world.setDayPass(nil)
        XCTAssertEqual(world.dailyDemand(from: foot, to: peak), 0)
    }

    /// A sight with no other to ride on to is worth only the trip there and
    /// back: at $8, $2 under it, a fifth buy, and each costs $2 of fares.
    func testASightAloneIsWorthOnlyTheTripThere() throws {
        var world = try world()
        world.setTourism([Attraction(id: falls, name: "瀑布", englishName: "Falls", point: PlanPoint(x: 101_000, y: 131_072), kind: .town, baseStars: 300)])
        try world.setDayPass(Money(800))
        let passes = world.dayPassToday()
        XCTAssertEqual(passes.sold, 48)
        XCTAssertEqual(passes.rides, 0)
        XCTAssertEqual(passes.net, Money(48 * 800 - 48 * 1_000))
    }

    func testFreePlaySellsNone() throws {
        var world = try world()
        try world.setDayPass(Money(1_500))
        world.setEconomyMode(.free)
        XCTAssertEqual(world.dayPassToday(), DayPassDay())
        XCTAssertEqual(world.dailyDemand(from: foot, to: peak), 0)
    }

    func testThePriceIsWholeDollarsFromOne() throws {
        var world = try world()
        for price in [Money(0), Money(50), Money(1_550), Money(-100), FareRules.maximumFare + Money(100)] {
            XCTAssertThrowsError(try world.setDayPass(price)) { XCTAssertEqual($0 as? GameError, .invalidFareRules) }
        }
        XCTAssertNil(world.accounts.dayPass)
        try world.setDayPass(Money(100))
        XCTAssertEqual(world.accounts.dayPass, Money(100))
    }

    /// The day's passes settle at midnight: their sales in, the fares they
    /// covered (charged as the holders boarded) out.
    func testMidnightSettlesThePassesAsOneRow() throws {
        var world = try world()
        try world.setDayPass(Money(1_500))
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        let row = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailyDayPass })
        XCTAssertEqual(row.breakdown, [
            LedgerLine(item: .dayPassSales, amount: Money(180_000)),
            LedgerLine(item: .dayPassFares, amount: Money(-240_000)),
        ])
        XCTAssertEqual(row.amount, Money(-60_000), "the rides on to the other sight were charged and given back")
        XCTAssertTrue(GameWorld.isWellFormed(row))
        XCTAssertEqual(world.attraction(id: falls)?.yesterday, 300, "240 tourists and 60 from the Temple")
        XCTAssertNil(world.accountsProblem())
    }

    /// A park within reach of Peak and Foot takes a tenth of the pass
    /// holders who visit them, by how near each is, as well as its share of
    /// the stations' trips.
    func testAParkNearASightTakesInPassHolders() throws {
        var world = try world()
        let park = try world.placeBuilding(.amusementPark, at: PlanPoint(x: 130_000, y: 131_072 + 6_000))
        let without = world.subsidiaryCustomers(of: park, onDay: 0)
        try world.setDayPass(Money(1_500))
        let with = world.subsidiaryCustomers(of: park, onDay: 0)
        let weights = [Int64(130_000), 100_000].map { x -> Int64 in
            let dx = park.centre.x - x, dy = park.centre.y - 131_072
            return 1_000 - 1_000 * (dx * dx + dy * dy) / (SubsidiaryRules.reach * SubsidiaryRules.reach)
        }
        XCTAssertTrue(weights.allSatisfy { $0 > 0 }, "both stations are within reach")
        XCTAssertEqual(with - without, 120 * DayPass.parkCapture * weights.reduce(0, +) / 1_000_000)
        XCTAssertGreaterThan(with, without)
    }

    // MARK: - Saving

    func testThePassSavesAndLoads() throws {
        var world = try world()
        try world.setDayPass(Money(1_500))
        let data = try JSONEncoder().encode(world)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"dayPass\":1500"))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        try world.setDayPass(nil)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(world), as: UTF8.self).contains("dayPass"), "none on sale writes nothing")
    }

    /// One-star sights, so the save keeps few passengers on the way.
    func testVersionSixtyEightKeepsThePass() throws {
        var world = try world()
        world.setTourism([
            Attraction(id: falls, name: "瀑布", englishName: "Falls", point: PlanPoint(x: 101_000, y: 131_072), kind: .town, baseStars: 100),
            Attraction(id: temple, name: "廟", englishName: "Temple", point: PlanPoint(x: 131_000, y: 131_072), kind: .town, baseStars: 100),
        ])
        try world.setDayPass(Money(1_500))
        world.setSpeed(.normal)
        try world.advance(ticks: 1_450)

        let url = SavedGameTests.fixtures.appendingPathComponent("v68-day-pass.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["DAY_PASS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 68)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.accounts.dayPass, Money(1_500))
        XCTAssertTrue(loaded.accounts.entries.contains { $0.kind == .dailyDayPass })
    }
}
