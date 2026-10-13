@testable import GameCore
@testable import GamePresentation
import XCTest

/// TestFlight 54.1 and 56.1: a line that runs changes its headway in one
/// tap (the trains it lacks bought, those it no longer needs taken off,
/// evenly apart), warns when a time of day is set to more trains than it
/// has, and the lines list says how many trains run each line how often.
@MainActor
final class LineTrainCountTests: XCTestCase {
    private static let line = LineID(rawValue: 1)

    /// Decision 137's line between the first two towns (seed 1), one train
    /// of four cars, with money to spend; traffic control off unless asked,
    /// so its single track holds more than one train.
    private func lineBetweenTwoTowns(trafficControl: Bool = false) throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        world.economy.earn(Money(10_000_000_000))
        try world.setTrafficControl(trafficControl)
        return world
    }

    private func session(_ world: GameWorld) -> GameSession {
        let session = GameSession(world: world)
        session.selectLine(Self.line)
        return session
    }

    private func lastEdit(_ session: GameSession) -> String? {
        session.commandLog.entries.compactMap { entry -> String? in
            if case .command(.edit(let edit)) = entry.action { return edit.name }
            return nil
        }.last
    }

    // MARK: A shorter headway

    func testAShorterHeadwayBuysTheTrainsItLacksEvenlyApart() throws {
        let world = try lineBetweenTwoTowns()
        let roundTrip = try XCTUnwrap(world.lineJourney(Self.line)?.roundTripMinutes)
        let plan = try XCTUnwrap(world.lineStaffingPlan(Self.line, headway: 5, type: nil, cars: 4))
        let change = try XCTUnwrap(world.lineHeadwayChange(Self.line, headway: 5))
        XCTAssertEqual(change.current, 1)
        XCTAssertEqual(change.trains, plan.trains)
        XCTAssertEqual(change.trains, Int((roundTrip + 4) / 5))
        XCTAssertGreaterThan(change.buying, 0)
        XCTAssertEqual(change.removing, 0)
        XCTAssertEqual(change.cars, 4, "as the line's train")
        XCTAssertEqual(change.cost, Money(plan.pricePerTrain.amount * Int64(change.buying)))
        XCTAssertFalse(change.isUnchanged)
        XCTAssertNil(change.limitText(in: .english))
        XCTAssertEqual(change.title(in: .traditionalChinese), "調整為每 5 分（加開 \(change.buying) 列 · \(change.cost.moneyText)）")
        XCTAssertEqual(change.title(in: .english), "Every 5 min (add \(change.buying) trains · \(change.cost.moneyText))")

        let session = session(world)
        session.changeSelectedLineHeadway(change)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let after = session.world
        let line = try XCTUnwrap(after.line(id: Self.line))
        XCTAssertEqual(line.trains.count, change.trains)
        XCTAssertEqual(line.targetHeadways, TargetHeadways(peak: 5, offPeak: 5, low: 5))
        XCTAssertEqual(after.economy.balance, world.economy.balance - change.cost)
        XCTAssertEqual(lastEdit(session), "addLineTrains")
        // Evenly apart: the line sends them out every 5 minutes at every
        // level, and has every train it is set to run.
        for level in ServiceLevel.allCases {
            XCTAssertEqual(after.lineHeadway(Self.line, at: level), 5)
        }
        XCTAssertEqual(after.lineRunningHeadway(Self.line), 5)
        XCTAssertNil(after.lineTrainShortfall(Self.line))
        XCTAssertTrue(try XCTUnwrap(after.lineHeadwayChange(Self.line, headway: 5)).isUnchanged)
    }

    // MARK: A longer headway

    func testALongerHeadwaySendsTheExtraTrainsToNoLine() throws {
        let start = session(try lineBetweenTwoTowns())
        start.changeSelectedLineHeadway(try XCTUnwrap(start.world.lineHeadwayChange(Self.line, headway: 5)))
        let world = start.world
        let before = try XCTUnwrap(world.line(id: Self.line)?.trains)

        let change = try XCTUnwrap(world.lineHeadwayChange(Self.line, headway: 30))
        let plan = try XCTUnwrap(world.lineStaffingPlan(Self.line, headway: 30, type: nil, cars: 4))
        XCTAssertEqual(change.trains, plan.trains)
        XCTAssertEqual(change.buying, 0)
        XCTAssertEqual(change.removing, before.count - plan.trains)
        XCTAssertGreaterThan(change.removing, 0)
        XCTAssertEqual(change.cost, .zero)
        XCTAssertEqual(change.title(in: .traditionalChinese), "改為 \(plan.trains) 列，每 30 分（多的車回到未配屬）")

        let session = session(world)
        session.changeSelectedLineHeadway(change)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let after = session.world
        let line = try XCTUnwrap(after.line(id: Self.line))
        XCTAssertEqual(line.trains.count, plan.trains)
        XCTAssertEqual(line.targetHeadways, TargetHeadways(peak: 30, offPeak: 30, low: 30))
        XCTAssertEqual(after.economy.balance, world.economy.balance, "free")
        XCTAssertEqual(lastEdit(session), "removeLineTrains")
        // The newest go first; they are still the player's, on no line.
        let removed = before.filter { !line.trains.contains($0) }
        XCTAssertEqual(removed, Array(before.suffix(change.removing)))
        for train in removed {
            XCTAssertNotNil(after.train(id: train))
            XCTAssertNil(after.assignedLine(of: train))
        }
        XCTAssertNil(after.lineTrainShortfall(Self.line))
        XCTAssertEqual(try XCTUnwrap(after.lineHeadwayChange(Self.line, headway: 30)).title(in: .english), "Already every 30 min")
    }

    func testFewerTrainsTakeTheWaitingOnesFirst() throws {
        let session = session(try lineBetweenTwoTowns())
        session.changeSelectedLineHeadway(try XCTUnwrap(session.world.lineHeadwayChange(Self.line, headway: 5)))
        var world = session.world
        // Some trains set off, the rest still wait at the first station.
        func split() -> (waiting: [TrainID], running: [TrainID]) {
            let trains = world.line(id: Self.line)?.trains ?? []
            return (trains.filter { world.train(id: $0)?.execution == nil }, trains.filter { world.train(id: $0)?.execution != nil })
        }
        for _ in 0..<240 where split().running.isEmpty || split().waiting.isEmpty {
            try world.advance(ticks: 1)
        }
        let (waiting, running) = split()
        XCTAssertFalse(waiting.isEmpty)
        XCTAssertFalse(running.isEmpty)
        try GameSession.removeTrains(waiting.count, from: Self.line, targets: TargetHeadways(peak: 30), in: &world)
        XCTAssertEqual(world.line(id: Self.line)?.trains, running, "those on a trip stay")
        XCTAssertEqual(world.line(id: Self.line)?.targetHeadways, TargetHeadways(peak: 30))
    }

    // MARK: Single track

    func testSingleTrackSaysWhatHoldsItBack() throws {
        let world = try lineBetweenTwoTowns(trafficControl: true)
        XCTAssertEqual(world.lineMaximumTrains(Self.line), 1)
        let change = try XCTUnwrap(world.lineHeadwayChange(Self.line, headway: 5))
        XCTAssertEqual(change.trains, 1)
        XCTAssertEqual(change.buying, 0)
        XCTAssertEqual(change.removing, 0)
        XCTAssertGreaterThan(change.actualHeadway, 5)
        XCTAssertFalse(change.isUnchanged, "the targets change")
        XCTAssertEqual(change.title(in: .traditionalChinese), "調整為每 5 分")
        XCTAssertEqual(
            change.limitText(in: .traditionalChinese),
            "這條路線最多只能跑 1 列：每 \(change.actualHeadway) 分一班。蓋雙線或待避線才能再多跑。"
        )
    }

    func testALineWithoutTrainsOrARingHasNoChange() throws {
        var world = try lineBetweenTwoTowns()
        XCTAssertNil(world.lineHeadwayChange(LineID(rawValue: 99), headway: 5))
        let train = try XCTUnwrap(world.line(id: Self.line)?.trains.first)
        try world.unassignTrain(train)
        XCTAssertNil(world.lineHeadwayChange(Self.line, headway: 5), "decision 101's staffing serves it")
        XCTAssertNil(world.lineTrainShortfall(Self.line))
        XCTAssertEqual(world.lineTrainsRowText(Self.line, in: .english), "No trains")
        XCTAssertEqual(world.lineTrainsRowText(Self.line, in: .traditionalChinese), "沒有列車")
    }

    // MARK: More trains wanted than the line has

    func testMoreTrainsWantedThanAssignedWarnsAndFillsThem() throws {
        var world = try lineBetweenTwoTowns()
        XCTAssertNil(world.lineTrainShortfall(Self.line))
        try world.setLineTrainsInService(Self.line, to: TrainsInService(peak: 3, offPeak: 2, low: 1))
        let shortfall = try XCTUnwrap(world.lineTrainShortfall(Self.line))
        XCTAssertEqual(shortfall.level, .peak)
        XCTAssertEqual(shortfall.wanted, 3)
        XCTAssertEqual(shortfall.assigned, 1)
        XCTAssertEqual(shortfall.buying, 2)
        XCTAssertEqual(shortfall.cars, 4)
        XCTAssertEqual(shortfall.cost, Money(world.purchaseCost(of: nil, cars: 4).amount * 2))
        XCTAssertEqual(shortfall.warning(in: .traditionalChinese), "尖峰設定上線 3 列，但路線只有 1 列：實際班距會比顯示的長。")
        XCTAssertEqual(shortfall.warning(in: .english), "Peak is set to 3 trains but the line has 1: trains come less often than shown.")
        XCTAssertEqual(shortfall.title(in: .traditionalChinese), "補齊 2 列 · \(shortfall.cost.moneyText)")

        let session = session(world)
        session.fillSelectedLineTrains(shortfall)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.line(id: Self.line)?.trains.count, 3)
        XCTAssertEqual(session.world.line(id: Self.line)?.targetHeadways, world.line(id: Self.line)?.targetHeadways, "kept")
        XCTAssertEqual(session.world.economy.balance, world.economy.balance - shortfall.cost)
        XCTAssertNil(session.world.lineTrainShortfall(Self.line))
        XCTAssertEqual(lastEdit(session), "addLineTrains")
    }

    // MARK: The lines list

    func testTheListSaysHowManyTrainsRunHowOften() throws {
        let world = try lineBetweenTwoTowns()
        let roundTrip = try XCTUnwrap(world.lineJourney(Self.line)?.roundTripMinutes)
        // One train: one every round trip.
        XCTAssertEqual(world.lineRunningHeadway(Self.line), roundTrip)
        XCTAssertEqual(
            world.lineTrainsRowText(Self.line, in: .english),
            "1 train · " + headwayText(minutes: roundTrip, in: .english).lowercased()
        )
        XCTAssertEqual(
            world.lineTrainsRowText(Self.line, in: .traditionalChinese),
            "1 列 · " + headwayText(minutes: roundTrip, in: .traditionalChinese)
        )

        let session = session(world)
        session.changeSelectedLineHeadway(try XCTUnwrap(world.lineHeadwayChange(Self.line, headway: 10)))
        let trains = try XCTUnwrap(session.world.line(id: Self.line)?.trains.count)
        XCTAssertEqual(session.world.lineTrainsRowText(Self.line, in: .traditionalChinese), "\(trains) 列 · 每 10 分鐘一班")
        XCTAssertEqual(session.world.lineTrainsRowText(Self.line, in: .english), "\(trains) trains · every 10 min")

        let memo = LinePanelMemo()
        XCTAssertEqual(memo.trainsRowText(Self.line, of: session), "\(trains) trains · every 10 min")
        XCTAssertEqual(memo.runningHeadway(Self.line, of: session), 10)
    }
}
