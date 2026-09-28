import GamePresentation
import XCTest

final class TickAccumulatorTests: XCTestCase {
    private func makeAccumulator() -> TickAccumulator {
        TickAccumulator(tickInterval: .milliseconds(100), maximumElapsed: .milliseconds(500))
    }

    func testLessThanOneTickIsKeptForLater() {
        var accumulator = makeAccumulator()

        XCTAssertEqual(accumulator.ticks(for: .milliseconds(99)), 0)
        XCTAssertEqual(accumulator.pending, .milliseconds(99))
    }

    func testExactlyOneTick() {
        var accumulator = makeAccumulator()

        XCTAssertEqual(accumulator.ticks(for: .milliseconds(100)), 1)
        XCTAssertEqual(accumulator.pending, .zero)
    }

    func testSeveralTicksAtOnce() {
        var accumulator = makeAccumulator()

        XCTAssertEqual(accumulator.ticks(for: .milliseconds(300)), 3)
        XCTAssertEqual(accumulator.pending, .zero)
    }

    func testFractionalRemaindersCarryOver() {
        var accumulator = makeAccumulator()

        XCTAssertEqual(accumulator.ticks(for: .milliseconds(150)), 1)
        XCTAssertEqual(accumulator.pending, .milliseconds(50))
        XCTAssertEqual(accumulator.ticks(for: .milliseconds(60)), 1)
        XCTAssertEqual(accumulator.pending, .milliseconds(10))
        XCTAssertEqual(accumulator.ticks(for: .milliseconds(89)), 0)
        XCTAssertEqual(accumulator.ticks(for: .milliseconds(1)), 1)
        XCTAssertEqual(accumulator.pending, .zero)
    }

    func testIrregularFramesAddUpWithoutDrift() {
        var accumulator = makeAccumulator()
        // 1,000 frames of 16.667 ms, as a 60 Hz host would report them.
        let frame = Duration.microseconds(16_667)
        var total = 0
        for _ in 0..<1_000 {
            total += accumulator.ticks(for: frame)
        }
        // 16.667 s of real time is 166 whole ticks with 67 ms left over.
        XCTAssertEqual(total, 166)
        XCTAssertEqual(accumulator.pending, .milliseconds(67))
    }

    func testLongStallsAreCappedInsteadOfCaughtUp() {
        var accumulator = makeAccumulator()

        XCTAssertEqual(accumulator.ticks(for: .seconds(3_600)), 5)
        XCTAssertEqual(accumulator.pending, .zero)
    }

    func testNegativeDurationsCountAsZero() {
        var accumulator = makeAccumulator()
        _ = accumulator.ticks(for: .milliseconds(40))

        XCTAssertEqual(accumulator.ticks(for: .milliseconds(-500)), 0)
        XCTAssertEqual(accumulator.pending, .milliseconds(40))
    }

    func testResetDropsThePartialTick() {
        var accumulator = makeAccumulator()
        _ = accumulator.ticks(for: .milliseconds(90))

        accumulator.reset()

        XCTAssertEqual(accumulator.pending, .zero)
        XCTAssertEqual(accumulator.ticks(for: .milliseconds(20)), 0)
    }
}
