import GameCore
import XCTest

final class GameClockTests: XCTestCase {
    func testPausedClockDoesNotAdvance() throws {
        var clock = GameClock(speed: .paused)

        try clock.advance(ticks: 100)

        XCTAssertEqual(clock.now, .zero)
        XCTAssertTrue(clock.isPaused)
    }

    func testNormalSpeedAdvancesOneMinutePerTick() throws {
        var clock = GameClock(speed: .normal)

        try clock.advance(ticks: 30)

        XCTAssertEqual(clock.now, GameTime(minutes: 30))
    }

    func testDoubleSpeedAdvancesTwoMinutesPerTick() throws {
        var clock = GameClock(speed: .double)

        try clock.advance(ticks: 30)

        XCTAssertEqual(clock.now, GameTime(minutes: 60))
    }

    func testPauseAndResumeRestorePreviousSpeed() throws {
        var clock = GameClock(speed: .normal)
        clock.setSpeed(.double)
        try clock.advance(ticks: 5)

        clock.pause()
        try clock.advance(ticks: 5)
        XCTAssertEqual(clock.now, GameTime(minutes: 10))

        clock.resume()
        try clock.advance(ticks: 5)
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
        try world.advance(ticks: 3)
        world.pause()
        try world.advance(ticks: 3)
        world.resume()
        try world.advance(ticks: 1)

        XCTAssertEqual(world.clock.now, GameTime(minutes: 8))
    }
}
