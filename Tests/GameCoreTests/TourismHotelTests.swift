import Foundation
@testable import GameCore
import XCTest

/// The hotels beside a sight (ARCHITECTURE decision 174, a later fix): each
/// within 800 m adds a quarter star (two count), and a share of the
/// tourists stay in them, as the customers of decision 173's hotel. Every
/// expectation is worked out by hand from the rules.
final class TourismHotelTests: XCTestCase {
    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2)
    private let sight = AttractionID(rawValue: 1)

    /// `TourismTests`' world: Home and Foot with a train, a 3-star town 15.6 m
    /// from Foot, in a managed company with cash enough for hotels.
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
        world.setTourism([Attraction(id: sight, name: "x", englishName: "x", point: PlanPoint(x: 31_000, y: 32_768), kind: .town, baseStars: 300)])
        return world
    }

    /// A hotel `dx` units east of the sight (a hotel is 2,048 units a side).
    @discardableResult
    private func hotel(_ world: inout GameWorld, dx: Int64) throws -> PlacedBuilding {
        try world.placeBuilding(.hotel, at: PlanPoint(x: 31_000 + dx, y: 32_768 - 6_000))
    }

    func testAHotelWithinEightHundredMetresAddsAQuarterStar() throws {
        var world = try world()
        let attraction = try XCTUnwrap(world.attraction(id: sight))
        XCTAssertEqual(world.stars(of: attraction), 300)
        try hotel(&world, dx: 0)
        XCTAssertEqual(world.hotelsNear(attraction), 1)
        XCTAssertEqual(world.stars(of: attraction), 325)
        try hotel(&world, dx: 4_000)
        XCTAssertEqual(world.stars(of: attraction), 350)
        // A third is not counted, but is near.
        try hotel(&world, dx: 8_000)
        XCTAssertEqual(world.hotelsNear(attraction), 3)
        XCTAssertEqual(world.stars(of: attraction), 350, "two count")
        // One beyond 800 m (51,200 units) is not near at all.
        try hotel(&world, dx: 52_000)
        XCTAssertEqual(world.hotelsNear(attraction), 3)
    }

    func testStarsStopAtFive() throws {
        var world = try world()
        world.setTourism([Attraction(id: sight, name: "x", englishName: "x", point: PlanPoint(x: 31_000, y: 32_768), kind: .town, baseStars: 480)])
        try hotel(&world, dx: 0)
        try hotel(&world, dx: 4_000)
        XCTAssertEqual(world.stars(of: try XCTUnwrap(world.attraction(id: sight))), 500)
    }

    func testAHotelRaisesTheTouristsAndThePlan() throws {
        var world = try world()
        XCTAssertEqual(world.touristsExpected(at: sight, onDay: 0), 240)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 240)
        try hotel(&world, dx: 0)
        // 3.25 stars: 2,625 potential, a Monday: 2,625 × 0.6 × 0.2 = 315.
        XCTAssertEqual(world.touristsExpected(at: sight, onDay: 0), 315)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 315, "the plan is worked out again")
    }

    func testAHotelsGuestsAreAShareOfTheTourists() throws {
        var world = try world()
        let one = try hotel(&world, dx: 0)
        // 315 tourists, 150 per mille stay: 47 (rounded down), the only hotel.
        XCTAssertEqual(world.subsidiaryCustomers(of: one, onDay: 0), 47)
        let two = try hotel(&world, dx: 4_000)
        // 3.5 stars: 3,250 × 0.6 × 0.2 = 390, 58 stay, 29 in each.
        XCTAssertEqual(world.subsidiaryCustomers(of: one, onDay: 0), 29)
        XCTAssertEqual(world.subsidiaryCustomers(of: two, onDay: 0), 29)
        // A weekend (day 5, a Saturday): 3,250 × 1.6 × 0.2 = 1,040; 156; 78 each.
        XCTAssertEqual(world.subsidiaryCustomers(of: one, onDay: 5), 78)
    }

    func testWithoutTourismAHotelHasNoGuests() throws {
        var world = try world()
        let one = try hotel(&world, dx: 0)
        world.setTourism(nil)
        XCTAssertEqual(world.subsidiaryCustomers(of: one, onDay: 0), 0, "as before decision 174")
    }

    func testAHotelFarFromTheSightGetsNoTourists() throws {
        var world = try world()
        let far = try world.placeBuilding(.hotel, at: PlanPoint(x: 31_000 + 52_000, y: 32_768 - 6_000))
        XCTAssertEqual(world.subsidiaryCustomers(of: far, onDay: 0), 0)
    }

    func testAHotelBooksTheDaysGuestsAtMidnight() throws {
        var world = try world()
        let one = try hotel(&world, dx: 0)
        world.setSpeed(.normal)
        try world.advance(ticks: 1_442)
        // Day 0's 315 tourists, 47 stay at $85: $3,995 taken; its cost 55%
        // of that and the staff, 0.04% of the hotel's cost, rounded up.
        let sales = 47 * 8_500
        let building = try XCTUnwrap(world.placedBuilding(id: one.id))
        let staff = (building.cost.amount * 4 + 9_999) / 10_000
        XCTAssertEqual(building.books.totalSales, Money(Int64(sales)))
        XCTAssertEqual(building.books.totalCost, Money(Int64(sales) * 55 / 100 + staff))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }
}
