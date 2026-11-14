import Foundation
@testable import GameCore
import XCTest

/// Decision 736 (ANNUAL-FINANCE AF-2): with the annual taxes on, the year's
/// close charges the house tax (3 % of the stations' and buildings' book
/// value), paid with the income tax at the end of the next fifth month, and
/// the land tax (1 % of the land bought), paid at the end of the next
/// eleventh; and the stations pay a daily upkeep by their platforms.
final class AnnualPropertyTaxesTests: XCTestCase {
    /// A station costs NT$720,000 here, so a year's house tax is worth
    /// counting.
    static let costs = ConstructionCosts(track: 100, station: 72_000_000, train: 5_000)

    /// A managed world with the annual taxes, one track edge and a station
    /// with a 100 m platform on it, built at the start.
    static func world(annualTaxes: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 32_768, height: 4_096), economy: GameEconomy(balance: 1_000_000_000, costs: costs),
            clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        world.setAnnualTaxes(annualTaxes)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 1_024))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 17_408, y: 1_024))
        try world.buildTrackEdge(from: a, to: b)
        let station = try world.buildStation(named: "A", at: PlanPoint(x: 5_120, y: 2_048)).id
        try world.addTrackPlatform(station, on: .edge(1), from: 1_024, to: 1_024 + 100 * WorldCoordinate.unitsPerMetre)
        return world
    }

    /// The world above a minute into its second year.
    static func closedFirstYear() throws -> GameWorld {
        var world = try world()
        try world.advance(ticks: 360 * 1_440 + 1)
        return world
    }

    func testTheRatesAreTaiwans() {
        XCTAssertEqual(GameWorld.annualHouseTax(on: .zero), .zero)
        XCTAssertEqual(GameWorld.annualHouseTax(on: Money(-100_000)), .zero)
        // 3 % of NT$7,200: NT$216.
        XCTAssertEqual(GameWorld.annualHouseTax(on: Money(720_000)), Money(21_600))
        // 3 % of NT$99: NT$2.97, rounded down.
        XCTAssertEqual(GameWorld.annualHouseTax(on: Money(9_999)), Money(200))
        // 1 % of NT$10,000.50: NT$100.
        XCTAssertEqual(GameWorld.annualLandTax(on: Money(1_000_050)), Money(10_000))
        XCTAssertEqual(GameWorld.annualLandTax(on: Money(9_900)), .zero)
    }

    func testThePlatformsPayTheirUpkeepEachDay() throws {
        var world = try Self.world()
        // 100 m: NT$300 a day.
        XCTAssertEqual(world.dailyStationUpkeep(), Money(30_000))
        try world.advance(ticks: 1_441)
        let row = try XCTUnwrap(world.accounts.entries.first { $0.kind == .dailyStationUpkeep })
        XCTAssertEqual(row.breakdown, [LedgerLine(item: .stationUpkeep, amount: Money(-30_000))])
        XCTAssertNil(world.accountsProblem())
        // Without the annual taxes, none.
        var plain = try Self.world(annualTaxes: false)
        XCTAssertEqual(plain.dailyStationUpkeep(), .zero)
        try plain.advance(ticks: 1_441)
        XCTAssertFalse(plain.accounts.entries.contains { $0.kind == .dailyStationUpkeep })
    }

    func testTheYearsCloseChargesTheHouseTaxPaidInTheFifthMonth() throws {
        var world = try Self.closedFirstYear()
        let closed = try XCTUnwrap(world.accounts.years.first)
        let house = GameWorld.annualHouseTax(on: closed.closing.stations.bookValue)
        XCTAssertGreaterThan(house, .zero)
        XCTAssertEqual(world.accounts.houseTaxPayable, house)
        XCTAssertEqual(world.accounts.landTaxPayable, .zero)
        XCTAssertEqual(closed.closing.taxPayable, house + world.accounts.incomeTaxPayable)
        XCTAssertNil(world.accountsProblem())
        let data = try JSONEncoder().encode(world)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""houseTaxPayable""#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        // Paid at the end of the fifth month.
        try world.advance(ticks: 149 * 1_440)
        XCTAssertEqual(world.accounts.houseTaxPayable, house)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.accounts.houseTaxPayable, .zero)
        let paid = try XCTUnwrap(world.accounts.entries.last { $0.kind == .annualHouseTax })
        XCTAssertEqual(paid.breakdown, [LedgerLine(item: .houseTax, amount: .zero - house)])
        XCTAssertEqual(paid.time, GameTime(seconds: (360 + 150) * GameTime.secondsPerDay - GameTime.secondsPerMinute))
        XCTAssertNil(world.accountsProblem())
    }

    func testTheLandTaxIsPaidInTheEleventhMonth() throws {
        var world = try Self.closedFirstYear()
        world.accounts.landTaxPayable = Money(10_000)
        let balance = world.economy.balance
        try world.advance(ticks: 329 * 1_440)
        XCTAssertEqual(world.accounts.landTaxPayable, Money(10_000))
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.accounts.landTaxPayable, .zero)
        let paid = try XCTUnwrap(world.accounts.entries.last { $0.kind == .annualLandTax })
        XCTAssertEqual(paid.breakdown, [LedgerLine(item: .propertyTax, amount: Money(-10_000))])
        XCTAssertEqual(paid.time, GameTime(seconds: (360 + 330) * GameTime.secondsPerDay - GameTime.secondsPerMinute))
        XCTAssertLessThan(world.economy.balance, balance)
        XCTAssertNil(world.accountsProblem())
    }

    func testWithoutTheAnnualTaxesNothingIsOwed() throws {
        var world = try Self.world(annualTaxes: false)
        try world.advance(ticks: 360 * 1_440 + 1)
        XCTAssertEqual(world.accounts.houseTaxPayable, .zero)
        XCTAssertEqual(world.accounts.landTaxPayable, .zero)
        XCTAssertEqual(world.estimatedPropertyTaxes().house, .zero)
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        for key in [#""houseTaxPayable""#, #""landTaxPayable""#, #""taxPayable""#] {
            XCTAssertFalse(text.contains(key), key)
        }
    }

    func testTaxesOwedOutOfRangeAreRefused() throws {
        var world = try Self.closedFirstYear()
        world.accounts.landTaxPayable = Money(-100)
        XCTAssertNotNil(world.accountsProblem())
    }

    /// The version 100 save: the world above a minute into its second year,
    /// owing the first year's house tax; it loads as the same world and
    /// pays it when due.
    func testTheVersion100SaveOwesItsHouseTax() throws {
        let world = try Self.closedFirstYear()
        let url = SavedGameTests.fixtures.appendingPathComponent("v100-house-tax.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["HOUSE_TAX_SAVE_NEW"] != nil, SavedGame.currentVersion == 100 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 100)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertGreaterThan(loaded.accounts.houseTaxPayable, .zero)
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 150 * 1_440)
        try running.advance(ticks: 150 * 1_440)
        XCTAssertEqual(loaded, running)
        XCTAssertEqual(loaded.accounts.houseTaxPayable, .zero)
    }
}
