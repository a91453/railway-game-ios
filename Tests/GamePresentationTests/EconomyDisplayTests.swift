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

    /// Decision 67: the loan's words and the session's loan commands.
    @MainActor
    func testTheLoanIsShownAndTakenInSteps() throws {
        XCTAssertEqual(CompanyAccounts().loanText(in: .english), "No loan")
        XCTAssertEqual(CompanyAccounts.loanTermsText(in: .english), "$ 100,000 at a time, up to $ 5,000,000, at 5% a year, paid daily")
        let session = GameSession(world: GameWorld.newGame())
        let balance = session.world.economy.balance
        session.borrowLoanStep()
        XCTAssertEqual(session.world.accounts.loan, CompanyAccounts.loanStep)
        XCTAssertEqual(session.world.economy.balance, balance + CompanyAccounts.loanStep)
        XCTAssertEqual(session.message?.text, "Borrowed $ 100,000.")
        XCTAssertEqual(session.world.accounts.loanText(in: .english), "Loan $ 100,000 · $ 14 a day in interest")
        XCTAssertEqual(session.world.accounts.loanText(in: .traditionalChinese), "貸款 $ 100,000 · 每日利息 $ 14")
        session.repayLoanStep()
        XCTAssertEqual(session.world.accounts.loan, .zero)
        session.repayLoanStep()
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(LedgerEntry.Kind.dailyInterest.displayName(in: .traditionalChinese), "貸款利息（日結）")
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
        // Stage W2c: the line sends its train out every 8 minutes; at 26 the
        // one sent out at 24 has left Alpha (24:42) with the passengers it
        // took on there and is due at Gamma at 26:14, and those who came
        // after it wait.
        try world.advance(ticks: 26)
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

    /// Decision 46: a managed company may switch to free play, which
    /// cannot become managed again (the reference loads a free-play save
    /// only in free play).
    func testTheSessionSwitchesToFreePlayOnlyOnceAndSetsFares() async throws {
        var world = try makeLine()
        world.setEconomyMode(.management)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.setEconomyMode(.free)
            XCTAssertEqual(session.world.accounts.mode, .free)
            XCTAssertEqual(session.message?.text, "Free play: no fares or running costs, and you set each station's ridership.")
            session.setEconomyMode(.management)
            XCTAssertEqual(session.world.accounts.mode, .free)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .failure, text: "Free play cannot become a managed company again. Start a new game to manage one.")
            )
            session.setFareRules(.flat(-1))
            XCTAssertEqual(session.message?.kind, .failure)
            XCTAssertNil(session.world.accounts.fareRules)
            session.setFareRules(.distance(FareRules.standardBands))
            XCTAssertEqual(session.world.accounts.fareRules, .distance(FareRules.standardBands))
            XCTAssertEqual(session.message?.text, "Fares: By distance · 5 steps from $ 0.55.")
        }
    }

    /// The cars stepper charges on every step up and never pays back, so the
    /// price is shown beside it (nothing when cars are free).
    func testTheCarPriceIsShownBesideTheStepperWhenCarsCostMoney() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 4_096, height: 2_048), economy: GameEconomy(balance: 100_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 5_000, car: 4_000_000)))
        XCTAssertEqual(world.carPriceText(in: .english), "Each car added costs $ 40,000; taking cars off refunds nothing.")
        XCTAssertEqual(world.carPriceText(in: .traditionalChinese), "每加一節車廂 $ 40,000；減少車廂不退費。")
        world = try GameWorld(bounds: WorldBounds(width: 4_096, height: 2_048), economy: GameEconomy(balance: 100_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 5_000)))
        XCTAssertNil(world.carPriceText(in: .english), "free cars: nothing to say")
    }

    /// Building still costs money in free play and nothing earns any, so a
    /// company in the red that switched could never build again (and the
    /// switch cannot be undone): the session refuses until the balance is
    /// back above zero.
    func testACompanyInTheRedCannotSwitchToFreePlay() async throws {
        var world = try makeLine()
        world.setEconomyMode(.management)
        for _ in 0..<60 where world.economy.balance >= .zero {
            try world.advance(ticks: 1_440)
        }
        XCTAssertLessThan(world.economy.balance, .zero, "the setup is a company in the red")
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            // A managed world is given its stations' ridership as it opens,
            // so compare with the session's own world, not the one passed in.
            let opened = session.world
            session.setEconomyMode(.free)
            XCTAssertEqual(session.world.accounts.mode, .management, "refused")
            XCTAssertEqual(session.message?.kind, .failure)
            XCTAssertEqual(
                session.message?.text,
                "The company is in the red. Free play has no income and building still costs money, so you could not build anything. Bring the balance back above zero first, or start a new game."
            )
            XCTAssertEqual(session.world, opened, "nothing else changed")
        }
    }

    /// Alpha(1,0) Beta(3,0) Gamma(5,0) beside a line of the track network
    /// from (0,1) to (6,1) (see `TestLine`), line Main calling at all
    /// three, one train of one car running it all day.
    private func makeLine() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        let line = TestLine(tiles: 7, row: 1)
        try line.build(in: &world)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try line.buildStation(named: name, beside: x, at: 0, in: &world)
        }
        let main = LineID(rawValue: 1)
        try world.createLine(named: "Main", stops: [StationID(rawValue: 1), StationID(rawValue: 2), StationID(rawValue: 3)])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.assignTrain(train.id, to: main)
        return world
    }

    /// The load bar is the `Ci/` reference's `#pt-load` / `.pax-bar-fill`:
    /// `u = cap ? round(pax / cap × 100) : 0`, the bar `min(100, max(0, u))`
    /// wide, and `is-overload` only when `u > 100`.
    func testTrainLoadInfoReadsRidersOverRatedCapacity() throws {
        let world = try makeLine()
        let train = world.trains[0]
        let load = try XCTUnwrap(world.trainLoadInfo(of: train.id))
        XCTAssertEqual(load, TrainLoadInfo(passengerCount: 0, capacity: 320))
        XCTAssertEqual(load.percentage, 0)
        XCTAssertEqual(load.barFraction, 0)
        XCTAssertFalse(load.isOverload)
        XCTAssertNil(world.trainLoadInfo(of: TrainID(rawValue: 99)))
    }

    func testLoadPercentageRoundsHalfUpAndOverloadNeedsMoreThanAHundredRounded() {
        XCTAssertEqual(TrainLoadInfo(passengerCount: 160, capacity: 320).percentage, 50)
        // 1 / 200 = 0.5 % rounds up, as `Math.round` does.
        XCTAssertEqual(TrainLoadInfo(passengerCount: 1, capacity: 200).percentage, 1)
        XCTAssertEqual(TrainLoadInfo(passengerCount: 223, capacity: 320).percentage, 70)

        let full = TrainLoadInfo(passengerCount: 320, capacity: 320)
        XCTAssertEqual(full.percentage, 100)
        XCTAssertEqual(full.barFraction, 1)
        XCTAssertFalse(full.isOverload)

        // 321 / 320 is 100.3 %: rounded it is 100, which the reference does
        // not mark as overloaded.
        let justOver = TrainLoadInfo(passengerCount: 321, capacity: 320)
        XCTAssertEqual(justOver.percentage, 100)
        XCTAssertFalse(justOver.isOverload)

        // 322 / 320 is 100.6 %, rounded 101: overloaded, the bar still full.
        let over = TrainLoadInfo(passengerCount: 322, capacity: 320)
        XCTAssertEqual(over.percentage, 101)
        XCTAssertTrue(over.isOverload)
        XCTAssertEqual(over.barFraction, 1, "the bar is clamped to 100 %")

        let crushed = TrainLoadInfo(passengerCount: 352, capacity: 320)
        XCTAssertEqual(crushed.percentage, 110)
        XCTAssertTrue(crushed.isOverload)
        XCTAssertEqual(crushed.barFraction, 1)
    }

    /// A capacity of 0 shows 0 % (the reference's `e.cap ? … : 0`), keeps
    /// the capacity it has rather than a made-up 1, and never divides by it.
    func testZeroCapacityShowsZeroPercent() {
        let empty = TrainLoadInfo(passengerCount: 5, capacity: 0)
        XCTAssertEqual(empty.capacity, 0)
        XCTAssertEqual(empty.percentage, 0)
        XCTAssertEqual(empty.barFraction, 0)
        XCTAssertFalse(empty.isOverload)
        XCTAssertEqual(TrainLoadInfo.percentage(passengers: 10, capacity: 0), 0)
        XCTAssertEqual(TrainLoadInfo.percentage(passengers: 10, capacity: -4), 0)
    }

    /// The fleet's average load counts only trains on the track: a train in
    /// the depot adds neither riders nor capacity.
    func testFleetLoadCountsOnlyPlacedTrains() throws {
        var world = try makeLine()
        XCTAssertEqual(world.fleetLoadInfo(), TrainLoadInfo(passengerCount: 0, capacity: 320))
        try world.purchaseTrain(named: "Spare")
        XCTAssertEqual(world.fleetLoadInfo(), TrainLoadInfo(passengerCount: 0, capacity: 320), "the unplaced train is not counted")
        try world.setStationDemand(StationID(rawValue: 1), to: StationDemand(kind: .residential, dailyTrips: 200_000))
        try world.setStationDemand(StationID(rawValue: 3), to: StationDemand(kind: .office, dailyTrips: 1_000))
        try world.advance(ticks: 26)
        let riding = world.riders(of: TrainID(rawValue: 1)).reduce(Int64(0)) { $0 + $1.count }
        XCTAssertGreaterThan(riding, 0)
        XCTAssertEqual(world.fleetLoadInfo(), TrainLoadInfo(passengerCount: riding, capacity: 320))
        XCTAssertEqual(world.fleetLoadInfo()?.percentage, world.trainLoadInfo(of: TrainID(rawValue: 1))?.percentage)

        var depot = try makeWorld(balance: 100_000)
        try depot.purchaseTrain(named: "Depot")
        XCTAssertNil(depot.fleetLoadInfo(), "no train on the track, no average")
    }
}
