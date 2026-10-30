@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 480: the economy panel's income and cost donuts.
final class FinanceCompositionTests: XCTestCase {
    private func summary(
        fares: Money = .zero, freight: Money = .zero, rent: Money = .zero,
        operating: Money = .zero, maintenance: Money = .zero, energy: Money = .zero, staff: Money = .zero,
        buildings: Money = .zero, interest: Money = .zero, depreciation: Money = .zero, writeOff: Money = .zero,
        tax: Money = .zero, sold: Money = .zero, bookValue: Money = .zero
    ) -> FinanceSummary {
        var summary = FinanceSummary(
            index: 0, fareRevenue: fares, operatingCost: operating, maintenanceCost: maintenance, energyCost: energy,
            staffCost: staff, interestCost: interest
        )
        summary.freightRevenue = freight
        summary.propertyRevenue = rent
        summary.propertyCost = buildings
        summary.depreciationCost = depreciation
        summary.writeOffCost = writeOff
        summary.taxCost = tax
        summary.saleProceeds = sold
        summary.saleBookValue = bookValue
        return summary
    }

    func testTheRingsAddUpToTheReportsIncomeAndCosts() {
        let report = summary(
            fares: 900_000, freight: 250_000, rent: 120_000, operating: 300_000, maintenance: 200_000, energy: 150_000,
            staff: 100_000, buildings: 60_000, interest: 40_000, depreciation: 30_000, writeOff: 5_000, tax: 20_000,
            sold: 500_000, bookValue: 100_000
        )
        let composition = FinanceComposition(report)
        let income = report.fareRevenue + report.freightRevenue + report.propertyRevenue
        let costs = report.totalCost + report.propertyCost + report.interestCost + report.depreciationCost
            + report.writeOffCost + report.taxCost
        XCTAssertEqual(composition.income.total, income)
        XCTAssertEqual(composition.income.slices.reduce(Money.zero) { $0 + $1.amount }, income)
        XCTAssertEqual(composition.costs.total, costs)
        XCTAssertEqual(composition.costs.slices.reduce(Money.zero) { $0 + $1.amount }, costs)
        // Income less costs is the net profit, but for the buildings sold.
        XCTAssertEqual(income - costs + report.realizedGain, report.netProfit)
        XCTAssertEqual(composition.income.slices.map(\.category), [.fares, .freight, .sideBusiness])
    }

    func testSmallKindsFoldIntoOther() {
        // Interest ($ 20) and tax ($ 10) are under 3% of $ 3,030.
        let composition = FinanceComposition(summary(operating: 200_000, maintenance: 100_000, interest: 2_000, tax: 1_000))
        let ring = composition.costs
        XCTAssertEqual(ring.slices.map(\.category), [.operating, .maintenance, .other])
        XCTAssertEqual(ring.slices.last?.amount, 3_000)
        XCTAssertEqual(ring.slices.last?.folded, [.interest, .tax])
        XCTAssertEqual(ring.percentText(of: ring.slices[0]), "66%")
        XCTAssertEqual(ring.percentText(of: ring.slices[2]), "1%")
        XCTAssertEqual(
            ring.detailText(of: ring.slices[2], in: .english), "Other (Loan interest, Income tax) · \(Money(3_000).moneyText) · 1%"
        )
        XCTAssertEqual(ring.detailText(of: ring.slices[2], in: .traditionalChinese), "其他（貸款利息、營利事業所得稅） · \(Money(3_000).moneyText) · 1%")
    }

    func testOneSmallKindKeepsItsName() {
        let ring = FinanceComposition(summary(fares: 990_000, freight: 10_000)).income
        XCTAssertEqual(ring.slices.map(\.category), [.fares, .freight])
        XCTAssertEqual(ring.percentText(of: ring.slices[1]), "1%")
        let tiny = FinanceComposition(summary(fares: 1_000_000, freight: 1)).income
        XCTAssertEqual(tiny.percentText(of: tiny.slices[1]), "<1%")
    }

    func testARingHasAtMostSixSlices() {
        // Eight kinds, each over 3%: the two smallest become "Other".
        let ring = FinanceComposition(summary(
            operating: 800, maintenance: 700, energy: 600, staff: 500, buildings: 400, interest: 300, depreciation: 200,
            tax: 100
        )).costs
        XCTAssertEqual(ring.slices.count, FinanceComposition.maximumSlices)
        XCTAssertEqual(ring.slices.map(\.category), [.operating, .maintenance, .energy, .staff, .sideBusinessCost, .other])
        XCTAssertEqual(ring.slices.last?.folded, [.interest, .depreciation, .tax])
        XCTAssertEqual(ring.slices.last?.amount, 600)
    }

    func testNothingIsDrawnWhenEverythingIsZero() {
        let composition = FinanceComposition(summary())
        XCTAssertTrue(composition.isEmpty)
        XCTAssertTrue(composition.income.slices.isEmpty)
        XCTAssertEqual(composition.income.summaryText(in: .english), "No income this period")
        // A negative kind counts as nothing.
        XCTAssertTrue(FinanceComposition(summary(fares: -500)).isEmpty)
        // Costs alone still draw their ring.
        let costsOnly = FinanceComposition(summary(operating: 1_000))
        XCTAssertFalse(costsOnly.isEmpty)
        XCTAssertTrue(costsOnly.income.isEmpty)
    }

    func testTheSharesAddUpToAHundred() {
        // Thirds: 33.3% each, rounded down to 99; the first takes the point.
        let thirds = FinanceComposition(summary(fares: 100, freight: 100, rent: 100)).income
        XCTAssertEqual(thirds.slices.map { thirds.percentText(of: $0) }, ["34%", "33%", "33%"])
        let costs = FinanceComposition(summary(
            operating: 382_206_00, maintenance: 7_000_00, energy: 6_000_00, staff: 5_000_00, interest: 4_955_88, tax: 91_014_00
        )).costs
        XCTAssertEqual(costs.percents.reduce(0, +), 100)
        XCTAssertEqual(FinanceComposition.wholePercents(of: []), [])
        XCTAssertEqual(FinanceComposition.wholePercents(of: [.zero, .zero]), [0, 0])
    }

    func testNoAccountsReadsADashNotZero() {
        let none = FinanceComposition(summary(), hasRecords: false)
        XCTAssertEqual(none.income.totalText, "—")
        XCTAssertEqual(none.costs.summaryText(in: .english), "No accounts yet")
        XCTAssertEqual(none.costs.summaryText(in: .traditionalChinese), "還沒有帳目")
        let zero = FinanceComposition(summary())
        XCTAssertEqual(zero.income.totalText, "\(Money(0).moneyText)")
        XCTAssertEqual(zero.costs.summaryText(in: .traditionalChinese), "本期沒有支出")
    }

    func testColoursFollowTheKindNotItsRank() {
        let a = FinanceComposition(summary(fares: 100, freight: 900)).income
        let b = FinanceComposition(summary(fares: 900, freight: 100)).income
        XCTAssertEqual(a.slices.map(\.category.colorSlot), [2, 1])
        XCTAssertEqual(b.slices.map(\.category.colorSlot), [1, 2])
        XCTAssertEqual(FinanceComposition.Category.tax.colorSlot, 8)
        XCTAssertEqual(FinanceComposition.Category.other.colorSlot, 0)
    }

    func testTheTouchedAngleFindsItsSlice() {
        // $ 75 fares, $ 25 freight.
        let ring = FinanceComposition(summary(fares: 7_500, freight: 2_500)).income
        XCTAssertEqual(ring.slice(atDollars: 0)?.category, .fares)
        XCTAssertEqual(ring.slice(atDollars: 74.9)?.category, .fares)
        XCTAssertEqual(ring.slice(atDollars: 75)?.category, .freight)
        XCTAssertNil(ring.slice(atDollars: 100))
    }

    func testTheAudioGraphListsTheSlices() {
        let ring = FinanceComposition(summary(fares: 7_500, freight: 2_500)).income
        let chart = ring.chart(in: .english)
        XCTAssertEqual(chart.title, "Income by kind")
        XCTAssertEqual(chart.xLabels, ["Fares", "Freight"])
        XCTAssertEqual(chart.series.first?.values, [75, 25])
        XCTAssertEqual(chart.summary, "Income \(Money(10_000).moneyText), most from Fares (75%)")
        XCTAssertEqual(ring.summaryText(in: .traditionalChinese), "收入 \(Money(10_000).moneyText)，最多是票價收入（75%）")
    }
}
