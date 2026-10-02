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

    // MARK: - Seconds (Stage W2a)

    /// A speed's name is how many times real time it runs at, with the host
    /// ticking every 100 ms; normal and double are a minute and two a tick.
    func testEachSpeedRunsItsTenthsOfASecondATick() throws {
        let expected: [GameSpeed: Int64] = [.paused: 0, .x1: 1, .x10: 10, .x60: 60, .normal: 600, .double: 1_200]
        XCTAssertEqual(Set(GameSpeed.allCases), Set(expected.keys))
        for (speed, tenths) in expected {
            XCTAssertEqual(speed.tenthsPerTick, tenths, "\(speed)")
            var clock = GameClock(speed: speed)
            try clock.advance(ticks: 10)
            XCTAssertEqual(clock.now, GameTime(seconds: tenths), "\(speed)")
            XCTAssertEqual(clock.pendingTenths, 0, "\(speed)")
        }
    }

    /// Real time runs a second every 10 ticks; the tenths that make no whole
    /// second yet wait, through a pause and a change of speed.
    func testRealTimeKeepsTheTenthsThatMakeNoWholeSecondYet() throws {
        var clock = GameClock(speed: .x1)
        try clock.advance(ticks: 7)
        XCTAssertEqual(clock.now, .zero)
        XCTAssertEqual(clock.pendingTenths, 7)

        try clock.advance(ticks: 5)
        XCTAssertEqual(clock.now, GameTime(seconds: 1))
        XCTAssertEqual(clock.pendingTenths, 2)

        clock.pause()
        try clock.advance(ticks: 100)
        XCTAssertEqual(clock.now, GameTime(seconds: 1))
        XCTAssertEqual(clock.pendingTenths, 2)

        clock.setSpeed(.x10)
        try clock.advance(ticks: 3)
        XCTAssertEqual(clock.now, GameTime(seconds: 4))
        XCTAssertEqual(clock.pendingTenths, 2)

        clock.setSpeed(.x1)
        try clock.advance(ticks: 8)
        XCTAssertEqual(clock.now, GameTime(seconds: 5))
        XCTAssertEqual(clock.pendingTenths, 0)
    }

    /// Ticks one at a time and in a batch give the same clock.
    func testTicksAtRealTimeAddUpWhateverTheBatches() throws {
        var single = GameClock(speed: .x1)
        for _ in 0..<1_234 {
            try single.advance(ticks: 1)
        }
        var batch = GameClock(speed: .x1)
        try batch.advance(ticks: 1_234)
        XCTAssertEqual(single, batch)
        XCTAssertEqual(batch.now, GameTime(seconds: 123))
        XCTAssertEqual(batch.pendingTenths, 4)
    }

    /// The tenths count toward the end of time too: a batch that would pass
    /// the largest second changes nothing.
    func testTheEndOfTimeCountsThePendingTenths() throws {
        var clock = GameClock(now: GameTime(seconds: .max - 1), speed: .x1)
        try clock.advance(ticks: 19)
        XCTAssertEqual(clock.now, GameTime(seconds: .max))
        XCTAssertEqual(clock.pendingTenths, 9)
        let before = clock
        XCTAssertThrowsGameError(try clock.advance(ticks: 1), .clockOverflow)
        XCTAssertEqual(clock, before)
        try clock.advance(ticks: 0)
        XCTAssertEqual(clock, before)
    }

    /// The running speed is the clock's speed, or while paused the one it
    /// resumes at.
    func testTheRunningSpeedIsTheOneAPausedClockResumesAt() {
        var clock = GameClock(speed: .x60)
        XCTAssertEqual(clock.runningSpeed, .x60)
        clock.pause()
        XCTAssertEqual(clock.runningSpeed, .x60)
        XCTAssertEqual(GameClock().runningSpeed, .normal)
    }

    /// Pending tenths are saved only when there are some, so clocks saved
    /// before Stage W2a read as having none; a value no clock can hold is
    /// rejected.
    func testPendingTenthsAreSavedOnlyWhenThereAreSome() throws {
        var clock = GameClock(now: GameTime(seconds: 90), speed: .x1)
        try clock.advance(ticks: 3)
        let encoded = try JSONEncoder().encode(clock)
        XCTAssertEqual(try JSONDecoder().decode(GameClock.self, from: encoded), clock)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("\"pendingTenths\":3"))

        let whole = String(decoding: try JSONEncoder().encode(GameClock(now: GameTime(seconds: 90), speed: .x1)), as: UTF8.self)
        XCTAssertFalse(whole.contains("pendingTenths"))

        let old = Data(#"{"now": 5, "speed": "normal", "resumeSpeed": "normal"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(GameClock.self, from: old).pendingTenths, 0)
        for bad in ["-1", "10", "null"] {
            let data = Data(#"{"now": 5, "speed": "x1", "resumeSpeed": "x1", "pendingTenths": \#(bad)}"#.utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(GameClock.self, from: data), bad)
        }
    }

    /// A time knows its minute and second, also before second 0.
    func testATimeKnowsItsMinuteAndSecond() {
        let ends: [(Int64, Int64, Int64)] = [(.min, Int64.min / 60 - 1, 52), (.max, Int64.max / 60, 7)]
        for (seconds, minute, second): (Int64, Int64, Int64) in [(0, 0, 0), (59, 0, 59), (60, 1, 0), (125, 2, 5), (-1, -1, 59), (-60, -1, 0), (-61, -2, 59)] + ends {
            let time = GameTime(seconds: seconds)
            XCTAssertEqual(time.minute, minute, "\(seconds)")
            XCTAssertEqual(time.secondOfMinute, second, "\(seconds)")
            XCTAssertEqual(time.isWholeMinute, second == 0, "\(seconds)")
        }
        XCTAssertEqual(GameTime(minutes: 3), GameTime(seconds: 180))
    }
}
