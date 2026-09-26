import GameCore
import XCTest

final class GameClockTests: XCTestCase {
    func testPausedClockDoesNotAdvance() {
        var clock = GameClock(speed: .paused)

        clock.advance(ticks: 100)

        XCTAssertEqual(clock.now, .zero)
        XCTAssertTrue(clock.isPaused)
    }

    func testNormalSpeedAdvancesOneMinutePerTick() {
        var clock = GameClock(speed: .normal)

        clock.advance(ticks: 30)

        XCTAssertEqual(clock.now, GameTime(minutes: 30))
    }

    func testDoubleSpeedAdvancesTwoMinutesPerTick() {
        var clock = GameClock(speed: .double)

        clock.advance(ticks: 30)

        XCTAssertEqual(clock.now, GameTime(minutes: 60))
    }

    func testPauseAndResumeRestorePreviousSpeed() {
        var clock = GameClock(speed: .normal)
        clock.setSpeed(.double)
        clock.advance(ticks: 5)

        clock.pause()
        clock.advance(ticks: 5)
        XCTAssertEqual(clock.now, GameTime(minutes: 10))

        clock.resume()
        clock.advance(ticks: 5)
        XCTAssertEqual(clock.speed, .double)
        XCTAssertEqual(clock.now, GameTime(minutes: 20))
    }

    func testResumeFromInitiallyPausedClockRunsAtNormalSpeed() {
        var clock = GameClock()

        clock.resume()

        XCTAssertEqual(clock.speed, .normal)
    }

    func testWorldAdvancesItsClock() throws {
        var world = try makeWorld()
        world.setSpeed(.double)
        world.advance(ticks: 3)
        world.pause()
        world.advance(ticks: 3)
        world.resume()
        world.advance(ticks: 1)

        XCTAssertEqual(world.clock.now, GameTime(minutes: 8))
    }
}
