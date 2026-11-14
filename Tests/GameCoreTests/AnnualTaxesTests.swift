import Foundation
@testable import GameCore
import XCTest

/// Decision 734 (ANNUAL-FINANCE AF-1): with the annual taxes on, the
/// company pays no tax at midnight; as a year closes its profit before tax
/// is charged Taiwan's income tax (20 %, none up to NT$120,000, at most
/// half of what is above it), owed until the end of the next year's fifth
/// month.
final class AnnualTaxesTests: XCTestCase {
    private func world(annualTaxes: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        world.setAnnualTaxes(annualTaxes)
        return world
    }

    /// Books `fares` as an hour's fares now, as the hourly settlement
    /// would: the worlds here have no network to earn them.
    private func earn(_ fares: Money, in world: inout GameWorld) {
        let entry = LedgerEntry(
            kind: .hourlyNet, time: world.clock.now, amount: fares,
            breakdown: [
                LedgerLine(item: .fareRevenue, amount: fares), LedgerLine(item: .operatingCost, amount: .zero),
                LedgerLine(item: .maintenanceCost, amount: .zero),
            ],
            crowding: CrowdingMetrics(crowdedStations: 0, fullTrains: 0, maxWaiting: 0, maxLoad: 0)
        )
        world.write(entry, day: world.dayIndex(of: world.clock.now))
    }

    /// A world that earned NT$900,000 on the first year's last day and has
    /// just closed that year: a minute into the second.
    private func closedFirstYear() throws -> GameWorld {
        var world = try world()
        try world.advance(ticks: 359 * 1_440 + 1)
        earn(Money(90_000_000), in: &world)
        try world.advance(ticks: 1_440)
        return world
    }

    func testTheTaxFollowsTaiwansBrackets() {
        XCTAssertEqual(CompanyAccounts.annualIncomeTaxThreshold, Money(12_000_000))
        XCTAssertEqual(GameWorld.annualIncomeTax(on: Money(-50_000_000)), .zero)
        XCTAssertEqual(GameWorld.annualIncomeTax(on: .zero), .zero)
        // Up to NT$120,000: none.
        XCTAssertEqual(GameWorld.annualIncomeTax(on: Money(12_000_000)), .zero)
        // NT$120,001: half of NT$1 is NT$0.50, rounded down to nothing.
        XCTAssertEqual(GameWorld.annualIncomeTax(on: Money(12_000_100)), .zero)
        // NT$150,000: 20 % is NT$30,000, but half of NT$30,000 above is less.
        XCTAssertEqual(GameWorld.annualIncomeTax(on: Money(15_000_000)), Money(1_500_000))
        // NT$200,000: both are NT$40,000.
        XCTAssertEqual(GameWorld.annualIncomeTax(on: Money(20_000_000)), Money(4_000_000))
        // Beyond, 20 % of the whole.
        XCTAssertEqual(GameWorld.annualIncomeTax(on: Money(90_000_000)), Money(18_000_000))
        XCTAssertEqual(GameWorld.annualIncomeTax(on: Money(100_000_099)), Money(20_000_000))
    }

    func testNoDayPaysItsOwnTax() throws {
        var world = try world()
        try world.advance(ticks: 1)
        earn(Money(75_000_000), in: &world)
        let balance = world.economy.balance
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.economy.balance, balance)
        XCTAssertFalse(world.accounts.entries.contains { $0.kind == .dailyTax || $0.kind == .annualIncomeTax })
        XCTAssertEqual(world.financeReport(.day).previous.taxCost, .zero)
        // This year's tax so far: 20 % of NT$750,000.
        XCTAssertEqual(world.estimatedIncomeTax(), Money(15_000_000))
        XCTAssertNil(world.accountsProblem())
    }

    func testTheYearIsChargedAsItClosesAndOwesIt() throws {
        let world = try closedFirstYear()
        let closed = try XCTUnwrap(world.accounts.years.first)
        // NT$900,000 before tax: NT$180,000 of tax, owed, not yet paid.
        XCTAssertEqual(closed.incomeTaxAssessed, Money(18_000_000))
        XCTAssertEqual(closed.income.taxCost, .zero)
        XCTAssertEqual(closed.afterTaxProfit, Money(72_000_000))
        XCTAssertEqual(world.accounts.retainedEarnings(through: 0), Money(72_000_000))
        XCTAssertEqual(world.accounts.incomeTaxPayable, Money(18_000_000))
        XCTAssertEqual(closed.closing.taxPayable, Money(18_000_000))
        XCTAssertEqual(closed.closing.cash, world.economy.balance)
        XCTAssertEqual(closed.closing.equity, closed.closing.totalAssets - Money(18_000_000))
        XCTAssertEqual(world.balanceSheet().taxPayable, Money(18_000_000))
        // The new year has made nothing yet.
        XCTAssertEqual(world.estimatedIncomeTax(), .zero)
        XCTAssertNil(world.accountsProblem())
        let data = try JSONEncoder().encode(world)
        let text = String(decoding: data, as: UTF8.self)
        for key in [#""annualTaxes""#, #""incomeTaxPayable""#, #""taxPayable""#, #""incomeTaxAssessed""#] {
            XCTAssertTrue(text.contains(key), key)
        }
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
    }

    func testTheTaxIsPaidAtTheEndOfTheFifthMonth() throws {
        var world = try closedFirstYear()
        let balance = world.economy.balance
        // A minute into the year's last day of the fifth month: still owed.
        try world.advance(ticks: 149 * 1_440)
        XCTAssertEqual(world.accounts.incomeTaxPayable, Money(18_000_000))
        XCTAssertEqual(world.economy.balance, balance)
        // Its midnight pays it.
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.accounts.incomeTaxPayable, .zero)
        XCTAssertEqual(world.economy.balance, balance - Money(18_000_000))
        let paid = try XCTUnwrap(world.accounts.entries.last { $0.kind == .annualIncomeTax })
        XCTAssertEqual(paid.amount, Money(-18_000_000))
        XCTAssertEqual(paid.breakdown, [LedgerLine(item: .incomeTax, amount: Money(-18_000_000))])
        XCTAssertEqual(paid.time, GameTime(seconds: (360 + 150) * GameTime.secondsPerDay - GameTime.secondsPerMinute))
        // In cash, the second year's; its profit before tax is not lowered.
        let year = world.financeReport(.year).current
        XCTAssertEqual(year.taxCost, Money(18_000_000))
        XCTAssertEqual(year.profitBeforeTax, .zero)
        XCTAssertNil(world.accountsProblem())
    }

    func testAPoorYearOwesNothing() throws {
        var world = try world()
        try world.advance(ticks: 359 * 1_440 + 1)
        earn(Money(12_000_000), in: &world)
        try world.advance(ticks: 1_440)
        let closed = try XCTUnwrap(world.accounts.years.first)
        XCTAssertEqual(closed.incomeTaxAssessed, .zero)
        XCTAssertEqual(world.accounts.incomeTaxPayable, .zero)
        XCTAssertEqual(closed.closing.taxPayable, .zero)
        // Nothing owed writes nothing, so the year's sheet is as before.
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(world), as: UTF8.self).contains(#""taxPayable""#))
    }

    func testWithoutThemEachDayPaysAsBefore() throws {
        var world = try world(annualTaxes: false)
        try world.advance(ticks: 359 * 1_440 + 1)
        earn(Money(90_000_000), in: &world)
        try world.advance(ticks: 1_440)
        let closed = try XCTUnwrap(world.accounts.years.first)
        // Decision 131: half of what is beyond NT$300,000, paid that midnight.
        XCTAssertEqual(closed.income.taxCost, Money(30_000_000))
        XCTAssertNil(closed.incomeTaxAssessed)
        XCTAssertEqual(closed.afterTaxProfit, closed.income.netProfit)
        XCTAssertEqual(world.accounts.retainedEarnings(through: 0), Money(60_000_000))
        XCTAssertEqual(world.accounts.incomeTaxPayable, .zero)
        XCTAssertEqual(world.estimatedIncomeTax(), .zero)
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        for key in [#""annualTaxes""#, #""incomeTaxPayable""#, #""taxPayable""#, #""incomeTaxAssessed""#] {
            XCTAssertFalse(text.contains(key), key)
        }
    }

    func testTaxOwedOutOfRangeIsRefused() throws {
        var world = try closedFirstYear()
        world.accounts.incomeTaxPayable = Money(-100)
        XCTAssertNotNil(world.accountsProblem())
        // A tax row must be the tax alone, out.
        var paid = try closedFirstYear()
        paid.write(LedgerEntry(
            kind: .annualIncomeTax, time: paid.clock.now, amount: Money(100),
            breakdown: [LedgerLine(item: .incomeTax, amount: Money(100))]
        ), day: paid.dayIndex(of: paid.clock.now))
        XCTAssertNotNil(paid.accountsProblem())
    }

    /// The version 99 save: the world above, its first year closed and its
    /// tax owed; it loads as the same world and pays the tax when due.
    func testTheVersion99SaveOwesItsTax() throws {
        let world = try closedFirstYear()
        let url = SavedGameTests.fixtures.appendingPathComponent("v99-annual-taxes.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["ANNUAL_TAXES_SAVE_NEW"] != nil, SavedGame.currentVersion == 99 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        // TEMPORARY (removed once the fixture is committed): no Swift in the
        // session that wrote this, so CI prints the fixture to copy.
        if !FileManager.default.fileExists(atPath: url.path) {
            print("V99-FIXTURE-BEGIN")
            print(String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self))
            print("V99-FIXTURE-END")
            XCTFail("v99-annual-taxes.json is not committed yet")
            return
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 99)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertTrue(loaded.annualTaxes)
        XCTAssertEqual(loaded.accounts.incomeTaxPayable, Money(18_000_000))
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 150 * 1_440)
        try running.advance(ticks: 150 * 1_440)
        XCTAssertEqual(loaded, running)
        XCTAssertEqual(loaded.accounts.incomeTaxPayable, .zero)
    }
}
