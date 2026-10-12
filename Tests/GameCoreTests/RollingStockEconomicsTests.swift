import Foundation
@testable import GameCore
import XCTest

/// Rolling-stock economics (ARCHITECTURE decision 180): a train costs what
/// its type and cars cost, a refit and a sale have prices, and the daily
/// running costs weigh a train's cars and type.
final class RollingStockEconomicsTests: XCTestCase {
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let one = TrainID(rawValue: 1)
    private let dollar: Int64 = 100

    /// A managed world on the straight line, with or without the switch.
    private func makeWorld(economics: Bool, balance: Int64 = 20_000_000_000) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: Money(balance), costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 0), speed: .normal)
        )
        world.setEconomyMode(.management)
        world.setRollingStockEconomics(economics)
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        return world
    }

    // MARK: - The table

    func testEveryTypeHasPricesAndAWeightAndTheStandardCarIsTypeA() {
        for type in TrainType.allCases {
            let pricing = type.pricing
            XCTAssertGreaterThan(pricing.firstCar, .zero, "\(type)")
            XCTAssertGreaterThan(pricing.eachCar, .zero, "\(type)")
            XCTAssertLessThanOrEqual(pricing.eachCar, pricing.firstCar, "\(type)")
            XCTAssertGreaterThan(pricing.operatingPermille, 0, "\(type)")
        }
        XCTAssertEqual(RollingStock.standard, TrainType.a.pricing)
        XCTAssertEqual(RollingStock.pricing(of: nil), TrainType.a.pricing)
        // The heavy types cost more than the light ones, to buy and to run.
        XCTAssertGreaterThan(TrainType.maglev.pricing.firstCar, TrainType.l.pricing.firstCar)
        XCTAssertGreaterThan(TrainType.highSpeed.pricing.operatingPermille, TrainType.l.pricing.operatingPermille)
    }

    func testPriceRefitAndSaleAreFunctionsOfTypeAndCars() {
        // Maglev: $600,000 the first car, $150,000 each more.
        XCTAssertEqual(RollingStock.price(of: .maglev, cars: 1), Money(60_000_000))
        XCTAssertEqual(RollingStock.price(of: .maglev, cars: 4), Money(105_000_000))
        XCTAssertEqual(RollingStock.refitFee(to: .maglev, cars: 4), Money(31_500_000))
        XCTAssertEqual(RollingStock.salePrice(bookValue: Money(33_333_333)), Money(23_333_333))
        XCTAssertEqual(RollingStock.salePrice(bookValue: Money(-5)), .zero)
        XCTAssertEqual(RollingStock.weight(of: .maglev, cars: 4), 7_200)
        XCTAssertEqual(RollingStock.weight(of: nil, cars: 1), 1_000)
    }

    // MARK: - Buying, refitting, selling

    func testWithoutTheSwitchEveryTrainCostsTheOnePriceAndSetTypeIsFree() throws {
        var world = try makeWorld(economics: false)
        let start = world.economy.balance
        let train = try world.purchaseTrain(named: "Blue")
        XCTAssertEqual(start - world.economy.balance, testCosts.train)
        let afterBuying = world.economy.balance
        try world.setTrainType(train.id, to: .maglev)
        try world.setTrainCars(train.id, to: 3)
        XCTAssertEqual(afterBuying - world.economy.balance, Money(testCosts.car.amount * 2))
    }

    func testWithTheSwitchATrainCostsItsTypesPricesAndARefitPaysAShare() throws {
        var world = try makeWorld(economics: true)
        var balance = world.economy.balance
        func paid() -> Int64 {
            defer { balance = world.economy.balance }
            return balance.amount - world.economy.balance.amount
        }
        let train = try world.purchaseTrain(named: "Blue")
        XCTAssertEqual(paid(), 150_000 * dollar)
        try world.setTrainType(train.id, to: .maglev)
        XCTAssertEqual(paid(), 18_000_000, "30 % of $600,000")
        try world.setTrainType(train.id, to: .maglev)
        XCTAssertEqual(paid(), 0, "the same type is no refit")
        try world.setTrainCars(train.id, to: 4)
        XCTAssertEqual(paid(), 3 * 150_000 * dollar, "three maglev cars")
        try world.setTrainType(train.id, to: .l)
        XCTAssertEqual(paid(), (90_000 + 3 * 25_000) * dollar * 30 / 100, "a light-rail refit of four cars")
        // What the books hold: the purchase and the refits on the train, the cars on the cars.
        let book = world.accounts.assets.filter { $0.kind == .train || $0.kind == .cars }.reduce(Money.zero) { $0 + $1.cost }
        XCTAssertEqual(book, Money(15_000_000 + 18_000_000 + 45_000_000 + 4_950_000))
    }

    func testARefitTooDearForTheBalanceIsRefusedAndChangesNothing() throws {
        var world = try makeWorld(economics: true, balance: 15_003_700)
        let train = try world.purchaseTrain(named: "Blue")
        let before = world
        XCTAssertThrowsError(try world.setTrainType(train.id, to: .highSpeed)) { error in
            guard case GameError.insufficientFunds = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(world, before)
    }

    func testSellingBringsSeventyPercentOfTheBookValueAndTheTrainIsGone() throws {
        var world = try makeWorld(economics: true)
        let train = try world.purchaseTrain(named: "Blue")
        try world.setTrainType(train.id, to: .maglev)
        try world.setTrainCars(train.id, to: 4)
        let before = world.economy.balance
        try world.sellTrain(train.id)
        // $150,000 + the $180,000 refit... the train record: 15,000,000 + 18,000,000; the cars: 45,000,000 + (the cars bought after the refit) 45,000,000.
        let trainBook: Int64 = 15_000_000 + 18_000_000
        let carsBook: Int64 = 3 * 15_000_000
        XCTAssertEqual(world.economy.balance - before, Money(trainBook * 70 / 100 + carsBook * 70 / 100))
        XCTAssertNil(world.train(id: train.id))
        XCTAssertFalse(world.accounts.assets.contains { $0.kind == .train || $0.kind == .cars })
        let capital = try XCTUnwrap(world.accounts.capitalDays.first)
        XCTAssertEqual(capital.saleProceeds, Money(trainBook * 70 / 100 + carsBook * 70 / 100))
        XCTAssertEqual(capital.saleBookValue, Money(trainBook + carsBook))
        XCTAssertThrowsError(try world.sellTrain(train.id)) { XCTAssertEqual($0 as? GameError, .unknownTrain(train.id)) }
        // The ID is not given out again.
        XCTAssertEqual(try world.purchaseTrain(named: "Green").id, TrainID(rawValue: 2))
    }

    func testATrainOnTheTrackOnALineOrRunningAServiceIsNotSold() throws {
        var world = try makeWorld(economics: true)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        let train = try world.purchaseTrain(named: "Blue")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        XCTAssertThrowsError(try world.sellTrain(train.id)) { XCTAssertEqual($0 as? GameError, .trainInService(train.id)) }
        try world.assignTrain(train.id, to: main)
        XCTAssertThrowsError(try world.sellTrain(train.id)) { XCTAssertEqual($0 as? GameError, .trainInService(train.id)) }
        try world.unplaceTrain(train.id)
        XCTAssertThrowsError(try world.sellTrain(train.id), "still on its line") { XCTAssertEqual($0 as? GameError, .trainInService(train.id)) }
        try world.unassignTrain(train.id)
        XCTAssertNoThrow(try world.sellTrain(train.id))
    }

    func testSellingInFreePlayPaysNothingButStillRemovesTheTrain() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        let train = try world.purchaseTrain(named: "Blue")
        let before = world.economy.balance
        try world.sellTrain(train.id)
        XCTAssertEqual(world.economy.balance, before)
        XCTAssertTrue(world.trains.isEmpty)
    }

    // MARK: - Running costs

    /// The weight of the trains on lines, in thousandths of a standard train.
    private func weight(_ world: GameWorld) -> Int64 {
        var memo = GameWorld.DispatchMemo()
        return world.fixedAssets(memo: &memo).trainWeight
    }

    func testWeightIsOneThousandATrainWithoutTheSwitchWhateverItsCars() throws {
        var world = try makeWorld(economics: false)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Blue")
        try world.setTrainType(train.id, to: .maglev)
        try world.setTrainCars(train.id, to: 8)
        try world.assignTrain(train.id, to: main)
        XCTAssertEqual(weight(world), 1_000)
    }

    func testWeightIsCarsTimesTypeForTrainsOnALineAndNothingForIdleOnes() throws {
        var world = try makeWorld(economics: true)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        let blue = try world.purchaseTrain(named: "Blue")
        try world.setTrainType(blue.id, to: .maglev)
        try world.setTrainCars(blue.id, to: 4)
        let idle = try world.purchaseTrain(named: "Idle")
        try world.setTrainCars(idle.id, to: 6)
        XCTAssertEqual(weight(world), 0, "no train is on a line")
        try world.assignTrain(blue.id, to: main)
        XCTAssertEqual(weight(world), 4 * 1_800)
        let green = try world.purchaseTrain(named: "Green")
        try world.setTrainType(green.id, to: .l)
        try world.setTrainCars(green.id, to: 2)
        try world.assignTrain(green.id, to: main)
        XCTAssertEqual(weight(world), 4 * 1_800 + 2 * 700)
    }

    /// A day of a train that runs no service: staff and energy are written at
    /// midnight, weighted. A 4-car maglev is 7,200 thousandths of a train:
    /// 480 × 7.2 = 3,456 dollars of staff and 360 × 7.2 = 2,592 of energy.
    func testTheDaysStaffAndEnergyWeighTheTrain() throws {
        var world = try makeWorld(economics: true)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        let train = try world.purchaseTrain(named: "Blue")
        try world.setTrainType(train.id, to: .maglev)
        try world.setTrainCars(train.id, to: 4)
        try world.assignTrain(train.id, to: main)
        try world.advance(ticks: 1_441)
        let staff = try XCTUnwrap(world.accounts.entries.first { $0.kind == .dailyStaff })
        XCTAssertEqual(staff.breakdown.first { $0.item == .trainStaff }?.amount, Money(-3_456 * dollar))
        XCTAssertEqual(staff.amount, staff.breakdown.reduce(Money.zero) { $0 + $1.amount })
        let energy = try XCTUnwrap(world.accounts.entries.first { $0.kind == .dailyEnergy })
        XCTAssertEqual(energy.breakdown.first { $0.item == .trainEnergy }?.amount, Money(-2_592 * dollar))
        XCTAssertEqual(energy.amount, energy.breakdown.reduce(Money.zero) { $0 + $1.amount })
    }

    func testAStandardTrainCostsWhatItAlwaysDidWithOrWithoutTheSwitch() throws {
        var costs: [Money] = []
        for economics in [false, true] {
            var world = try makeWorld(economics: economics)
            try world.createLine(named: "Main", stops: [alpha, gamma])
            try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
            let train = try world.purchaseTrain(named: "Blue")
            try world.assignTrain(train.id, to: main)
            try world.advance(ticks: 1_441)
            let staff = try XCTUnwrap(world.accounts.entries.first { $0.kind == .dailyStaff })
            XCTAssertEqual(staff.breakdown.first { $0.item == .trainStaff }?.amount, Money(-480 * dollar))
            costs.append(staff.amount)
        }
        XCTAssertEqual(costs[0], costs[1])
    }

    // MARK: - The save

    func testTheSwitchSavesAndLoadsAndIsOffInOlderSaves() throws {
        var world = try makeWorld(economics: true)
        _ = try world.purchaseTrain(named: "Blue")
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"rollingStockEconomics\":true"))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        world.setRollingStockEconomics(false)
        let off = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertFalse(String(decoding: off, as: UTF8.self).contains("rollingStockEconomics"))
        XCTAssertFalse(try JSONDecoder().decode(SavedGame.self, from: off).world.rollingStockEconomics)
    }

    /// Version 49 (decision 180): a managed world with the switch on that has
    /// sold a train and kept another, a 2-car light-rail train that cost its
    /// type's prices and a refit. It saves byte for byte and is the world this
    /// build makes.
    func testVersionFortyNineKeepsTheSwitchAndTheBooks() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v49-rolling-stock-economics.json")
        var made = try makeWorld(economics: true, balance: 1_000_000_000)
        let sold = try made.purchaseTrain(named: "Sold")
        try made.setTrainType(sold.id, to: .maglev)
        try made.sellTrain(sold.id)
        let kept = try made.purchaseTrain(named: "Kept")
        try made.setTrainType(kept.id, to: .l)
        try made.setTrainCars(kept.id, to: 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["ROLLING_STOCK_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 49)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertTrue(world.rollingStockEconomics)
        XCTAssertEqual(world.trains.map(\.name), ["Kept"])
        XCTAssertEqual(world.train(id: kept.id)?.type, .l)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), data)
    }
}
