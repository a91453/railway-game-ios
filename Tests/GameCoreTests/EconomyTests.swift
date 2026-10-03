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
            width: 4, height: 2, economy: GameEconomy(balance: balance, costs: ConstructionCosts(track: 100, station: 1_000, train: 5_000, car: car))
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
