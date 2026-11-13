import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// HEALTH-129 (`docs/research/HEALTH_129_2026-11-13.md`): what the term
/// loans of decision 715 do to a company's cash, beside the loan of
/// decision 67, printed as Markdown. It asserts nothing but that the rules
/// answer, and runs only on request:
///
///     swift build -c release -Xswiftc -enable-testing --build-tests
///     TERM_LOAN_REPORT=800 swift test -c release --skip-build --filter TermLoanReportTests
///
/// `TERM_LOAN_REPORT` is the days played after day 30 (800 reaches past a
/// two-year loan's due day); `TERM_LOAN_KIND` the business bought with the
/// money (a `PlacedBuildingKind`, the amusement park without it).
///
/// The game is decision 137's line between two towns. On day 30:
///
/// - what the bank lends (``GameWorld/termLoanCredit()``) and what each
///   term costs, and what borrowing and paying back the same day costs;
/// - games that only hold the money a year: none borrowed, the most of a
///   one-year term loan, and the loan of decision 67 in full, so what each
///   costs after tax is the cash it ends with less the first game's;
/// - games that buy a business the first day the cash pays for it: with
///   nothing borrowed, with the loan of decision 67, with the most of a
///   two-year term loan, and with both; the days each stood in the red
///   after the term loan fell due;
/// - whether a company with a term loan can switch to free play, where no
///   day is settled and so no term loan ever falls due.
@MainActor
final class TermLoanReportTests: XCTestCase {
    func testWhatTermLoansDoToACompany() throws {
        guard let value = ProcessInfo.processInfo.environment["TERM_LOAN_REPORT"] else {
            throw XCTSkip("set TERM_LOAN_REPORT=<days> to print the term loan report")
        }
        let days = try XCTUnwrap(Int(value).flatMap { $0 > 0 ? $0 : nil }, "TERM_LOAN_REPORT is a whole number of days")
        let kind = try ProcessInfo.processInfo.environment["TERM_LOAN_KIND"].map {
            try XCTUnwrap(PlacedBuildingKind(rawValue: $0), "TERM_LOAN_KIND is a PlacedBuildingKind")
        } ?? .amusementPark
        func dollars(_ money: Money) -> String { (money.amount / 100).groupedText }
        func note(_ text: String) { FileHandle.standardError.write(Data("\(text)\n".utf8)) }

        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var base = try newGameLine(through: [towns[0], towns[1]])
        try base.advance(ticks: 1)
        try base.advance(ticks: 30 * 1_440)
        var out: [String] = []

        // What the bank lends on day 30, and what each term costs.
        let credit = base.termLoanCredit()
        let sheet = base.balanceSheet()
        out += [
            "### Day 30 of a line between two towns",
            "",
            "Cash \(dollars(base.economy.balance)); assets \(dollars(sheet.totalAssets)); net worth \(dollars(sheet.equity)). "
                + "Term loans: limit \(dollars(credit.limit)), the most a new one can be \(dollars(credit.maximumPrincipal)); "
                + "the loan of decision 67: \(dollars(CompanyAccounts.maximumLoan)).",
            "",
            "| Years | Rate | Interest on the most | Paid when due | Paid back the same day: interest | The most a second loan can be after it |",
            "| --: | --: | --: | --: | --: | --: |",
        ]
        for years in 1...CompanyAccounts.longestTermLoan {
            var world = base
            let loan = try world.takeTermLoan(principal: credit.maximumPrincipal, years: years)
            let back = try world.termLoanRepaymentQuote(loan.id)
            let next = world.termLoanCredit().maximumPrincipal
            XCTAssertGreaterThan(back.interest, .zero, "borrowing and paying back the same day is not free")
            out.append("| \(years) | \(Double(loan.rate) / 100)% | \(dollars(loan.interest)) | \(dollars(loan.total)) | \(dollars(back.interest)) | \(dollars(next)) |")
        }
        // The smallest loan there is, paid back the same day.
        do {
            var world = base
            let loan = try world.takeTermLoan(principal: CompanyAccounts.loanStep, years: 1)
            let back = try world.termLoanRepaymentQuote(loan.id)
            let before = world.economy.balance
            try world.repayTermLoanEarly(loan.id)
            out += ["", "The smallest loan (\(dollars(loan.principal)), 1 year, interest \(dollars(loan.interest))) paid back the same day costs "
                + "\(dollars(back.interest)); the cash went from \(dollars(base.economy.balance)) to \(dollars(world.economy.balance)) "
                + "(\(dollars(before - world.economy.balance)) paid back)."]
        }

        // Holding the money a year: what each loan costs after tax.
        struct Game {
            var name: String
            var world: GameWorld
            var red = 0
            var lowest = Money.zero
            var bought: (day: Int, cost: Money)?
            var borrowedOld = false
            var notes: [String] = []
        }
        var holds = [Game(name: "Nothing borrowed", world: base), Game(name: "Term loan, the most, 1 year, held", world: base),
                     Game(name: "Decision 67's loan in full, held 360 days", world: base)]
        let held = try holds[1].world.takeTermLoan(principal: credit.maximumPrincipal, years: 1)
        try holds[2].world.borrow(CompanyAccounts.maximumLoan)
        let holdDays = min(days, 362)
        var oldInterest = Money.zero
        for day in 1...holdDays {
            for index in holds.indices {
                try holds[index].world.advance(ticks: 1_440)
            }
            if day <= 360 { oldInterest = oldInterest + GameWorld.dailyLoanInterest(on: holds[2].world.accounts.loan) }
            if day == 360 { try holds[2].world.repayLoan(CompanyAccounts.maximumLoan) }
        }
        let plain = holds[0].world.economy.balance
        out += [
            "", "### Holding the money a year (day \(30 + holdDays))", "",
            "| Game | Borrowed | Interest paid | Cash | Cash less the first game's | So tax saved |", "| --- | --: | --: | --: | --: | --: |",
            "| \(holds[0].name) | 0 | 0 | \(dollars(plain)) | 0 | 0 |",
        ]
        for (game, borrowed, interest) in [(holds[1], held.principal, held.interest), (holds[2], CompanyAccounts.maximumLoan, oldInterest)] {
            let less = game.world.economy.balance - plain
            out.append("| \(game.name) | \(dollars(borrowed)) | \(dollars(interest)) | \(dollars(game.world.economy.balance)) | \(dollars(less)) | \(dollars(less + interest)) |")
        }
        note(out.joined(separator: "\n"))

        // Buying a business the first day the cash pays for it.
        let tile = Int64(1_024)
        let station = try XCTUnwrap(base.stations.first).location
        var sites: [PlanPoint] = []
        for ring in 3...9 {
            for (dx, dy) in [(0, 1), (1, 0), (0, -1), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)] as [(Int64, Int64)] {
                sites.append(PlanPoint(x: station.x + dx * Int64(ring) * tile, y: station.y + dy * Int64(ring) * tile))
            }
        }
        let price = try XCTUnwrap(sites.lazy.compactMap { base.placedBuildingQuote(kind, at: $0)?.total }.first, "no site for a \(kind)")
        var games = [Game(name: "Nothing borrowed", world: base), Game(name: "Decision 67's loan", world: base),
                     Game(name: "Term loan, the most, 2 years", world: base), Game(name: "Both", world: base)]
        try games[1].world.borrow(CompanyAccounts.maximumLoan)
        games[1].borrowedOld = true
        let two = try games[2].world.takeTermLoan(principal: credit.maximumPrincipal, years: 2)
        _ = try games[3].world.takeTermLoan(principal: credit.maximumPrincipal, years: 2)
        try games[3].world.borrow(CompanyAccounts.maximumLoan)
        games[3].borrowedOld = true
        let shown: Set<Int> = [1, 30, 90, 330, 690, 719, 720, 721, 750, 780, days]
        var rows = ["| Day | " + games.map { "\($0.name): cash / net worth" }.joined(separator: " | ") + " |",
                    "| --: |" + String(repeating: " --: |", count: games.count)]
        func buy(_ game: inout Game, day: Int) {
            guard game.bought == nil, game.world.economy.balance >= price else { return }
            for site in sites {
                if let placed = try? game.world.placeBuilding(kind, at: site) {
                    game.bought = (day, placed.cost)
                    return
                }
            }
        }
        for index in games.indices { buy(&games[index], day: 30) }
        for day in 1...days {
            for index in games.indices {
                try games[index].world.advance(ticks: 1_440)
                buy(&games[index], day: 30 + day)
                // The loan of decision 67 is paid back once the business is
                // bought and the cash covers it.
                if games[index].borrowedOld, games[index].bought != nil, games[index].world.economy.balance >= CompanyAccounts.maximumLoan {
                    try games[index].world.repayLoan(CompanyAccounts.maximumLoan)
                    games[index].borrowedOld = false
                    games[index].notes.append("decision 67's loan paid back on day \(30 + day)")
                }
                let cash = games[index].world.economy.balance
                if cash < .zero { games[index].red += 1 }
                games[index].lowest = min(games[index].lowest, cash)
            }
            if shown.contains(day) {
                rows.append("| \(30 + day) | " + games.map { "\(dollars($0.world.economy.balance)) / \(dollars($0.world.balanceSheet().equity))" }.joined(separator: " | ") + " |")
                note(rows.last!)
            }
        }
        out = ["", "### Buying a \(kind.rawValue) (\(dollars(price))) the first day the cash pays for it", "",
               "The two-year term loan: \(dollars(two.principal)) at \(Double(two.rate) / 100)%, \(dollars(two.total)) paid as day \(two.dueDay) begins.", ""]
        out += rows
        out += ["", "| Game | Bought on day | Days in the red | Lowest cash | Term loans left | Decision 67's loan left | Notes |", "| --- | --: | --: | --: | --: | --: | --- |"]
        for game in games {
            out.append("| \(game.name) | \(game.bought.map { "\($0.day)" } ?? "never") | \(game.red) | \(dollars(game.lowest)) | "
                + "\(game.world.accounts.termLoans.count) | \(dollars(game.world.accounts.loan)) | \(game.notes.joined(separator: "; ")) |")
        }

        // Free play with a term loan: no day is settled there.
        var owing = base
        let owed = try owing.takeTermLoan(principal: CompanyAccounts.loanStep, years: 1)
        let session = GameSession(world: owing, language: .english)
        session.setEconomyMode(.free)
        var free = session.world
        let switched = free.accounts.mode == .free
        if switched { try free.advance(ticks: 400 * 1_440) }
        out += ["", "### Free play with a term loan", "",
                switched
                    ? "A company owing a term loan of \(dollars(owed.principal)) switched to free play; 400 days on (its due day is \(owed.dueDay)) "
                        + "it still has \(free.accounts.termLoans.count) term loan and \(dollars(free.economy.balance)) cash: never paid."
                    : "A company owing a term loan could not switch to free play: \(session.message?.text ?? "")"]
        note(out.joined(separator: "\n"))
    }
}
