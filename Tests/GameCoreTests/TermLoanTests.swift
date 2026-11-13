import Foundation
@testable import GameCore
import XCTest

/// Decision 715: a managed company signs term loans of 1 to 10 years beside
/// the loan of decision 67. The interest is fixed at signing and paid with
/// the principal when the loan falls due; the bank lends while what is owed
/// on term loans stays below half of what the company is worth; paying
/// early costs the interest gone by and a fifth of the rest.
final class TermLoanTests: XCTestCase {
    /// NT$20,000,000 and nothing else: the company is worth its cash.
    private func world(managed: Bool = true, balance: Money = 2_000_000_000) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: fixtureEconomy(balance: balance, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        if managed { world.setEconomyMode(.management) }
        return world
    }

    private let day: Int64 = 1_440

    func testALongerTermCostsMoreAYear() {
        XCTAssertEqual((1...10).map { CompanyAccounts.termLoanRate(years: $0) }, [500, 510, 520, 530, 540, 550, 570, 590, 610, 630])
        XCTAssertNil(CompanyAccounts.termLoanRate(years: 0))
        XCTAssertNil(CompanyAccounts.termLoanRate(years: 11))
        // NT$3,000,000 for 2 years at 5.10 %: NT$153,000 a year.
        XCTAssertEqual(CompanyAccounts.termLoanInterest(principal: Money(300_000_000), rate: 510, years: 2), Money(30_600_000))
        // Each year's interest is rounded down to a dollar: NT$300,000 at
        // 6.30 % is NT$18,900 a year.
        XCTAssertEqual(CompanyAccounts.termLoanInterest(principal: CompanyAccounts.loanStep, rate: 630, years: 10), Money(18_900_000))
    }

    func testTheQuoteIsTheLoanSigned() throws {
        var world = try world()
        let quote = try world.termLoanQuote(principal: Money(300_000_000), years: 2)
        XCTAssertEqual(quote, TermLoanQuote(principal: Money(300_000_000), years: 2, rate: 510, interest: Money(30_600_000), dueDay: 720))
        XCTAssertEqual(quote.total, Money(330_600_000))
        let untouched = try self.world()
        XCTAssertEqual(world, untouched, "A quote changes nothing")

        let loan = try world.takeTermLoan(principal: Money(300_000_000), years: 2)
        XCTAssertEqual(loan, TermLoan(id: 1, principal: Money(300_000_000), interest: Money(30_600_000), rate: 510, years: 2, borrowedDay: 0))
        XCTAssertEqual(loan.dueDay, quote.dueDay)
        XCTAssertEqual(world.accounts.termLoans, [loan])
        XCTAssertEqual(world.accounts.nextTermLoanID, 2)
        XCTAssertEqual(world.economy.balance, Money(2_300_000_000))
        // The sheet owes the principal; borrowing does not change what the
        // company is worth.
        let sheet = world.balanceSheet()
        XCTAssertEqual(sheet.termLoans, Money(300_000_000))
        XCTAssertEqual(sheet.equity, Money(2_000_000_000))
        XCTAssertEqual(sheet.totalAssets, sheet.loan + sheet.termLoans + sheet.equity)
        XCTAssertEqual(world.financeReport(.day).current.loanBorrowed, Money(300_000_000))
        XCTAssertNil(world.accountsProblem())
    }

    func testTheBankLendsBelowHalfOfWhatTheCompanyIsWorth() throws {
        var world = try world()
        // Worth NT$20,000,000: the limit is NT$10,000,000, and what is owed
        // and the new principal stay below it.
        XCTAssertEqual(world.termLoanCredit(), TermLoanCredit(
            limit: Money(1_000_000_000), outstanding: .zero, freeSlots: 50, maximumPrincipal: Money(990_000_000)
        ))
        try world.takeTermLoan(principal: Money(300_000_000), years: 2)
        // The interest still to pay comes off the worth: NT$19,694,000,
        // half of it NT$9,847,000; NT$3,306,000 is owed.
        XCTAssertEqual(world.termLoanCredit(), TermLoanCredit(
            limit: Money(984_700_000), outstanding: Money(330_600_000), freeSlots: 49, maximumPrincipal: Money(630_000_000)
        ))
        let before = world
        XCTAssertThrowsError(try world.takeTermLoan(principal: Money(660_000_000), years: 1)) { XCTAssertEqual($0 as? GameError, .invalidTermLoan) }
        XCTAssertEqual(world, before)
        try world.takeTermLoan(principal: Money(630_000_000), years: 1)
        XCTAssertEqual(world.accounts.termLoans.map(\.id), [1, 2])

        // A company worth nothing, or less, borrows nothing.
        var poor = try self.world(balance: .zero)
        XCTAssertEqual(poor.termLoanCredit().maximumPrincipal, .zero)
        try poor.borrow(CompanyAccounts.loanStep)
        try poor.economy.spend(CompanyAccounts.loanStep)
        XCTAssertEqual(poor.termLoanCredit().limit, Money(-15_000_000))
        XCTAssertEqual(poor.termLoanCredit().maximumPrincipal, .zero)
    }

    func testRefusedTermLoansChangeNothing() throws {
        var world = try world()
        let before = world
        for principal in [Money(0), Money(-30_000_000), Money(30_000_001), Money(1_020_000_000)] {
            XCTAssertThrowsError(try world.takeTermLoan(principal: principal, years: 1)) { XCTAssertEqual($0 as? GameError, .invalidTermLoan) }
        }
        for years: Int64 in [0, -1, 11] {
            XCTAssertThrowsError(try world.takeTermLoan(principal: CompanyAccounts.loanStep, years: years)) {
                XCTAssertEqual($0 as? GameError, .invalidTermLoan)
            }
        }
        XCTAssertThrowsError(try world.repayTermLoanEarly(1)) { XCTAssertEqual($0 as? GameError, .invalidTermLoan) }
        XCTAssertThrowsError(try world.termLoanRepaymentQuote(1)) { XCTAssertEqual($0 as? GameError, .invalidTermLoan) }
        XCTAssertEqual(world, before)

        // Free play signs none.
        var free = try self.world(managed: false)
        XCTAssertThrowsError(try free.takeTermLoan(principal: CompanyAccounts.loanStep, years: 1)) {
            XCTAssertEqual($0 as? GameError, .loanNeedsManagement)
        }
    }

    func testTheBankHoldsFiftyTermLoansAtOnce() throws {
        var world = try world(balance: 1_000_000_000_000)
        for _ in 0..<50 { try world.takeTermLoan(principal: CompanyAccounts.loanStep, years: 1) }
        XCTAssertEqual(world.termLoanCredit().freeSlots, 0)
        XCTAssertEqual(world.termLoanCredit().maximumPrincipal, .zero)
        XCTAssertThrowsError(try world.takeTermLoan(principal: CompanyAccounts.loanStep, years: 1)) {
            XCTAssertEqual($0 as? GameError, .invalidTermLoan)
        }
        // Paying one back frees its slot; its ID is not used again.
        try world.repayTermLoanEarly(7)
        try world.takeTermLoan(principal: CompanyAccounts.loanStep, years: 1)
        XCTAssertEqual(world.accounts.termLoans.last?.id, 51)
        XCTAssertNil(world.accountsProblem())
    }

    func testPayingEarlyCostsTheInterestGoneByAndAFifthOfTheRest() throws {
        var world = try world()
        let loan = try world.takeTermLoan(principal: Money(300_000_000), years: 2)
        // The day it is signed: nothing gone by, a fifth of NT$306,000.
        XCTAssertEqual(try world.termLoanRepaymentQuote(1), TermLoanRepaymentQuote(
            loan: loan, elapsedDays: 0, accruedInterest: .zero, penalty: Money(6_120_000), interest: Money(6_120_000)
        ))
        // A year on: half gone by, a fifth of the other half.
        try world.advance(ticks: Int(360 * day))
        let quote = try world.termLoanRepaymentQuote(1)
        XCTAssertEqual(quote, TermLoanRepaymentQuote(
            loan: loan, elapsedDays: 360, accruedInterest: Money(15_300_000), penalty: Money(3_060_000), interest: Money(18_360_000)
        ))
        XCTAssertEqual(quote.total, Money(318_360_000))
        // Charged interest is rounded down to NT$100.
        XCTAssertEqual(
            GameWorld.repaymentQuote(of: loan, on: 1).interest, Money(6_150_000),
            "NT$425 gone by and a fifth of NT$305,575, NT$61,115: NT$61,540 charged as NT$61,500"
        )
        // Past its due day (a company that was not managed then), it costs
        // all of its interest and no more.
        XCTAssertEqual(GameWorld.repaymentQuote(of: loan, on: 9_999).interest, loan.interest)

        let balance = world.economy.balance
        try world.repayTermLoanEarly(1)
        XCTAssertEqual(world.economy.balance, balance - Money(318_360_000))
        XCTAssertEqual(world.accounts.termLoans, [])
        let row = try XCTUnwrap(world.accounts.entries.last)
        XCTAssertEqual(row.kind, .dailyInterest)
        XCTAssertEqual(row.breakdown, [LedgerLine(item: .loanInterest, amount: Money(-18_360_000))])
        let today = world.financeReport(.day).current
        XCTAssertEqual(today.interestCost, Money(18_360_000))
        XCTAssertEqual(today.loanRepaid, Money(300_000_000))
        XCTAssertEqual(world.balanceSheet().termLoans, .zero)
        XCTAssertNil(world.accountsProblem())
    }

    func testPayingEarlyNeedsTheMoneyAndFreePlayMayPayToo() throws {
        var world = try world(balance: 90_000_000)
        try world.takeTermLoan(principal: CompanyAccounts.loanStep, years: 1)
        try world.economy.spend(Money(90_000_001))
        let owing = world
        // NT$300,000 and a fifth of NT$15,000.
        XCTAssertThrowsError(try world.repayTermLoanEarly(1)) {
            XCTAssertEqual($0 as? GameError, .insufficientFunds(required: Money(30_300_000), available: Money(29_999_999)))
        }
        XCTAssertEqual(world, owing)

        var free = try self.world()
        try free.takeTermLoan(principal: CompanyAccounts.loanStep, years: 1)
        free.setEconomyMode(.free)
        let balance = free.economy.balance
        let rows = free.accounts.entries
        try free.repayTermLoanEarly(1)
        XCTAssertEqual(free.economy.balance, balance - Money(30_300_000))
        XCTAssertEqual(free.accounts.termLoans, [])
        XCTAssertEqual(free.accounts.entries, rows, "Free play keeps no ledger")
    }

    func testATermLoanIsPaidInOneSumAsItsDueDayBegins() throws {
        var world = try world()
        try world.takeTermLoan(principal: Money(300_000_000), years: 1)
        // Midnight is settled at the start of the minute from it: the
        // midnight before the due day's changes nothing.
        try world.advance(ticks: Int(359 * day) + 1)
        XCTAssertEqual(world.accounts.termLoans.count, 1)
        XCTAssertEqual(world.economy.balance, Money(2_300_000_000))
        try world.advance(ticks: Int(day))
        XCTAssertEqual(world.accounts.termLoans, [])
        // NT$3,000,000 back and NT$150,000 of interest.
        XCTAssertEqual(world.economy.balance, Money(2_000_000_000 - 15_000_000))
        let row = try XCTUnwrap(world.accounts.entries.last { $0.kind == .dailyInterest })
        XCTAssertEqual(row.time, GameTime(seconds: 360 * GameTime.secondsPerDay - GameTime.secondsPerMinute))
        XCTAssertEqual(row.breakdown, [LedgerLine(item: .loanInterest, amount: Money(-15_000_000))])
        let lastDay = world.financeReport(.day).previous
        XCTAssertEqual(lastDay.interestCost, Money(15_000_000))
        XCTAssertEqual(lastDay.loanRepaid, Money(300_000_000))
        // The year closed that midnight owes nothing on term loans.
        XCTAssertEqual(world.accounts.years.last?.closing.termLoans, .zero)
        XCTAssertNil(world.accountsProblem())

        // A year split into many calls pays the same.
        var stepped = try self.world()
        try stepped.takeTermLoan(principal: Money(300_000_000), years: 1)
        for _ in 0..<360 { try stepped.advance(ticks: Int(day)) }
        try stepped.advance(ticks: 1)
        XCTAssertEqual(stepped, world)
    }

    func testAClosedYearKeepsWhatWasOwedAtItsEnd() throws {
        var world = try world()
        try world.takeTermLoan(principal: Money(300_000_000), years: 2)
        try world.advance(ticks: Int(360 * day) + 1)
        let closing = try XCTUnwrap(world.accounts.years.last?.closing)
        XCTAssertEqual(closing.termLoans, Money(300_000_000))
        XCTAssertEqual(closing.totalAssets, closing.loan + closing.termLoans + closing.equity)
        XCTAssertNil(world.accountsProblem())
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testSavesWithoutATermLoanAreUnchangedAndBadOnesAreRefused() throws {
        var world = try world()
        let before = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertFalse(before.contains("ermLoan"))
        try world.takeTermLoan(principal: Money(300_000_000), years: 2)
        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)

        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var accounts = try XCTUnwrap(object["accounts"] as? [String: Any])
        let loan = try XCTUnwrap((accounts["termLoans"] as? [[String: Any]])?.first)
        XCTAssertEqual(accounts["nextTermLoanID"] as? Int, 2)
        func refused(_ change: (inout [String: Any]) -> Void, _ accountsChange: [String: Any] = [:], line: UInt = #line) throws {
            var bad = loan
            change(&bad)
            var badAccounts = accounts
            badAccounts["termLoans"] = [bad]
            for (key, value) in accountsChange { badAccounts[key] = value }
            object["accounts"] = badAccounts
            let broken = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: broken), line: line)
        }
        try refused { $0["principal"] = 300_000_001 }
        try refused { $0["principal"] = 0 }
        try refused { $0["interest"] = 30_600_100 }
        try refused { $0["rate"] = 500 }
        try refused { $0["years"] = 11 }
        try refused { $0["borrowedDay"] = 1 }
        try refused { $0["id"] = 2 }
        try refused({ _ in }, ["nextTermLoanID": 1])
        accounts["termLoans"] = [loan, loan]
        object["accounts"] = accounts
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: try JSONSerialization.data(withJSONObject: object)))
    }

    /// A version 93 save keeps the term loans, the year closed with one
    /// owed, and runs on to pay it. Written with `TERM_LOAN_SAVE_NEW=1`, as
    /// the save was first made.
    func testTheSaveKeepsTheTermLoans() throws {
        var world = try world()
        try world.takeTermLoan(principal: Money(300_000_000), years: 2)
        try world.advance(ticks: Int(360 * day) + 1)
        try world.takeTermLoan(principal: Money(90_000_000), years: 10)

        // The file is version 93's, whatever this build writes: never
        // written again under a later version's name.
        let url = SavedGameTests.fixtures.appendingPathComponent("v93-term-loans.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["TERM_LOAN_SAVE_NEW"] != nil, SavedGame.currentVersion == 93 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"saveVersion\" : 93"), "the fixture is a version 93 save")
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.accounts.termLoans.map(\.id), [1, 2])
        XCTAssertEqual(loaded.accounts.termLoans.map(\.dueDay), [720, 3_960])
        XCTAssertEqual(loaded.accounts.years.last?.closing.termLoans, Money(300_000_000))
        // It runs on as the game it was saved from, and pays the first.
        try loaded.advance(ticks: Int(360 * day))
        try world.advance(ticks: Int(360 * day))
        XCTAssertEqual(loaded.accounts.termLoans.map(\.id), [2])
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), try encoder.encode(SavedGame(world: world)))
    }
}
