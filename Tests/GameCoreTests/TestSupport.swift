import GameCore
import XCTest

/// Costs used across tests so expected balances are easy to read.
let testCosts = ConstructionCosts(track: 100, station: 1_000, train: 5_000)

func makeWorld(
    width: Int = 20,
    height: Int = 20,
    balance: Money = 10_000
) throws -> GameWorld {
    try GameWorld(width: width, height: height, economy: GameEconomy(balance: balance, costs: testCosts))
}

/// Asserts that `expression` throws exactly `expected`.
func XCTAssertThrowsGameError<T>(
    _ expression: @autoclosure () throws -> T,
    _ expected: GameError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
        XCTAssertEqual(error as? GameError, expected, file: file, line: line)
    }
}
