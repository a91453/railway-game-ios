import Foundation
@testable import GameCore
import XCTest

/// Decision 715, section 8 (REVIEW-L20 P2-5): with unlimited funds
/// (decision 200) nothing moves the balance, so both loans stand still
/// while they are on. Nothing is borrowed (the debt would be booked and no
/// money come in), nothing is repaid (the debt would go and no money
/// leave), and a term loan does not fall due; turned off, the loans carry
/// on, and one past its due day is paid at the next midnight.
///
/// Expected values are worked out by hand from the rules and written out.
final class LoanUnlimitedFundsTests: XCTestCase {
    /// A managed company with NT$20,000,000 and nothing else.
    private func world() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096),
            economy: fixtureEconomy(balance: 2_000_000_000, costs: testCosts), clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        return world
    }

    private let day = 1_440

    func testNothingIsBorrowedWithUnlimitedFunds() throws {
        var world = try world()
        world.setUnlimitedFunds(true)
        let before = world
        XCTAssertThrowsGameError(try world.termLoanQuote(principal: Money(300_000_000), years: 1), .loanNeedsLimitedFunds)
        XCTAssertThrowsGameError(try world.takeTermLoan(principal: Money(300_000_000), years: 1), .loanNeedsLimitedFunds)
        XCTAssertThrowsGameError(try world.borrow(CompanyAccounts.loanStep), .loanNeedsLimitedFunds)
        XCTAssertEqual(world, before, "no debt for money that never came in")

        // REVIEW-L20's probe: signed with them on and then turned off, the
        // company owed NT$3,000,000 it never had. Now it owes nothing, and
        // a year later has paid nothing.
        world.setUnlimitedFunds(false)
        XCTAssertEqual(world.accounts.termLoans, [])
        XCTAssertEqual(world.accounts.loan, .zero)
        try world.advance(ticks: 361 * day)
        XCTAssertEqual(world.economy.balance, Money(2_000_000_000))

        // Off again, the bank lends as ever.
        try world.takeTermLoan(principal: Money(300_000_000), years: 1)
        try world.borrow(CompanyAccounts.loanStep)
        XCTAssertEqual(world.economy.balance, Money(2_000_000_000 + 300_000_000 + 30_000_000))
    }

    /// A company in free play is told so first, as before.
    func testFreePlayIsStillToldItCannotBorrow() throws {
        var world = try world()
        world.setEconomyMode(.free)
        world.setUnlimitedFunds(true)
        XCTAssertThrowsGameError(try world.takeTermLoan(principal: Money(300_000_000), years: 1), .loanNeedsManagement)
        XCTAssertThrowsGameError(try world.borrow(CompanyAccounts.loanStep), .loanNeedsManagement)
    }

    func testNothingIsRepaidWithUnlimitedFunds() throws {
        var world = try world()
        try world.takeTermLoan(principal: Money(300_000_000), years: 1)
        try world.borrow(CompanyAccounts.loanStep)
        XCTAssertEqual(world.economy.balance, Money(2_330_000_000))
        world.setUnlimitedFunds(true)
        let owing = world
        // REVIEW-L20's probe the other way: repaid with them on, the loan
        // went and the NT$3,000,000 stayed.
        XCTAssertThrowsGameError(try world.repayTermLoanEarly(1), .loanNeedsLimitedFunds)
        XCTAssertThrowsGameError(try world.repayLoan(CompanyAccounts.loanStep), .loanNeedsLimitedFunds)
        XCTAssertEqual(world, owing)
        // A loan that does not exist is still said first.
        XCTAssertThrowsGameError(try world.repayTermLoanEarly(2), .invalidTermLoan)
        XCTAssertThrowsGameError(try world.repayLoan(Money(1)), .invalidLoanAmount)
        // The quote is only read, and reads the same.
        XCTAssertEqual(try world.termLoanRepaymentQuote(1).total, Money(300_000_000 + 3_000_000))

        world.setUnlimitedFunds(false)
        try world.repayTermLoanEarly(1)
        try world.repayLoan(CompanyAccounts.loanStep)
        // NT$3,000,000 and a fifth of NT$150,000 for the term loan,
        // NT$300,000 for the other.
        XCTAssertEqual(world.economy.balance, Money(2_330_000_000 - 303_000_000 - 30_000_000))
        XCTAssertEqual(world.accounts.termLoans, [])
        XCTAssertEqual(world.accounts.loan, .zero)
        XCTAssertNil(world.accountsProblem())
    }

    func testATermLoanDoesNotFallDueWithUnlimitedFunds() throws {
        var world = try world()
        try world.takeTermLoan(principal: Money(300_000_000), years: 1)
        world.setUnlimitedFunds(true)
        // Ten days past its due day: it is still owed, and nothing moved.
        try world.advance(ticks: 370 * day + 1)
        XCTAssertEqual(world.accounts.termLoans.map(\.id), [1], "not written off while the balance cannot pay")
        XCTAssertEqual(world.economy.balance, Money(2_300_000_000))
        XCTAssertNil(world.accountsProblem())

        // Turned off, it is paid at the next midnight: NT$3,000,000 and the
        // NT$150,000 fixed when it was signed, no more for the days over.
        world.setUnlimitedFunds(false)
        XCTAssertEqual(world.accounts.termLoans.count, 1)
        try world.advance(ticks: day)
        XCTAssertEqual(world.accounts.termLoans, [])
        XCTAssertEqual(world.economy.balance, Money(2_300_000_000 - 300_000_000 - 15_000_000))
        XCTAssertEqual(world.financeReport(.day).previous.loanRepaid, Money(300_000_000))
        XCTAssertNil(world.accountsProblem())
    }

    /// A year in one call and a day at a time agree, with the funds turned
    /// on part of the way.
    func testBatchedAndSteppedDaysAgree() throws {
        var whole = try world()
        try whole.takeTermLoan(principal: Money(300_000_000), years: 1)
        var stepped = whole
        for on in [true, false] {
            whole.setUnlimitedFunds(on)
            stepped.setUnlimitedFunds(on)
            try whole.advance(ticks: 365 * day)
            for _ in 0..<365 { try stepped.advance(ticks: day) }
        }
        XCTAssertEqual(stepped, whole)
        XCTAssertEqual(whole.accounts.termLoans, [])
    }
}
