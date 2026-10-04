import Foundation
import GameCore
import XCTest

final class EconomyTests: XCTestCase {
    func testSpendAndEarnAdjustBalanceExactly() throws {
        var economy = GameEconomy(balance: 1_000)

        try economy.spend(250)
        economy.earn(75)

        XCTAssertEqual(economy.balance, 825)
    }

    func testSpendingMoreThanBalanceFailsWithoutChange() {
        var economy = GameEconomy(balance: 100)

        XCTAssertThrowsGameError(try economy.spend(101), .insufficientFunds(required: 101, available: 100))
        XCTAssertEqual(economy.balance, 100)
        XCTAssertFalse(economy.canAfford(101))
        XCTAssertTrue(economy.canAfford(100))
    }
}

/// Decision 46: each car added to a train costs ``ConstructionCosts/car``,
/// as the reference's management mode spends a car of its quota; taking
/// cars off pays nothing back. Worlds and saves from before it add cars
/// for nothing.
final class CarPriceTests: XCTestCase {
    private func makeWorld(balance: Money, car: Money) throws -> (GameWorld, TrainID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 4_096, height: 2_048), economy: GameEconomy(balance: balance, costs: ConstructionCosts(track: 100, station: 1_000, train: 5_000, car: car))
        )
        let train = try world.purchaseTrain(named: "T").id
        return (world, train)
    }

    func testEachAddedCarIsPaidForAndNoneIsPaidBack() throws {
        var (world, train) = try makeWorld(balance: 100_000, car: 2_000)
        XCTAssertEqual(world.economy.balance, 95_000, "a new train, with its first car")
        try world.setTrainCars(train, to: 4)
        XCTAssertEqual(world.economy.balance, 89_000, "three cars added")
        try world.setTrainCars(train, to: 2)
        XCTAssertEqual(world.economy.balance, 89_000, "taken off: nothing back")
        try world.setTrainCars(train, to: 3)
        XCTAssertEqual(world.economy.balance, 87_000, "added again: paid again")
        XCTAssertEqual(world.train(id: train)?.cars, 3)
    }

    func testCarsBeyondTheBalanceChangeNothing() throws {
        var (world, train) = try makeWorld(balance: 10_000, car: 2_000)
        let before = world
        XCTAssertThrowsGameError(try world.setTrainCars(train, to: 4), .insufficientFunds(required: 6_000, available: 5_000))
        XCTAssertEqual(world, before)
        var (dear, other) = try makeWorld(balance: 10_000, car: Money(.max))
        let unchanged = dear
        XCTAssertThrowsGameError(try dear.setTrainCars(other, to: 2), .insufficientFunds(required: Money(.max), available: 5_000))
        // Two cars' price overflows: still more than any balance.
        XCTAssertThrowsGameError(try dear.setTrainCars(other, to: 3), .insufficientFunds(required: Money(.max), available: 5_000))
        XCTAssertEqual(dear, unchanged)
    }

    /// A managed company that is in the red after a day: two stations and a
    /// line cost more to run than the one train earns.
    private func makeCompanyInTheRed(car: Money) throws -> (GameWorld, TrainID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096),
            economy: GameEconomy(balance: 100_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 5_000, car: car)),
            clock: GameClock(speed: .normal)
        )
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        try world.createLine(named: "Main", stops: [StationID(rawValue: 1), StationID(rawValue: 2)])
        let spare = try world.purchaseTrain(named: "Spare").id
        world.setEconomyMode(.management)
        try world.advance(ticks: 1_441)
        XCTAssertLessThan(world.economy.balance, .zero, "the setup is a company in the red")
        return (world, spare)
    }

    /// Cars cost nothing in a save from before they had a price, and such a
    /// company is soon in the red: adding cars must still work, as it did
    /// before they were charged for (`spend` would refuse a price of 0
    /// against a negative balance).
    func testFreeCarsAreAddedEvenWithANegativeBalance() throws {
        var (world, spare) = try makeCompanyInTheRed(car: .zero)
        let balance = world.economy.balance
        try world.setTrainCars(spare, to: 3)
        XCTAssertEqual(world.train(id: spare)?.cars, 3)
        XCTAssertEqual(world.economy.balance, balance, "nothing was charged")
    }

    func testPricedCarsAreStillRefusedWithANegativeBalance() throws {
        var (world, spare) = try makeCompanyInTheRed(car: 2_000)
        let before = world
        XCTAssertThrowsGameError(
            try world.setTrainCars(spare, to: 2),
            .insufficientFunds(required: 2_000, available: world.economy.balance)
        )
        XCTAssertEqual(world, before)
    }

    func testFreeCarsSaveAsBeforeAndPricedOnesRoundTrip() throws {
        let free = ConstructionCosts(track: 1, station: 2, train: 3)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(free)) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["track", "station", "train"], "free cars are not written")
        XCTAssertEqual(try JSONDecoder().decode(ConstructionCosts.self, from: Data(#"{"track":1,"station":2,"train":3}"#.utf8)), free, "a save from before cars had a price")
        let priced = ConstructionCosts(track: 1, station: 2, train: 3, car: 4)
        XCTAssertEqual(try JSONDecoder().decode(ConstructionCosts.self, from: try JSONEncoder().encode(priced)), priced)
        XCTAssertThrowsError(try JSONDecoder().decode(ConstructionCosts.self, from: Data(#"{"track":1,"station":2,"train":3,"car":-1}"#.utf8)))
    }
}
