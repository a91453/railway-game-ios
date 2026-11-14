@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 751: the year-end appraisal, its grades and its achievements.
final class YearEndAppraisalTests: XCTestCase {
    private let zero = AssetClassBalance.zero

    private func statement(year: Int64, fares: Int64, cost: Int64 = 200, cash: Int64 = 1_000, loan: Int64 = 0) -> AnnualStatement {
        let income = FinanceSummary(
            index: year, fareRevenue: Money(fares), operatingCost: Money(cost), maintenanceCost: .zero, energyCost: .zero,
            staffCost: .zero, interestCost: .zero
        )
        let sheet = BalanceSheet(cash: Money(cash), track: zero, stations: zero, rollingStock: zero, loan: Money(loan))
        return AnnualStatement(year: year, income: income, closing: sheet)
    }

    /// Both years' every day with `before` and `now` riders.
    private func riders(year: Int64, before: Int64, now: Int64) -> [DayAccount] {
        let length = FinancePeriod.year.days
        return ((year - 1) * length..<(year + 1) * length).map { day in
            var account = DayAccount(day: day)
            account.fareTrips = day / length == year ? now : before
            return account
        }
    }

    func testAGoodYearIsAllA() {
        var world = GameWorld.newGame()
        let last = statement(year: 0, fares: 1_000)
        let this = statement(year: 1, fares: 1_200)
        world.accounts.years = [last, this]
        world.accounts.days = riders(year: 1, before: 100, now: 120)
        let appraisal = YearEndAppraisal(statement: this, previous: last, world: world)
        XCTAssertEqual(appraisal.rows.map(\.item), YearEndAppraisal.Item.allCases)
        XCTAssertEqual(appraisal.grades, [.a, .a, .a, .a], "punctuality not graded without timed trips")
        XCTAssertNil(appraisal.rows.last?.grade)
        XCTAssertTrue(appraisal.isAllA)
        XCTAssertEqual(appraisal.gradesText, "A A A A —")
        XCTAssertEqual(appraisal.rows[1].detail(in: .traditionalChinese), "比去年 +20.0%")
        XCTAssertEqual(appraisal.rows[3].detail(in: .english), "0.0% of assets")
        XCTAssertTrue(appraisal.taxesDue.isEmpty, "no annual taxes")
    }

    func testTheFirstYearCannotBeAllA() {
        var world = GameWorld.newGame()
        let first = statement(year: 0, fares: 1_000)
        world.accounts.years = [first]
        let appraisal = YearEndAppraisal(statement: first, previous: nil, world: world)
        XCTAssertEqual(appraisal.rows[0].grade, .a)
        XCTAssertNil(appraisal.rows[1].grade)
        XCTAssertNil(appraisal.rows[2].grade)
        XCTAssertFalse(appraisal.isAllA, "nothing to grow on")
    }

    func testGradesFollowTheThresholds() {
        // Growth: +10 % is A, 0 % B, below C.
        XCTAssertEqual(YearEndAppraisal.growthRow(.revenueGrowth, now: 110, before: 100).grade, .a)
        XCTAssertEqual(YearEndAppraisal.growthRow(.revenueGrowth, now: 109, before: 100).grade, .b)
        XCTAssertEqual(YearEndAppraisal.growthRow(.revenueGrowth, now: 100, before: 100).grade, .b)
        XCTAssertEqual(YearEndAppraisal.growthRow(.revenueGrowth, now: 99, before: 100).grade, .c)
        XCTAssertEqual(YearEndAppraisal.growthRow(.revenueGrowth, now: 99, before: 100).detail(in: .english), "-1.0% on last year")
        // Profit: a loss is C, less than last year B.
        XCTAssertEqual(YearEndAppraisal.netProfitRow(statement(year: 1, fares: 100), nil).grade, .c)
        XCTAssertEqual(YearEndAppraisal.netProfitRow(statement(year: 1, fares: 500), statement(year: 0, fares: 900)).grade, .b)
        // Debt: 30 % A, 60 % B, above C; assets below zero C.
        func debt(_ loan: Int64) -> AppraisalGrade? {
            YearEndAppraisal.debtRow(BalanceSheet(cash: Money(1_000), track: zero, stations: zero, rollingStock: zero, loan: Money(loan))).grade
        }
        XCTAssertEqual(debt(300), .a)
        XCTAssertEqual(debt(301), .b)
        XCTAssertEqual(debt(600), .b)
        XCTAssertEqual(debt(601), .c)
        XCTAssertEqual(YearEndAppraisal.debtRow(BalanceSheet(cash: Money(-1), track: zero, stations: zero, rollingStock: zero, loan: .zero)).grade, .c)
        // Punctuality: 95 % A, 85 % B.
        XCTAssertEqual(YearEndAppraisal.punctualityRow(trips: 100, late: 5).grade, .a)
        XCTAssertEqual(YearEndAppraisal.punctualityRow(trips: 100, late: 6).grade, .b)
        XCTAssertEqual(YearEndAppraisal.punctualityRow(trips: 100, late: 16).grade, .c)
    }

    func testRidershipNeedsEnoughDaysOfBothYears() {
        let length = FinancePeriod.year.days
        let full = (0..<2 * length).map { (day: $0, trips: $0 < length ? Int64(100) : Int64(90)) }
        XCTAssertEqual(YearEndAppraisal.ridershipRow(year: 1, days: full).grade, .c)
        // The accounts dropping the year before's first days still grade
        // on the days both keep.
        XCTAssertEqual(YearEndAppraisal.ridershipRow(year: 1, days: Array(full.dropFirst(50))).grade, .c)
        XCTAssertNil(YearEndAppraisal.ridershipRow(year: 1, days: Array(full.dropFirst(61))).grade)
    }

    func testAnnualTaxesShowWhatTheNewestYearOwes() {
        var world = GameWorld.newGame()
        world.annualTaxes = true
        let this = statement(year: 0, fares: 1_000)
        world.accounts.years = [this]
        world.accounts.incomeTaxPayable = Money(300)
        world.accounts.houseTaxPayable = Money(200)
        world.accounts.landTaxPayable = Money(100)
        let appraisal = YearEndAppraisal(statement: this, previous: nil, world: world)
        XCTAssertEqual(appraisal.taxesDue.map(\.month), [5, 11])
        XCTAssertEqual(appraisal.taxesDue.map(\.amount), [Money(500), Money(100)])
        XCTAssertEqual(appraisal.taxDueText(appraisal.taxesDue[0], in: .traditionalChinese), "5 月底要繳稅 \(Money(500).moneyText)")
        // An older year owes nothing more.
        world.accounts.years = [this, statement(year: 1, fares: 1_000)]
        XCTAssertTrue(YearEndAppraisal(statement: this, previous: nil, world: world).taxesDue.isEmpty)
    }

    func testTheAchievementsReadTheYears() throws {
        var world = GameWorld.newGame()
        world.accounts.years = [0, 1, 2, 3].map { statement(year: $0, fares: 1_000 + 100 * $0) }
        var facts = AchievementFacts(world: world)
        XCTAssertEqual(facts.profitGrowthYears, 3)
        XCTAssertFalse(facts.yearEndAllA, "the newest year is not last year on day 0")
        let growth = try XCTUnwrap(Achievement.named("profitGrowth3"))
        XCTAssertTrue(growth.isMet(by: facts))
        world.accounts.years[1] = statement(year: 1, fares: 2_000)
        XCTAssertEqual(AchievementFacts(world: world).profitGrowthYears, 1, "the run starts again after a fall")
        let allA = try XCTUnwrap(Achievement.named("yearEndAllA"))
        XCTAssertFalse(allA.isMet(by: facts))
        facts.yearEndAllA = true
        XCTAssertTrue(allA.isMet(by: facts))
    }
}
