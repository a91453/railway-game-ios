import GameCore
@testable import GamePresentation
import XCTest

/// Decision 717: the pages of the company's figures over the whole screen,
/// what each holds and when a page stands in two columns.
final class EconomyLayoutTests: XCTestCase {
    private func facts(
        unlimitedFunds: Bool = false, showsTermLoans: Bool = true, hasToday: Bool = true, hasScenario: Bool = false,
        hasPunctuality: Bool = false
    ) -> EconomyLayout.Facts {
        EconomyLayout.Facts(
            unlimitedFunds: unlimitedFunds, showsTermLoans: showsTermLoans, hasToday: hasToday, hasScenario: hasScenario,
            hasPunctuality: hasPunctuality
        )
    }

    private func everyFacts() -> [EconomyLayout.Facts] {
        var all: [EconomyLayout.Facts] = []
        for bits in 0..<32 {
            all.append(facts(
                unlimitedFunds: bits & 1 != 0, showsTermLoans: bits & 2 != 0, hasToday: bits & 4 != 0, hasScenario: bits & 8 != 0,
                hasPunctuality: bits & 16 != 0
            ))
        }
        return all
    }

    func testAManagedCompanyHasFourPagesInOrder() {
        let layout = EconomyLayout(facts())
        XCTAssertEqual(layout.pages, [.overview, .loans, .fares, .reports])
        XCTAssertEqual(layout.columns(of: .overview).leading, [.balance, .today, .shortcuts, .mode])
        XCTAssertEqual(layout.columns(of: .overview).trailing, [.trend])
        XCTAssertEqual(layout.columns(of: .loans).all, [.loan, .termLoans])
        XCTAssertEqual(layout.columns(of: .fares).all, [.fares, .dayPass])
        XCTAssertEqual(layout.columns(of: .reports).leading, [.report])
        XCTAssertEqual(layout.columns(of: .reports).trailing, [.lastHour, .balanceSheet, .closedYears, .ledger])
    }

    func testTheBalanceIsTheFirstThingOnTheOverviewWhateverTheWorld() {
        for facts in everyFacts() {
            XCTAssertEqual(EconomyLayout(facts).columns(of: .overview).all.first, .balance, "\(facts)")
        }
    }

    func testTheChallengeAndThePunctualityShowOnlyWhenThereAreAny() {
        let plain = EconomyLayout(facts(hasToday: false))
        XCTAssertEqual(plain.columns(of: .overview).leading, [.balance, .shortcuts, .mode])
        let full = EconomyLayout(facts(hasScenario: true, hasPunctuality: true))
        XCTAssertEqual(full.columns(of: .overview).leading, [.balance, .today, .goals, .shortcuts, .mode])
        XCTAssertEqual(full.columns(of: .overview).trailing, [.trend, .punctuality])
    }

    func testUnlimitedFundsHaveNoLoanAndNoBalanceSheet() {
        // Decision 200. With term loans still to pay back (decision 715),
        // the loans page is theirs alone.
        let owing = EconomyLayout(facts(unlimitedFunds: true, showsTermLoans: true))
        XCTAssertEqual(owing.pages, [.overview, .loans, .fares, .reports])
        XCTAssertEqual(owing.columns(of: .loans).all, [.termLoans])
        XCTAssertFalse(owing.columns(of: .reports).all.contains(.balanceSheet))
        // With none, there is no loans page at all.
        let free = EconomyLayout(facts(unlimitedFunds: true, showsTermLoans: false))
        XCTAssertEqual(free.pages, [.overview, .fares, .reports])
        XCTAssertNil(free.page(of: .loan))
        XCTAssertNil(free.page(of: .termLoans))
    }

    func testEverySectionShownIsOnExactlyOnePage() {
        for facts in everyFacts() {
            let layout = EconomyLayout(facts)
            let shown = layout.pages.flatMap { layout.columns(of: $0).all }
            XCTAssertEqual(Set(shown).count, shown.count, "no section twice: \(facts)")
            for section in shown {
                XCTAssertNotNil(layout.page(of: section))
            }
            // What never depends on the world is always there.
            for section in [EconomySection.balance, .trend, .shortcuts, .mode, .fares, .dayPass, .report, .lastHour, .closedYears, .ledger] {
                XCTAssertTrue(shown.contains(section), "\(section) with \(facts)")
            }
            XCTAssertFalse(layout.pages.isEmpty)
            XCTAssertEqual(layout.pages.first, .overview)
        }
    }

    func testTheInsolvencyBubbleOpensTheLoansWhereBorrowIs() {
        // Decision 336: the bubble lands on Borrow.
        let layout = EconomyLayout(facts())
        XCTAssertEqual(layout.opening(at: .loans), .loans)
        XCTAssertEqual(layout.page(of: .loan), .loans)
        XCTAssertEqual(layout.opening(at: nil), .overview)
        // A page that is not there opens the overview instead.
        let free = EconomyLayout(facts(unlimitedFunds: true, showsTermLoans: false))
        XCTAssertEqual(free.opening(at: .loans), .overview)
        XCTAssertEqual(free.showing(.loans), .overview)
        XCTAssertEqual(free.showing(.reports), .reports)
    }

    func testAPageStandsInTwoColumnsOnlyWhereBothFit() {
        let layout = EconomyLayout(facts())
        for page in layout.pages {
            XCTAssertTrue(layout.isSplit(page, width: 734, accessibilitySize: false), "a phone on its side: \(page)")
            XCTAssertFalse(layout.isSplit(page, width: 639, accessibilitySize: false), "a narrow window: \(page)")
            XCTAssertFalse(layout.isSplit(page, width: 1_024, accessibilitySize: true), "large text: \(page)")
        }
        XCTAssertTrue(layout.isSplit(.overview, width: EconomyLayout.twoColumnWidth, accessibilitySize: false))
        // One column when the other would be empty.
        let noTermLoans = EconomyLayout(facts(showsTermLoans: false))
        XCTAssertFalse(noTermLoans.isSplit(.loans, width: 1_024, accessibilitySize: false))
        XCTAssertEqual(noTermLoans.columns(of: .loans).all, [.loan])
    }

    func testOneColumnHoldsTheSameSectionsAsTwo() {
        for facts in everyFacts() {
            let layout = EconomyLayout(facts)
            for page in layout.pages {
                let columns = layout.columns(of: page)
                XCTAssertEqual(columns.all, columns.leading + columns.trailing)
                XCTAssertFalse(columns.all.isEmpty)
            }
        }
    }

    func testThePagesHaveNamesInBothLanguages() {
        XCTAssertEqual(EconomyPage.allCases.map { $0.title(in: .english) }, ["Overview", "Loans", "Fares", "Reports"])
        XCTAssertEqual(EconomyPage.allCases.map { $0.title(in: .traditionalChinese) }, ["總覽", "借款", "票價", "報表"])
    }

    func testTheFactsAreReadFromTheWorld() throws {
        var world = GameWorld(
            bounds: try WorldBounds(width: 8_192, height: 6_144),
            economy: GameEconomy(balance: 2_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 5_000)),
            clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        let facts = EconomyLayout.Facts(world: world)
        XCTAssertFalse(facts.unlimitedFunds)
        XCTAssertTrue(facts.showsTermLoans)
        XCTAssertTrue(facts.hasToday, "a managed company has a day's account")
        XCTAssertFalse(facts.hasScenario)
        XCTAssertFalse(facts.hasPunctuality)
        XCTAssertEqual(EconomyLayout(world: world).pages, [.overview, .loans, .fares, .reports])
        // Free play charges no fares and pays nothing: no "Today".
        world.setEconomyMode(.free)
        XCTAssertFalse(EconomyLayout.Facts(world: world).hasToday)
        XCTAssertEqual(EconomyLayout(world: world).columns(of: .overview).leading, [.balance, .shortcuts, .mode])
    }
}
