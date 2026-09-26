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
