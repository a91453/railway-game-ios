import Foundation
@testable import GameCore
import XCTest

/// Decision 67: a managed company borrows and repays in $100,000 steps up to
/// $5,000,000, and pays 5 % a 360-day year on what it owes, every midnight.
final class LoanTests: XCTestCase {
    private func world(managed: Bool = true, balance: Money = 1_000_000) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: balance, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        if managed { world.setEconomyMode(.management) }
        return world
    }

    func testBorrowingAndRepayingMoveTheBalanceAndTheLoan() throws {
        var world = try world()
        try world.borrow(Money(30_000_000))
        XCTAssertEqual(world.accounts.loan, Money(30_000_000))
        XCTAssertEqual(world.economy.balance, Money(31_000_000))
        try world.repayLoan(Money(10_000_000))
        XCTAssertEqual(world.accounts.loan, Money(20_000_000))
        XCTAssertEqual(world.economy.balance, Money(21_000_000))
        XCTAssertNil(world.accountsProblem())
    }

    func testRefusedLoansChangeNothing() throws {
        var world = try world()
        let before = world
        for amount in [Money(0), Money(-10_000_000), Money(10_000_001), Money(510_000_000)] {
            XCTAssertThrowsError(try world.borrow(amount)) { XCTAssertEqual($0 as? GameError, .invalidLoanAmount) }
        }
        XCTAssertThrowsError(try world.repayLoan(Money(10_000_000))) { XCTAssertEqual($0 as? GameError, .invalidLoanAmount) }
        XCTAssertEqual(world, before)

        try world.borrow(CompanyAccounts.maximumLoan)
        XCTAssertThrowsError(try world.borrow(CompanyAccounts.loanStep)) { XCTAssertEqual($0 as? GameError, .invalidLoanAmount) }
        XCTAssertThrowsError(try world.repayLoan(Money(510_000_000))) { XCTAssertEqual($0 as? GameError, .invalidLoanAmount) }

        // Repaying needs the money.
        var poor = try self.world(balance: .zero)
        try poor.borrow(CompanyAccounts.loanStep)
        try poor.economy.spend(Money(1))
        let owing = poor
        XCTAssertThrowsError(try poor.repayLoan(CompanyAccounts.loanStep)) {
            XCTAssertEqual($0 as? GameError, .insufficientFunds(required: CompanyAccounts.loanStep, available: Money(9_999_999)))
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
        // $1,000,000 at 5 % over 360 days: $138.888… a day, so $139.
        XCTAssertEqual(GameWorld.dailyLoanInterest(on: Money(100_000_000)), Money(13_900))
        // $100,000: $13.888…, $14. $5,000,000: $694.44…, $694.
        XCTAssertEqual(GameWorld.dailyLoanInterest(on: CompanyAccounts.loanStep), Money(1_400))
        XCTAssertEqual(GameWorld.dailyLoanInterest(on: CompanyAccounts.maximumLoan), Money(69_400))
        XCTAssertEqual(GameWorld.dailyLoanInterest(on: .zero), .zero)

        var world = try world()
        try world.borrow(Money(100_000_000))
        let balance = world.economy.balance
        // Midnight is settled at the start of the minute from it.
        try world.advance(ticks: 1_441)
        XCTAssertEqual(world.economy.balance, balance - Money(13_900))
        let interest = try XCTUnwrap(world.accounts.entries.last)
        XCTAssertEqual(interest.kind, .dailyInterest)
        XCTAssertEqual(interest.time, GameTime(seconds: GameTime.secondsPerDay - GameTime.secondsPerMinute))
        XCTAssertEqual(interest.breakdown, [LedgerLine(item: .loanInterest, amount: Money(-13_900))])
        let report = world.financeReport(.day).previous
        XCTAssertEqual(report.interestCost, Money(13_900))
        XCTAssertEqual(report.totalCost, .zero, "Interest is not a running cost")
        XCTAssertEqual(report.netProfit, Money(-13_900))
        XCTAssertNil(world.accountsProblem())
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)

        // A day split into many calls pays the same.
        var stepped = try self.world()
        try stepped.borrow(Money(100_000_000))
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
        XCTAssertTrue(text.contains(#""loan":10000000"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        for bad in ["10000001", "-10000000", "510000000"] {
            let broken = text.replacingOccurrences(of: #""loan":10000000"#, with: #""loan":\#(bad)"#)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(broken.utf8)), bad)
        }
    }
}
