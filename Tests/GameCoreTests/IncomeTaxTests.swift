import Foundation
@testable import GameCore
import XCTest

/// Decision 131: a managed company pays, at each midnight, half of what the
/// day made before tax beyond NT$300,000 (the reference's $100,000, times 3
/// by decision 499).
final class IncomeTaxTests: XCTestCase {
    private func world(managed: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        if managed { world.setEconomyMode(.management) }
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

    func testTheTaxIsHalfOfTheProfitBeyondTheAllowance() {
        XCTAssertEqual(CompanyAccounts.taxFreeProfit, Money(30_000_000))
        XCTAssertEqual(GameWorld.dailyTax(on: Money(-150_000_000)), .zero)
        XCTAssertEqual(GameWorld.dailyTax(on: .zero), .zero)
        XCTAssertEqual(GameWorld.dailyTax(on: Money(30_000_000)), .zero)
        // NT$0.005 beyond: rounded to NT$0. NT$1 beyond: NT$0.50, rounded up to NT$1.
        XCTAssertEqual(GameWorld.dailyTax(on: Money(30_000_001)), .zero)
        XCTAssertEqual(GameWorld.dailyTax(on: Money(30_000_100)), Money(100))
        XCTAssertEqual(GameWorld.dailyTax(on: Money(30_000_300)), Money(200))
        XCTAssertEqual(GameWorld.dailyTax(on: Money(75_000_000)), Money(22_500_000))
        XCTAssertEqual(GameWorld.dailyTax(on: Money(150_000_000)), Money(60_000_000))
    }

    func testAProfitableDayPaysItsTaxAtMidnight() throws {
        var world = try world()
        try world.advance(ticks: 1)
        earn(Money(75_000_000), in: &world)
        let balance = world.economy.balance
        try world.advance(ticks: 1_440)
        // NT$750,000 before tax: half of NT$450,000.
        XCTAssertEqual(world.economy.balance, balance - Money(22_500_000))
        let tax = try XCTUnwrap(world.accounts.entries.last)
        XCTAssertEqual(tax.kind, .dailyTax)
        XCTAssertEqual(tax.time, GameTime(seconds: GameTime.secondsPerDay - GameTime.secondsPerMinute))
        XCTAssertEqual(tax.breakdown, [LedgerLine(item: .incomeTax, amount: Money(-22_500_000))])
        let report = world.financeReport(.day).previous
        XCTAssertEqual(report.operatingProfit, Money(75_000_000), "The tax is not a running cost")
        XCTAssertEqual(report.profitBeforeTax, Money(75_000_000))
        XCTAssertEqual(report.taxCost, Money(22_500_000))
        XCTAssertEqual(report.netProfit, Money(52_500_000))
        XCTAssertEqual(report.operatingCashFlow, Money(52_500_000))
        XCTAssertNil(world.accountsProblem())
        let data = try JSONEncoder().encode(world)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""taxCost""#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
    }

    func testInterestLowersTheProfitTaxed() throws {
        var world = try world()
        try world.borrow(Money(300_000_000))
        try world.advance(ticks: 1)
        earn(Money(75_000_000), in: &world)
        try world.advance(ticks: 1_440)
        // NT$417 of interest: NT$749,583 before tax, NT$224,791.50 of tax, NT$224,792.
        let report = world.financeReport(.day).previous
        XCTAssertEqual(report.profitBeforeTax, Money(75_000_000 - 41_700))
        XCTAssertEqual(report.taxCost, Money(22_479_200))
        XCTAssertNil(world.accountsProblem())
    }

    func testSmallDaysLossesAndFreePlayPayNoTax() throws {
        // Within the allowance.
        var small = try world()
        try small.advance(ticks: 1)
        earn(Money(30_000_000), in: &small)
        try small.advance(ticks: 1_440)
        XCTAssertFalse(small.accounts.entries.contains { $0.kind == .dailyTax })
        XCTAssertEqual(small.financeReport(.day).previous.taxCost, .zero)
        // A loss: the interest only.
        var owing = try world()
        try owing.borrow(Money(300_000_000))
        try owing.advance(ticks: 1_441)
        XCTAssertFalse(owing.accounts.entries.contains { $0.kind == .dailyTax })
        // A day without tax writes no tax, so saves without it are as before.
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(owing), as: UTF8.self).contains(#""taxCost""#))
        // Free play settles nothing.
        var free = try world(managed: false)
        try free.advance(ticks: 1_441)
        XCTAssertEqual(free.accounts.entries, [])
    }

    func testTheYearsStatementHoldsItsTax() throws {
        var world = try world()
        try world.advance(ticks: 359 * 1_440 + 1)
        earn(Money(90_000_000), in: &world)
        try world.advance(ticks: 1_440)
        let closed = try XCTUnwrap(world.accounts.years.first)
        XCTAssertEqual(closed.income.taxCost, Money(30_000_000))
        XCTAssertEqual(closed.income.netProfit, Money(60_000_000))
        XCTAssertEqual(closed.closing.cash, world.economy.balance)
        XCTAssertNil(world.accountsProblem())
        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
    }

    func testABadTaxRowIsRefused() throws {
        var world = try world()
        try world.advance(ticks: 1)
        // A tax row must be the tax alone, out.
        world.write(LedgerEntry(
            kind: .dailyTax, time: world.clock.now, amount: Money(100),
            breakdown: [LedgerLine(item: .incomeTax, amount: Money(100))]
        ), day: 0)
        XCTAssertNotNil(world.accountsProblem())
    }
}
