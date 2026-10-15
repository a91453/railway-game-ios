import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 37 under decision 228: a minute run in one step
/// leaves the high-speed demo's sets where sixty one-second steps do, so
/// the game plays the same at every speed and a problem report's merged
/// steps rebuild the world the device had.
final class HighSpeedDemoBatchTests: XCTestCase {
    func testAMinuteInOneStepIsSixtyOneSecondSteps() throws {
        var minutes = try HighSpeedDemoTests.opened.get()
        minutes.setSpeed(.normal)
        var seconds = minutes
        seconds.setSpeed(.x10)
        for minute in 1...30 {
            try minutes.advance(ticks: 1)
            for _ in 0..<60 { try seconds.advance(ticks: 1) }
            XCTAssertEqual(minutes.clock.now, seconds.clock.now)
            guard minutes.trains == seconds.trains else {
                let differ = zip(minutes.trains, seconds.trains).filter { $0.0 != $0.1 }.map(\.0.name)
                return XCTFail("minute \(minute): \(differ.joined(separator: ", ")) differ")
            }
        }
    }
}
