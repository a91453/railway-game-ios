@testable import GameCore
import GamePresentation
import XCTest

/// Decision 739 (ANNUAL-FINANCE AF-3a): with the annual taxes, the station
/// master says a month ahead what tax falls due and whether the cash
/// covers it; the fares show the business tax they include; the simple
/// rules' income tax says it is the daily one.
final class TaxReminderTests: XCTestCase {
    /// A managed world with the annual taxes that earned NT$900,000 on its
    /// first year's last day and is a minute into the second, owing
    /// NT$180,000 of income tax at the end of its fifth month.
    private func owingWorld() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: Money(1_000_000), speed: .normal)
        world.setEconomyMode(.management)
        world.setAnnualTaxes(true)
        try world.advance(ticks: 359 * 1_440 + 1)
        let fares = Money(90_000_000)
        world.write(LedgerEntry(
            kind: .hourlyNet, time: world.clock.now, amount: fares,
            breakdown: [
                LedgerLine(item: .fareRevenue, amount: fares), LedgerLine(item: .operatingCost, amount: .zero),
                LedgerLine(item: .maintenanceCost, amount: .zero),
            ],
            crowding: CrowdingMetrics(crowdedStations: 0, fullTrains: 0, maxWaiting: 0, maxLoad: 0)
        ), day: world.dayIndex(of: world.clock.now))
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.accounts.incomeTaxPayable, Money(18_000_000))
        return world
    }

    func testTheStationMasterSaysAMonthAhead() throws {
        var world = try owingWorld()
        XCTAssertNil(StationMasterAdvice.taxDue(in: world), "five months ahead")
        // The fourth month's last day: 31 days to go, not yet.
        try world.advance(ticks: 119 * 1_440)
        XCTAssertNil(StationMasterAdvice.taxDue(in: world))
        try world.advance(ticks: 1_440)
        let due = StationMasterAdvice.taxDue(year: 2, month: 5, days: 30, amount: Money(18_000_000), enough: true)
        XCTAssertEqual(StationMasterAdvice.taxDue(in: world), due)
        XCTAssertFalse(due.isWorry)
        XCTAssertEqual(due.text(in: .traditionalChinese), "5 月底要繳稅 \(Money(18_000_000).moneyText)（還有 30 天）。現金夠，先留著別花掉。")
        XCTAssertEqual(
            due.text(in: .english), "\(Money(18_000_000).moneyText) of tax is due at the end of month 5, in 30 days. We have the cash; keep it until then."
        )
        // The due day itself: tonight.
        try world.advance(ticks: 29 * 1_440)
        XCTAssertEqual(
            StationMasterAdvice.taxDue(in: world), .taxDue(year: 2, month: 5, days: 1, amount: Money(18_000_000), enough: true)
        )
        // Paid at its midnight: nothing more to say.
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.accounts.incomeTaxPayable, .zero)
        XCTAssertNil(StationMasterAdvice.taxDue(in: world))
    }

    func testCashThatDoesNotCoverItIsAWorry() throws {
        var world = try owingWorld()
        try world.advance(ticks: 120 * 1_440)
        try world.economy.spend(world.economy.balance - Money(100))
        let due = try XCTUnwrap(StationMasterAdvice.taxDue(in: world))
        XCTAssertEqual(due, .taxDue(year: 2, month: 5, days: 30, amount: Money(18_000_000), enough: false))
        XCTAssertTrue(due.isWorry)
        // A worry comes before the first line's next step.
        XCTAssertEqual(StationMasterAdvice(world: world), due)
        XCTAssertEqual(due.text(in: .traditionalChinese), "5 月底要繳稅 \(Money(18_000_000).moneyText)（還有 30 天），現金不夠。這段時間少蓋一點，或先向銀行借款。")
    }

    func testTheLandTaxIsSaidBeforeTheEleventhMonthsEnd() throws {
        var world = try owingWorld()
        world.accounts.landTaxPayable = Money(500_000)
        try world.advance(ticks: 300 * 1_440)
        XCTAssertEqual(
            StationMasterAdvice.taxDue(in: world), .taxDue(year: 2, month: 11, days: 30, amount: Money(500_000), enough: true)
        )
    }

    func testWithoutTheAnnualTaxesNothingIsSaid() throws {
        var world = try owingWorld()
        try world.advance(ticks: 120 * 1_440)
        world.setAnnualTaxes(false)
        XCTAssertNil(StationMasterAdvice.taxDue(in: world))
    }

    func testTheFaresShowTheirBusinessTax() {
        XCTAssertEqual(FinanceSummary.businessTax(in: .zero), .zero)
        XCTAssertEqual(FinanceSummary.businessTax(in: Money(-100)), .zero)
        // NT$105: NT$5.
        XCTAssertEqual(FinanceSummary.businessTax(in: Money(10_500)), Money(500))
        // NT$104.99: NT$104 of whole dollars, NT$4.95 rounded down.
        XCTAssertEqual(FinanceSummary.businessTax(in: Money(10_499)), Money(400))
    }
}
