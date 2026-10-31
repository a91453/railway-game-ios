import Foundation
@testable import GameCore
import XCTest

/// Decision 67: a managed company borrows and repays in NT$300,000 steps up to
/// NT$15,000,000 (decision 499), and pays 5 % a 360-day year on what it owes,
/// every midnight.
final class LoanTests: XCTestCase {
    private func world(managed: Bool = true, balance: Money = 1_000_000) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: fixtureEconomy(balance: balance, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        if managed { world.setEconomyMode(.management) }
        return world
    }

    func testBorrowingAndRepayingMoveTheBalanceAndTheLoan() throws {
        var world = try world()
        try world.borrow(Money(90_000_000))
        XCTAssertEqual(world.accounts.loan, Money(90_000_000))
        XCTAssertEqual(world.economy.balance, Money(91_000_000))
        try world.repayLoan(Money(30_000_000))
        XCTAssertEqual(world.accounts.loan, Money(60_000_000))
        XCTAssertEqual(world.economy.balance, Money(61_000_000))
        XCTAssertNil(world.accountsProblem())
    }

    func testRefusedLoansChangeNothing() throws {
        var world = try world()
        let before = world
        for amount in [Money(0), Money(-30_000_000), Money(30_000_001), Money(1_530_000_000)] {
            XCTAssertThrowsError(try world.borrow(amount)) { XCTAssertEqual($0 as? GameError, .invalidLoanAmount) }
        }
        XCTAssertThrowsError(try world.repayLoan(Money(30_000_000))) { XCTAssertEqual($0 as? GameError, .invalidLoanAmount) }
        XCTAssertEqual(world, before)

        try world.borrow(CompanyAccounts.maximumLoan)
        XCTAssertThrowsError(try world.borrow(CompanyAccounts.loanStep)) { XCTAssertEqual($0 as? GameError, .invalidLoanAmount) }
        XCTAssertThrowsError(try world.repayLoan(Money(1_530_000_000))) { XCTAssertEqual($0 as? GameError, .invalidLoanAmount) }

        // Repaying needs the money.
        var poor = try self.world(balance: .zero)
        try poor.borrow(CompanyAccounts.loanStep)
        try poor.economy.spend(Money(1))
        let owing = poor
        XCTAssertThrowsError(try poor.repayLoan(CompanyAccounts.loanStep)) {
            XCTAssertEqual($0 as? GameError, .insufficientFunds(required: CompanyAccounts.loanStep, available: Money(29_999_999)))
        }
        XCTAssertEqual(poor, owing)

        // Free play does not borrow, but may repay.
        var free = try self.world()
        try free.borrow(CompanyAccounts.loanStep)
        free.setEconomyMode(.free)
        XCTAssertThrowsError(try free.borrow(CompanyAccounts.loanStep)) { XCTAssertEqual($0 as? GameError, .loanNeedsManagement) }
        try free.repayLoan(CompanyAccounts.loanStep)
        XCTAssertEqual(free.accounts.loan, .zero)
    }

    func testInterestIsPaidEveryMidnight() throws {
        // NT$3,000,000 at 5 % over 360 days: NT$416.66… a day, so NT$417.
        XCTAssertEqual(GameWorld.dailyLoanInterest(on: Money(300_000_000)), Money(41_700))
        // NT$300,000: NT$41.66…, NT$42. NT$15,000,000: NT$2,083.33…, NT$2,083.
        XCTAssertEqual(GameWorld.dailyLoanInterest(on: CompanyAccounts.loanStep), Money(4_200))
        XCTAssertEqual(GameWorld.dailyLoanInterest(on: CompanyAccounts.maximumLoan), Money(208_300))
        XCTAssertEqual(GameWorld.dailyLoanInterest(on: .zero), .zero)

        var world = try world()
        try world.borrow(Money(300_000_000))
        let balance = world.economy.balance
        // Midnight is settled at the start of the minute from it.
        try world.advance(ticks: 1_441)
        XCTAssertEqual(world.economy.balance, balance - Money(41_700))
        let interest = try XCTUnwrap(world.accounts.entries.last)
        XCTAssertEqual(interest.kind, .dailyInterest)
        XCTAssertEqual(interest.time, GameTime(seconds: GameTime.secondsPerDay - GameTime.secondsPerMinute))
        XCTAssertEqual(interest.breakdown, [LedgerLine(item: .loanInterest, amount: Money(-41_700))])
        let report = world.financeReport(.day).previous
        XCTAssertEqual(report.interestCost, Money(41_700))
        XCTAssertEqual(report.totalCost, .zero, "Interest is not a running cost")
        XCTAssertEqual(report.netProfit, Money(-41_700))
        XCTAssertNil(world.accountsProblem())
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)

        // A day split into many calls pays the same.
        var stepped = try self.world()
        try stepped.borrow(Money(300_000_000))
        for _ in 0..<1_441 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(stepped, world)
    }

    func testSavesWithoutALoanAreUnchangedAndBadLoansAreRefused() throws {
        var world = try world()
        let before = try JSONEncoder().encode(world)
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains(#""loan""#))
        try world.borrow(CompanyAccounts.loanStep)
        let data = try JSONEncoder().encode(world)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""loan":30000000"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        for bad in ["30000001", "-30000000", "1530000000"] {
            let broken = text.replacingOccurrences(of: #""loan":30000000"#, with: #""loan":\#(bad)"#)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(broken.utf8)), bad)
        }
    }
}
