@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 682: what buying trains for a line would do to its day, said
/// where they are bought.
@MainActor
final class TrainPurchaseEstimateTests: XCTestCase {
    private static let line = LineID(rawValue: 1)

    private func lineBetweenTwoTowns() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        world.economy.earn(Money(10_000_000_000))
        try world.setTrafficControl(false)
        return world
    }

    private func played(_ world: GameWorld, days: Int) throws -> GameWorld {
        var player = PolicyPlayer(world: world, policy: .none)
        try player.advance(ticks: 1)
        for _ in 0..<days { try player.playDay() }
        return player.world
    }

    /// The line with no train, the clock having run a tick so that the
    /// passenger plan is made.
    private func emptyLine() throws -> GameWorld {
        var world = try lineBetweenTwoTowns()
        let train = world.trains[0].id
        try world.unassignTrain(train)
        try world.unplaceTrain(train)
        try world.advance(ticks: 1)
        return world
    }

    /// The line's average day of `days` completed days from `first` on:
    /// dollars of fares and of running cost.
    private func average(_ world: GameWorld, from first: Int, days: Int) -> (fares: Double, cost: Double) {
        let records = world.lineDays(Self.line).dropFirst(first).prefix(days)
        XCTAssertEqual(records.count, days)
        let fares = records.reduce(0) { $0 + $1.tally.fareRevenue.amount }
        let cost = records.reduce(0) { $0 + $1.tally.totalCost.amount }
        return (Double(fares) / 100 / Double(days), Double(cost) / 100 / Double(days))
    }

    private func dollars(_ money: Money?) -> Double { Double(money?.amount ?? 0) / 100 }

    /// The report the decision quotes: `TRAIN_PURCHASE_REPORT=1`.
    private func report(_ title: String, _ estimate: TrainPurchaseEstimate, _ actual: (fares: Double, cost: Double)) {
        guard getenv("TRAIN_PURCHASE_REPORT") != nil else { return }
        print("REPORT \(title): fares est \(Int(dollars(estimate.fares))) actual \(Int(actual.fares)); cost est \(Int(dollars(estimate.cost))) actual \(Int(actual.cost)); now \(Int(dollars(estimate.faresNow))) / \(Int(dollars(estimate.costNow)))")
        print("REPORT   " + estimate.spokenText(in: .traditionalChinese))
    }

    // MARK: - Against the days the game then plays

    /// A line with one train, a second and a third bought: the running
    /// cost the estimate says is the cost of the four days played after,
    /// within 3%, and the fares within the days' own swing (a quarter).
    func testMoreTrainsOnARunningLineCostWhatTheEstimateSays() throws {
        let world = try played(try lineBetweenTwoTowns(), days: 3)
        let change = try XCTUnwrap(world.lineHeadwayChange(Self.line, headway: 5))
        XCTAssertEqual(change.buying, 2)
        let estimate = try XCTUnwrap(world.trainPurchaseEstimate(
            Self.line, buying: change.buying, type: change.type, cars: change.cars, headway: 5, price: change.cost
        ))
        XCTAssertEqual(estimate.demand, .planned)
        XCTAssertEqual(estimate.historyDays, 3)
        // Now is the line's own days.
        let before = average(world, from: 0, days: 3)
        XCTAssertEqual(dollars(estimate.faresNow), before.fares, accuracy: 1)
        XCTAssertEqual(dollars(estimate.costNow), before.cost, accuracy: 1)

        let session = GameSession(world: world)
        session.selectLine(Self.line)
        session.changeSelectedLineHeadway(change)
        let after = average(try played(session.world, days: 4), from: 3, days: 4)
        report("one train, two bought", estimate, after)
        XCTAssertEqual(dollars(estimate.cost), after.cost, accuracy: after.cost * 0.03)
        XCTAssertEqual(dollars(estimate.fares), after.fares, accuracy: after.fares * 0.25)
        // One train carried everyone: two more cost and bring nothing.
        XCTAssertEqual(estimate.tone, .worse)
        XCTAssertNil(estimate.paybackDays)
        XCTAssertGreaterThan(estimate.addedCost.amount, 0)
    }

    /// A line with no train yet, staffed: no day of its own to go by, and
    /// the estimate is still the days played after.
    func testStaffingALineWithNoTrainIsTheDaysPlayedAfter() throws {
        let world = try emptyLine()
        let plan = try XCTUnwrap(world.lineStaffingPlan(Self.line, headway: 10, type: nil, cars: 4))
        let estimate = try XCTUnwrap(world.trainPurchaseEstimate(
            Self.line, buying: plan.trains, type: plan.type, cars: plan.cars, headway: 10, price: plan.cost
        ))
        XCTAssertEqual(estimate.demand, .planned)
        XCTAssertEqual(estimate.historyDays, 0)
        XCTAssertEqual(estimate.faresNow, .zero)
        XCTAssertGreaterThan(estimate.costNow.amount, 0, "Its stations and track cost with no train")

        let session = GameSession(world: world)
        session.selectLine(Self.line)
        session.staffSelectedLine(headway: 10, type: nil, cars: 4)
        let after = average(try played(session.world, days: 4), from: 0, days: 4)
        report("no train, two bought", estimate, after)
        XCTAssertEqual(dollars(estimate.cost), after.cost, accuracy: after.cost * 0.03)
        XCTAssertEqual(dollars(estimate.fares), after.fares, accuracy: after.fares * 0.25)
        XCTAssertEqual(estimate.tone, .better)
        XCTAssertNotNil(estimate.paybackDays)
        let breakEven = try XCTUnwrap(estimate.breakEvenRiders)
        XCTAssertLessThan(breakEven, try XCTUnwrap(estimate.riders))
    }

    /// One short train leaves riders behind: the estimate says another
    /// brings fares, and the days played after bring them.
    func testAFullLineTakesMoreFaresWithAnotherTrain() throws {
        let first = GameSession(world: try emptyLine())
        first.selectLine(Self.line)
        first.staffSelectedLine(headway: 15, type: nil, cars: 1)
        let world = try played(first.world, days: 3)
        let change = try XCTUnwrap(world.lineHeadwayChange(Self.line, headway: 10))
        XCTAssertEqual(change.buying, 1)
        let estimate = try XCTUnwrap(world.trainPurchaseEstimate(
            Self.line, buying: 1, type: change.type, cars: change.cars, headway: 10, price: change.cost
        ))
        XCTAssertEqual(estimate.peakLoadPermille, 1_000)
        XCTAssertGreaterThan(try XCTUnwrap(estimate.fares), estimate.faresNow)

        let session = GameSession(world: world)
        session.selectLine(Self.line)
        session.changeSelectedLineHeadway(change)
        let later = try played(session.world, days: 4)
        let before = average(later, from: 0, days: 3), after = average(later, from: 3, days: 4)
        report("one short train, one bought", estimate, after)
        XCTAssertGreaterThan(after.fares, before.fares)
        XCTAssertEqual(dollars(estimate.cost), after.cost, accuracy: after.cost * 0.03)
        XCTAssertEqual(dollars(estimate.fares), after.fares, accuracy: after.fares * 0.25)
    }

    // MARK: - What cannot be said

    /// Before the clock has run there is no passenger plan: the cost is
    /// said, the fares are not.
    func testWithNoPlanTheFaresAreNotSaid() throws {
        let world = try lineBetweenTwoTowns()
        let estimate = try XCTUnwrap(world.trainPurchaseEstimate(
            Self.line, buying: 1, type: nil, cars: 4, headway: 10, price: Money(100_000_000)
        ))
        XCTAssertEqual(estimate.demand, .unknown)
        XCTAssertNil(estimate.fares)
        XCTAssertNil(estimate.riders)
        XCTAssertNil(estimate.tone)
        XCTAssertNil(estimate.changeText(in: .english))
        XCTAssertGreaterThan(estimate.cost.amount, 0)
        XCTAssertNotNil(estimate.breakEvenRiders, "From the fares between its stops")
        XCTAssertTrue(estimate.headline(in: .traditionalChinese).hasSuffix("票收 —"))
        XCTAssertTrue(estimate.note(in: .english).contains("once the clock has run"))
    }

    func testNothingBoughtOrNoSuchLineHasNoEstimate() throws {
        let world = try lineBetweenTwoTowns()
        XCTAssertNil(world.trainPurchaseEstimate(Self.line, buying: 0, type: nil, cars: 4, headway: 10, price: .zero))
        XCTAssertNil(world.trainPurchaseEstimate(LineID(rawValue: 99), buying: 1, type: nil, cars: 4, headway: 10, price: .zero))
    }

    // MARK: - The parts

    func testRidersLeftBehindWaitForTheNextHour() {
        var need = Array(repeating: Int64(0), count: 24)
        var offered = Array(repeating: Int64(100), count: 24)
        need[8] = 150
        // 50 wait an hour and ride at nine.
        var carried = TrainPurchaseModel.carried(need: need, offered: offered)
        XCTAssertEqual(carried.permille, 1_000)
        XCTAssertEqual(carried.peakLoad, 1_000)
        // Never room enough: half ride.
        need = Array(repeating: 200, count: 24)
        carried = TrainPurchaseModel.carried(need: need, offered: offered)
        XCTAssertEqual(carried.permille, 500)
        // Room to spare.
        offered = Array(repeating: 400, count: 24)
        carried = TrainPurchaseModel.carried(need: need, offered: offered)
        XCTAssertEqual(carried.permille, 1_000)
        XCTAssertEqual(carried.peakLoad, 500)
        // No train, no rider.
        carried = TrainPurchaseModel.carried(need: need, offered: Array(repeating: 0, count: 24))
        XCTAssertEqual(carried.permille, 0)
        XCTAssertNil(carried.peakLoad)
    }

    func testTheTextsSayMoreOrLessThanNow() {
        func estimate(fares: Int64, cost: Int64) -> TrainPurchaseEstimate {
            TrainPurchaseEstimate(
                demand: .planned, historyDays: 7, faresNow: Money(100_000_00), costNow: Money(60_000_00),
                fares: Money(fares * 100), cost: Money(cost * 100), addedCost: Money(20_000_00),
                riders: 4_100, peakLoadPermille: 850, breakEvenRiders: 3_200, price: Money(380_000_00)
            )
        }
        let better = estimate(fares: 130_000, cost: 80_000)
        XCTAssertEqual(better.tone, .better)
        XCTAssertEqual(better.paybackDays, 38)
        XCTAssertEqual(better.headline(in: .traditionalChinese), "估每天票收 \(Money(130_000_00).moneyText) · 開銷 \(Money(80_000_00).moneyText) · 賺 \(Money(50_000_00).moneyText)")
        XCTAssertEqual(better.changeText(in: .traditionalChinese), "比現在每天多 \(Money(10_000_00).moneyText) · 約 38 天回本")
        XCTAssertEqual(better.changeText(in: .english), "\(Money(10_000_00).moneyText) a day more than now · pays back in about 38 days")
        XCTAssertEqual(better.ridersText(in: .traditionalChinese), "每天載 3,200 人次打平 · 估 4,100 人次，最擠時坐滿 85%")
        XCTAssertEqual(better.ridersText(in: .english), "Breaks even at 3,200 riders a day · about 4,100 expected, fullest trains 85% full")

        let worse = estimate(fares: 70_000, cost: 80_000)
        XCTAssertEqual(worse.tone, .worse)
        XCTAssertEqual(worse.headline(in: .english), "About a day: fares \(Money(70_000_00).moneyText) · running \(Money(80_000_00).moneyText) · loses \(Money(10_000_00).moneyText)")
        XCTAssertEqual(worse.changeText(in: .traditionalChinese), "比現在每天少 \(Money(50_000_00).moneyText)")
        XCTAssertEqual(estimate(fares: 120_000, cost: 80_000).changeText(in: .english), "The same as now")
        XCTAssertTrue(worse.spokenText(in: .traditionalChinese).contains("天氣、假日與誤點"))
    }

    // MARK: - The panel's memo

    /// The panel reads it once an hour of the game, and again after a
    /// command.
    func testThePanelKeepsItForTheHour() throws {
        let session = GameSession(world: try played(try lineBetweenTwoTowns(), days: 1))
        session.selectLine(Self.line)
        let memo = LinePanelMemo()
        let change = try XCTUnwrap(memo.headwayChange(Self.line, headway: 5, of: session))
        func read() -> TrainPurchaseEstimate? {
            memo.purchaseEstimate(
                Self.line, buying: change.buying, type: change.type, cars: change.cars, headway: 5, price: change.cost, of: session
            )
        }
        let first = try XCTUnwrap(read())
        XCTAssertEqual(first, session.world.trainPurchaseEstimate(
            Self.line, buying: change.buying, type: change.type, cars: change.cars, headway: 5, price: change.cost
        ))
        XCTAssertEqual(first.historyDays, 1)
        XCTAssertEqual(read(), first)
    }

    /// When the page shows it: for every headway that buys trains, and
    /// for none that does not (the screenshots' line, two days run: its
    /// one train comes every 13 minutes).
    func testEveryHeadwayThatBuysTrainsHasAnEstimate() throws {
        let session = GameSession(world: try played(try lineBetweenTwoTowns(), days: 2))
        session.selectLine(Self.line)
        let memo = LinePanelMemo()
        var buying: [Int64: Int] = [:]
        for headway in GameWorld.staffingHeadways {
            let change = try XCTUnwrap(memo.headwayChange(Self.line, headway: headway, of: session))
            buying[headway] = change.buying
            let estimate = memo.purchaseEstimate(
                Self.line, buying: change.buying, type: change.type, cars: change.cars, headway: headway, price: change.cost, of: session
            )
            XCTAssertEqual(estimate != nil, change.buying > 0, "\(headway) min")
            if let estimate {
                XCTAssertEqual(estimate.demand, .planned)
                XCTAssertEqual(estimate.price, change.cost)
            }
        }
        XCTAssertEqual(buying, [3: 4, 5: 2, 10: 1, 15: 0, 20: 0, 30: 0])
    }
}
