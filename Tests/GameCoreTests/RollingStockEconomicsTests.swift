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
        // A change of type: the new train's price less the old one's sale value, at least nothing.
        XCTAssertEqual(RollingStock.refitFee(price: Money(105_000_000), tradeIn: Money(10_500_000)), Money(94_500_000))
        XCTAssertEqual(RollingStock.refitFee(price: Money(1_650_000), tradeIn: Money(7_350_000)), .zero)
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
        XCTAssertEqual(paid(), 60_000_000 - 10_500_000, "a $600,000 maglev less 70 % of the $150,000 train")
        try world.setTrainType(train.id, to: .maglev)
        XCTAssertEqual(paid(), 0, "the same type is no refit")
        try world.setTrainCars(train.id, to: 4)
        XCTAssertEqual(paid(), 3 * 150_000 * dollar, "three maglev cars")
        try world.setTrainType(train.id, to: .l)
        // Four light-rail cars cost $165,000; the maglev train is worth 70 % of $600,000 + $450,000 more:
        // nothing is paid, and nothing is paid back.
        XCTAssertEqual(paid(), 0, "a downgrade costs nothing")
        // What the books hold: the new train at its price, the old records sold.
        let book = world.accounts.assets.filter { $0.kind == .train || $0.kind == .cars }.reduce(Money.zero) { $0 + $1.cost }
        XCTAssertEqual(book, Money(16_500_000))
        let capital = try XCTUnwrap(world.accounts.capitalDays.first)
        XCTAssertEqual(capital.saleProceeds, Money(10_500_000 + 16_500_000), "the first change and the second sold at what the new cost, at most")
    }

    /// The loophole the rule closes: a cheap type, cars added, then changed
    /// to the dear type never costs less than buying the dear type outright.
    func testBuyingCheapAddingCarsAndChangingTypeIsNeverCheaperThanBuyingOutright() throws {
        for cars in [1, 4, 8, 16] {
            var direct = try makeWorld(economics: true)
            let start = direct.economy.balance
            let outright = try direct.purchaseTrain(named: "Direct", as: .highSpeed)
            try direct.setTrainCars(outright.id, to: cars)
            let directCost = start - direct.economy.balance

            var roundabout = try makeWorld(economics: true)
            let cheap = try roundabout.purchaseTrain(named: "Cheap", as: .l)
            try roundabout.setTrainCars(cheap.id, to: cars)
            try roundabout.setTrainType(cheap.id, to: .highSpeed)
            let roundaboutCost = start - roundabout.economy.balance
            XCTAssertGreaterThanOrEqual(roundaboutCost, directCost, "\(cars) cars")
            XCTAssertEqual(roundabout.train(id: cheap.id)?.cars, cars)
        }
    }

    func testTheChangeOfTypeCostIsTheNewPriceLessWhatTheOldWouldSellFor() throws {
        var world = try makeWorld(economics: true)
        let train = try world.purchaseTrain(named: "Blue", as: .l)
        try world.setTrainCars(train.id, to: 3)
        // The books: $90,000 + 2 × $25,000 = $140,000, 70 % is $98,000.
        XCTAssertEqual(world.trainSaleQuote(train.id), Money(9_800_000))
        XCTAssertEqual(world.refitCost(of: train.id, to: .maglev), Money((600_000 + 2 * 150_000) * 100 - 9_800_000))
        XCTAssertEqual(world.refitCost(of: train.id, to: .l), .zero, "the type it is")
        XCTAssertEqual(world.refitCost(of: TrainID(rawValue: 9), to: .maglev), .zero)
        let before = world.economy.balance
        try world.setTrainType(train.id, to: .maglev)
        XCTAssertEqual(before - world.economy.balance, Money((600_000 + 2 * 150_000) * 100 - 9_800_000))
        // What it is worth now: 70 % of the new price, whatever the old books were.
        XCTAssertEqual(world.trainSaleQuote(train.id), Money(90_000_000 * 70 / 100))
    }

    func testWithoutTheSwitchTheChangeOfTypeStaysFree() throws {
        var world = try makeWorld(economics: false)
        let train = try world.purchaseTrain(named: "Blue")
        XCTAssertEqual(world.refitCost(of: train.id, to: .maglev), .zero)
        let before = world.economy.balance
        try world.setTrainType(train.id, to: .maglev)
        XCTAssertEqual(world.economy.balance, before)
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

    /// A change to a cheaper type the old train more than pays for costs
    /// nothing (``refitCost(of:to:)`` quotes nothing), so it is made even in
    /// the red; it used to sell the old train, then spend the new price
    /// against a negative balance, and throw with the old train's records
    /// already sold.
    func testAChangeOfTypeTheOldTrainPaysForIsMadeInTheRed() throws {
        var world = try makeWorld(economics: true)
        let train = try world.purchaseTrain(named: "Fast", as: .highSpeed)
        world.economy.settle(Money(-world.economy.balance.amount - 100))
        XCTAssertEqual(world.refitCost(of: train.id, to: .l), .zero)
        try world.setTrainType(train.id, to: .l)
        XCTAssertEqual(world.train(id: train.id)?.type, .l)
        // Sold for $630,000, the L bought for $90,000: the rest is not paid
        // back, and the balance is where it was.
        XCTAssertEqual(world.economy.balance, Money(-100))
        XCTAssertEqual(world.trainSaleQuote(train.id), Money(9_000_000 * 70 / 100))
    }

    /// After a change of type, the cars taken off write off their share
    /// of the new price, as cars bought do: a train of one car is worth on
    /// the books what one bought as it is would be.
    func testCarsTakenOffAfterAChangeOfTypeLeaveTheBooks() throws {
        var world = try makeWorld(economics: true)
        let train = try world.purchaseTrain(named: "Blue", as: .l)
        try world.setTrainCars(train.id, to: 16)
        try world.setTrainType(train.id, to: .highSpeed)
        XCTAssertEqual(world.trainSaleQuote(train.id), Money((900_000 + 15 * 120_000) * 100 * 70 / 100))
        try world.setTrainCars(train.id, to: 1)
        XCTAssertEqual(world.trainSaleQuote(train.id), Money(900_000 * 100 * 70 / 100), "a one-car high-speed train")
        XCTAssertEqual(world.accounts.capitalDays.last?.writeOff, Money(15 * 120_000 * 100))
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
    }

    func testSellingBringsSeventyPercentOfTheBookValueAndTheTrainIsGone() throws {
        var world = try makeWorld(economics: true)
        let train = try world.purchaseTrain(named: "Blue")
        try world.setTrainType(train.id, to: .maglev)
        try world.setTrainCars(train.id, to: 4)
        let before = world.economy.balance
        try world.sellTrain(train.id)
        // The train record is the maglev bought in the change, $600,000; the cars: 3 maglev cars at $150,000.
        let trainBook: Int64 = 60_000_000
        let carsBook: Int64 = 3 * 15_000_000
        XCTAssertEqual(world.economy.balance - before, Money(trainBook * 70 / 100 + carsBook * 70 / 100))
        XCTAssertNil(world.train(id: train.id))
        XCTAssertFalse(world.accounts.assets.contains { $0.kind == .train || $0.kind == .cars })
        let capital = try XCTUnwrap(world.accounts.capitalDays.first)
        // The change of type sold the standard train for 70 % of $150,000, then the sale.
        XCTAssertEqual(capital.saleProceeds, Money(10_500_000 + trainBook * 70 / 100 + carsBook * 70 / 100))
        XCTAssertEqual(capital.saleBookValue, Money(15_000_000 + trainBook + carsBook))
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

    /// Decision 179 with decision 180: two lines with trains of different
    /// type and cars still add up to the company's day, and each line's staff
    /// and energy follow its trains' weight.
    func testLinesStillAddUpToTheCompanyWithWeightedTrains() throws {
        var world = try makeWorld(economics: true)
        world.setLineAccounts(true)
        let beta = StationID(rawValue: 2)
        try world.createLine(named: "First", stops: [alpha, beta])
        try world.createLine(named: "Second", stops: [beta, gamma])
        let first = LineID(rawValue: 1), second = LineID(rawValue: 2)
        let heavy = try world.purchaseTrain(named: "Heavy", as: .maglev)
        try world.setTrainCars(heavy.id, to: 4)
        let light = try world.purchaseTrain(named: "Light", as: .l)
        try world.setTrainCars(light.id, to: 2)
        try world.assignTrain(heavy.id, to: first)
        try world.assignTrain(light.id, to: second)
        try world.advance(ticks: 1_441)
        let company = try XCTUnwrap(world.accounts.days.first { $0.day == 0 })
        let one = try XCTUnwrap(world.lineDays(first).first { $0.day == 0 }?.tally)
        let two = try XCTUnwrap(world.lineDays(second).first { $0.day == 0 }?.tally)
        XCTAssertEqual(one.staffCost + two.staffCost, company.staffCost)
        XCTAssertEqual(one.energyCost + two.energyCost, company.energyCost)
        XCTAssertEqual(one.maintenanceCost + two.maintenanceCost, company.maintenanceCost)
        // Train staff: 4 maglev cars weigh 7,200 (3,456 dollars), 2 L cars 1,400 (672 dollars);
        // each line also pays its own two stations' 620.
        XCTAssertEqual(one.staffCost, Money((620 * 2 + 3_456) * dollar))
        XCTAssertEqual(two.staffCost, Money((620 * 2 + 672) * dollar))
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
    /// sold a train and kept another, a 2-car light-rail train. The save was
    /// written when a change of type cost 30 % of the new type's price, so its
    /// books hold that refit ($2,700 on the train's $150,000, `17,700,000`);
    /// since the follow-up rule (a change of type costs the new price less the
    /// old train's sale value) the commands that made it would make another
    /// world, so this test does not rebuild it: an old save is read as it was
    /// stored, and a later change of type is charged by the new rule. The
    /// file itself is never rewritten.
    func testVersionFortyNineKeepsTheSwitchAndTheBooks() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v49-rolling-stock-economics.json")
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 49)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertTrue(world.rollingStockEconomics)
        XCTAssertEqual(world.trains.map(\.name), ["Kept"])
        let kept = try XCTUnwrap(world.trains.first)
        XCTAssertEqual(kept.type, .l)
        XCTAssertEqual(kept.cars, 2)
        // The books and the balance as they were stored.
        XCTAssertEqual(world.economy.balance, Money(969_896_400))
        let records = world.accounts.assets.filter { $0.owner == kept.id.rawValue && ($0.kind == .train || $0.kind == .cars) }
        XCTAssertEqual(records.map(\.cost), [Money(17_700_000), Money(2_500_000)])
        let capital = try XCTUnwrap(world.accounts.capitalDays.first)
        XCTAssertEqual(capital.saleProceeds, Money(23_100_000))
        XCTAssertEqual(capital.saleBookValue, Money(33_000_000))
        // Saved again by a later build: the same bytes with its version.
        let current = Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 49,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), current)
        // It goes on to be the same world as one that never was saved.
        var carried = try JSONDecoder().decode(SavedGame.self, from: try encoder.encode(SavedGame(world: world))).world
        try carried.advance(ticks: 40)
        try world.advance(ticks: 40)
        XCTAssertEqual(carried, world)
        // A later change of type is charged by the new rule: the new price
        // less 70 % of the books ($177,000 + $25,000 for the two cars).
        let quote = world.trainSaleQuote(kept.id)
        XCTAssertEqual(quote, Money((17_700_000 + 2_500_000) * 70 / 100))
        XCTAssertEqual(world.refitCost(of: kept.id, to: .maglev), Money((600_000 + 150_000) * 100) - quote)
    }

    /// A save may hold a train whose books are as large as the accounts
    /// allow; changing its type shares the proceeds out without a crash.
    func testARefitOfATrainWithHugeBooksDoesNotOverflow() throws {
        var world = try makeWorld(economics: true)
        let train = try world.purchaseTrain(named: "Blue")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = String(decoding: try encoder.encode(world), as: UTF8.self)
        let record = #""cost":15000000,"days":0,"depreciation":0,"kind":"train""#
        XCTAssertTrue(text.contains(record))
        let huge = text.replacingOccurrences(of: record, with: #""cost":\#(Int64(1) << 49),"days":0,"depreciation":0,"kind":"train""#)
        var loaded = try JSONDecoder().decode(GameWorld.self, from: Data(huge.utf8))
        try loaded.setTrainType(train.id, to: .steam)
        XCTAssertEqual(loaded.train(id: train.id)?.type, .steam)
    }
}
