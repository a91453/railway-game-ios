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

/// Stage W2c: how far along a service's run a train is `elapsed` seconds
/// after it set off: the running curve its performance builds for
/// `length` units in `seconds` (W1's `RunningCurve`, checked against the
/// reference's JavaScript in `RunningCurveTests`), all of it from the end
/// of the run. Tests work arrival times out by hand; where a train is in
/// between follows the curve, and this reads it off.
func runDistance(_ length: Int64, in seconds: Int64, after elapsed: Int64, performance: TrainPerformance = .standard) -> Int64 {
    guard elapsed > 0 else { return 0 }
    guard elapsed < seconds else { return length }
    return RunningCurve(length: length, duration: seconds * 1000, performance: performance)!.distance(at: elapsed * 1000)
}
