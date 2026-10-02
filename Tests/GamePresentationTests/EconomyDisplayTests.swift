import GameCore
import GamePresentation
import XCTest

/// G1c (decision 36): money, ledger rows, the last hour's totals, waiting
/// passengers and train loads as the panels show them, and the session's
/// economy commands.
final class EconomyDisplayTests: XCTestCase {
    func testMoneyIsShownInWholeDollarsRoundedAsTheReferenceDoes() {
        XCTAssertEqual(Money(0).moneyText, "$ 0")
        XCTAssertEqual(Money(1_234_549).moneyText, "$ 12,345")
        XCTAssertEqual(Money(1_234_550).moneyText, "$ 12,346", "half a dollar rounds up")
        XCTAssertEqual(Money(-142_800).moneyText, "$ -1,428")
        XCTAssertEqual(Money(-150).moneyText, "$ -1", "Math.round(-1.5) is -1")
        XCTAssertEqual(Money(-151).moneyText, "$ -2")
        XCTAssertEqual(Money(-49).moneyText, "$ 0")
        XCTAssertEqual(Money(Int64.max).moneyText, "$ 92,233,720,368,547,758")
        XCTAssertEqual(Money(Int64.min).moneyText, "$ -92,233,720,368,547,758")
        XCTAssertEqual(Money(55).centsText, "$ 0.55")
        XCTAssertEqual(Money(500).centsText, "$ 5.00")
        XCTAssertEqual(Money(123_405).centsText, "$ 1,234.05")
        XCTAssertEqual(FareRules.standard.displayText(in: .english), "Flat · $ 5.00")
        XCTAssertEqual(FareRules.distance(FareRules.standardBands).displayText(in: .english), "By distance · 5 steps from $ 0.55")
    }

    func testLedgerRowsAndTheLastHourAreReadFromTheAccounts() throws {
        var world = try makeLine()
        world.setEconomyMode(.management)
        // The hour that ends at 60 is settled as the step from 60 starts.
        try world.advance(ticks: 61)
        let row = try XCTUnwrap(world.recentLedgerEntries().first)
        XCTAssertEqual(row.kind.displayName(in: .english), "Hourly net")
        XCTAssertLessThan(row.amount, .zero, "running costs and no fares")
        XCTAssertEqual(row.amountText, "-\(Money(-row.amount.amount).moneyText)")
        let totals = world.recentLedgerTotals()
        XCTAssertEqual(totals.map(\.item), [.operatingCost, .maintenanceCost], "no fares without passengers")
        XCTAssertEqual(totals.reduce(Money.zero) { $0 + $1.amount }, row.amount)
        XCTAssertTrue(totals[0].amountText.hasPrefix("-$ "))

        try world.advance(ticks: 60)
        XCTAssertEqual(world.recentLedgerEntries().count, 2)
        XCTAssertEqual(world.recentLedgerEntries(1), [world.accounts.entries.last!], "newest first")
        XCTAssertEqual(world.recentLedgerTotals().reduce(Money.zero) { $0 + $1.amount }, world.accounts.entries.last!.amount, "only the last hour")
        XCTAssertEqual(LedgerItem.trainStaff.displayName(in: .english), "Drivers and dispatchers")
        XCTAssertEqual(FinancePeriod.month.displayName(in: .english), "Month")
    }

    func testWaitingPassengersAreShownByLineAndDirectionAndTrainsByLoad() throws {
        var world = try makeLine()
        let alpha = StationID(rawValue: 1)
        XCTAssertEqual(world.waitingText(at: alpha, in: .english), [])
        XCTAssertNil(world.waitingSummary(at: alpha, in: .english))
        XCTAssertNil(world.loadText(of: TrainID(rawValue: 1), in: .english))
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 200_000))
        try world.setStationDemand(StationID(rawValue: 3), to: StationDemand(kind: .office, dailyTrips: 1_000))
        try world.advance(ticks: 30)
        let waiting = world.waitingPassengers(at: alpha).reduce(Int64(0)) { $0 + $1.count }
        XCTAssertGreaterThan(waiting, 0)
        XCTAssertEqual(world.waitingText(at: alpha, in: .english), ["Main to Gamma · \(waiting)"])
        XCTAssertEqual(world.waitingSummary(at: alpha, in: .english), "waiting Main to Gamma · \(waiting)")
        XCTAssertEqual(world.waitingSummary(at: alpha, in: .traditionalChinese), "候車 Main 往 Gamma · \(waiting)")

        let riding = world.riders(of: TrainID(rawValue: 1)).reduce(Int64(0)) { $0 + $1.count }
        XCTAssertGreaterThan(riding, 0)
        let percent = (riding * 100 * 2 + 320) / 640
        XCTAssertEqual(world.loadText(of: TrainID(rawValue: 1), in: .english), "\(riding) riding · \(percent)%")
        XCTAssertEqual(world.loadText(of: TrainID(rawValue: 1), in: .traditionalChinese), "載客 \(riding) 人 · \(percent)%")
    }

    func testTheSessionSwitchesModeAndSetsFares() async throws {
        let world = try makeLine()
        await MainActor.run {
            let session = GameSession(world: world)
            session.setEconomyMode(.management)
            XCTAssertEqual(session.world.accounts.mode, .management)
            XCTAssertEqual(session.message?.kind, .success)
            session.setFareRules(.flat(-1))
            XCTAssertEqual(session.message?.kind, .failure)
            XCTAssertNil(session.world.accounts.fareRules)
            session.setFareRules(.distance(FareRules.standardBands))
            XCTAssertEqual(session.world.accounts.fareRules, .distance(FareRules.standardBands))
            XCTAssertEqual(session.message?.text, "Fares: By distance · 5 steps from $ 0.55.")
        }
    }

    /// Alpha(1,0) Beta(3,0) Gamma(5,0) on track (0,1)–(6,1), line Main
    /// calling at all three, one train of one car running it all day.
    private func makeLine() throws -> GameWorld {
        var world = try makeWorld(width: 8, height: 4, balance: 1_000_000, speed: .normal)
        try world.buildTrack(at: GridPosition(x: 0, y: 1), connections: .east)
        for x in 1...5 {
            try world.buildTrack(at: GridPosition(x: x, y: 1), connections: [.east, .west])
        }
        try world.buildTrack(at: GridPosition(x: 6, y: 1), connections: .west)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try world.buildStation(named: name, at: GridPosition(x: x, y: 0))
        }
        let main = LineID(rawValue: 1)
        try world.createLine(named: "Main", stops: [StationID(rawValue: 1), StationID(rawValue: 2), StationID(rawValue: 3)])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: .atNode(GridPosition(x: 1, y: 1), heading: .east))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.assignTrain(train.id, to: main)
        return world
    }
}
