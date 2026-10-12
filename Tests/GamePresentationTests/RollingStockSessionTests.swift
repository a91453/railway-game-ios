import Foundation
import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 180: a line staffed with a chosen type and cars, a
/// whole line re-formed, a train sold, and the cards of the types.
@MainActor
final class RollingStockSessionTests: XCTestCase {
    private static let line = TestLine(tiles: 9, row: 1)
    private static let main = LineID(rawValue: 1)

    private func lineWorld(economics: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 9_216, height: 4_096, balance: Money(5_000_000_000), speed: .normal)
        world.setEconomyMode(.management)
        world.setRollingStockEconomics(economics)
        try Self.line.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            stops.append(try Self.line.buildStation(named: name, beside: x, at: 0, in: &world))
        }
        try world.createLine(named: "Main", stops: stops)
        try world.setLineServiceWindow(Self.main, to: .allDay)
        return world
    }

    func testThePlanPricesTheChosenTypeAndCars() throws {
        let world = try lineWorld()
        let plan = try XCTUnwrap(world.lineStaffingPlan(Self.main, headway: 10, type: .maglev, cars: 4))
        XCTAssertEqual(plan.type, .maglev)
        XCTAssertEqual(plan.cars, 4)
        XCTAssertEqual(plan.pricePerTrain, Money(105_000_000))
        XCTAssertEqual(plan.cost, Money(105_000_000 * Int64(plan.trains)))
        // 4 maglev cars weigh 7.2 standard trains: (480 + 360 + 192) × 7.2 = 7,430.4 dollars.
        XCTAssertEqual(plan.dailyCostPerTrain, Money(743_040).roundedToDollars)
        // A cars count out of range is brought into it.
        XCTAssertEqual(world.lineStaffingPlan(Self.main, headway: 10, cars: 99)?.cars, Train.maximumCars)
    }

    func testWithoutTheSwitchThePlanIsTheOnePriceAndTheCarPrice() throws {
        let world = try lineWorld(economics: false)
        let one = try XCTUnwrap(world.lineStaffingPlan(Self.main, headway: 10))
        XCTAssertEqual(one.pricePerTrain, world.economy.costs.train)
        let four = try XCTUnwrap(world.lineStaffingPlan(Self.main, headway: 10, type: .maglev, cars: 4))
        XCTAssertEqual(four.pricePerTrain, Money(world.economy.costs.train.amount + 3 * world.economy.costs.car.amount))
        XCTAssertEqual(four.dailyCostPerTrain, one.dailyCostPerTrain, "one weight for every train")
    }

    func testStaffingBuysTheChosenTypeAtItsPriceWithoutARefit() throws {
        let start = try lineWorld()
        let session = GameSession(world: start)
        let plan = try XCTUnwrap(start.lineStaffingPlan(Self.main, headway: 10, type: .l, cars: 3))
        session.staffSelectedLine(headway: 10, type: .l, cars: 3)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.trains.count, plan.trains)
        XCTAssertEqual(session.world.economy.balance, start.economy.balance - plan.cost)
        for train in session.world.trains {
            XCTAssertEqual(train.type, .l)
            XCTAssertEqual(train.cars, 3)
        }
    }

    func testAHighSpeedLineIsStaffedWithHighSpeedSetsAtTheirPrice() throws {
        var world = try lineWorld()
        try world.setLinePerformance(Self.main, to: .highSpeed)
        let session = GameSession(world: world)
        let plan = try XCTUnwrap(world.lineStaffingPlan(Self.main, headway: 10))
        XCTAssertEqual(plan.type, .highSpeed)
        session.staffSelectedLine(headway: 10)
        XCTAssertEqual(session.world.economy.balance, world.economy.balance - plan.cost, "no refit on top of the price")
        XCTAssertTrue(session.world.trains.allSatisfy { $0.type == .highSpeed })
    }

    func testReformingChangesTheTrainsWaitingAndLeavesTheOnesOnATrip() throws {
        let session = GameSession(world: try lineWorld())
        session.staffSelectedLine(headway: 5)
        var world = session.world
        XCTAssertGreaterThan(world.trains.count, 1)
        // Let the first train go out; the others wait their turn.
        while world.trains.allSatisfy({ $0.execution == nil }) { try world.advance(ticks: 1) }
        let onTrip = world.trains.filter { $0.execution != nil }.map(\.id)
        let waiting = world.trains.filter { $0.execution == nil }.map(\.id)
        XCTAssertFalse(waiting.isEmpty)
        let editing = GameSession(world: world)
        let before = editing.world.economy.balance

        editing.reformSelectedLine(type: .maglev, cars: 2)
        XCTAssertEqual(editing.message?.kind, .success, editing.message?.text ?? "")
        for id in waiting {
            let train = try XCTUnwrap(editing.world.train(id: id))
            XCTAssertEqual(train.type, .maglev)
            XCTAssertEqual(train.cars, 2)
            XCTAssertEqual(editing.world.assignedLine(of: id), Self.main)
            XCTAssertNotNil(train.position)
        }
        for id in onTrip {
            XCTAssertNil(editing.world.train(id: id)?.type, "on a trip, left as it was")
            XCTAssertEqual(editing.world.train(id: id)?.cars, 1)
        }
        // Each: the maglev's price for one car less 70 % of the standard train's books, and one more car.
        let each = (RollingStock.price(of: .maglev, cars: 1).amount - 10_500_000) + TrainType.maglev.pricing.eachCar.amount
        XCTAssertEqual(before - editing.world.economy.balance, Money(each * Int64(waiting.count)))
        XCTAssertTrue(editing.message?.text.contains("Left as they were") ?? false)
        XCTAssertEqual(editing.undoCount, 1, "one edit")
    }

    func testReformingToTheSameFormationChangesNothing() throws {
        let session = GameSession(world: try lineWorld())
        session.staffSelectedLine(headway: 30)
        let before = session.world
        session.reformSelectedLine(type: nil, cars: 1)
        XCTAssertEqual(session.world, before)
        XCTAssertEqual(session.message?.kind, .success)
    }

    func testSellingATrainThroughTheSession() throws {
        let session = GameSession(world: try lineWorld())
        session.purchaseTrain()
        let id = try XCTUnwrap(session.selectedTrainID)
        let quote = session.world.trainSaleQuote(id)
        XCTAssertEqual(quote, Money(15_000_000 * 70 / 100))
        let before = session.world.economy.balance
        session.sellTrain(id)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.economy.balance - before, quote)
        XCTAssertNil(session.world.train(id: id))
        XCTAssertNil(session.selectedTrainID)
        session.undo()
        XCTAssertNotNil(session.world.train(id: id), "a sale can be taken back like any edit")
    }

    func testATrainOnALineIsNotSoldAndTheMessageSaysSo() throws {
        let session = GameSession(world: try lineWorld())
        session.staffSelectedLine(headway: 30)
        let id = try XCTUnwrap(session.world.trains.first?.id)
        XCTAssertFalse(session.world.canSellTrain(id))
        let before = session.world
        session.sellTrain(id)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, before)
    }

    func testTheCardsListWhatEachTypeCostsAndHowFastItRuns() throws {
        let on = try lineWorld()
        let card = on.trainTypeCard(.highSpeed)
        XCTAssertEqual(card.capacityPerCar, 80)
        XCTAssertEqual(card.firstCarPrice, Money(90_000_000))
        XCTAssertEqual(card.carPrice, Money(12_000_000))
        XCTAssertEqual(card.topSpeed, TrainPerformance.highSpeed.topSpeed)
        XCTAssertEqual(on.trainTypeCard(nil).topSpeed, TrainPerformance.standard.topSpeed)
        XCTAssertTrue(card.text(in: .english).contains("80 a car"))
        XCTAssertTrue(card.text(in: .traditionalChinese).contains("每節 80 人"))
        let off = try lineWorld(economics: false)
        XCTAssertEqual(off.trainTypeCard(.highSpeed).firstCarPrice, off.economy.costs.train, "one price without the switch")
        for type in TrainType.allCases {
            XCTAssertGreaterThan(on.trainTypeCard(type).dailyCost, .zero, "\(type)")
        }
    }
}

private extension Money {
    /// Rounded to a whole dollar, half up, in cents.
    var roundedToDollars: Money { Money((amount + 50) / 100 * 100) }
}
