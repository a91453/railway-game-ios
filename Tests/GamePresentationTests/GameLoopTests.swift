import GameCore
import GamePresentation
import XCTest

final class GameLoopTests: XCTestCase {
    func testTheSessionUsesTheDocumentedTickRate() {
        XCTAssertEqual(GameSession.tickInterval, .milliseconds(100))
        XCTAssertEqual(GameSession.maximumStepDuration, .milliseconds(500))
    }

    func testOneTickPerIntervalAtNormalSpeed() async throws {
        let world = try makeWorld(speed: .normal)
        await MainActor.run {
            let session = GameSession(world: world)

            session.advance(realElapsed: .milliseconds(40))
            session.advance(realElapsed: .milliseconds(40))
            XCTAssertEqual(session.world.clock.now, .zero)
            session.advance(realElapsed: .milliseconds(40))
            XCTAssertEqual(session.world.clock.now, GameTime(minutes: 1))
            session.advance(realElapsed: .milliseconds(280))
            XCTAssertEqual(session.world.clock.now, GameTime(minutes: 4))
        }
    }

    func testDoubleSpeedKeepsTheTickRateAndLetsGameCoreApplyTheSpeed() async throws {
        let world = try makeWorld(speed: .double)
        var expected = world
        try expected.advance(ticks: 3)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)

            session.advance(realElapsed: .milliseconds(300))

            XCTAssertEqual(session.world, expected, "three ticks, not a larger step")
            XCTAssertEqual(session.world.clock.now, GameTime(minutes: 6))
        }
    }

    func testTimeThatCannotAdvanceChangesNothingAndIsReported() async throws {
        let world = try GameWorld(
            width: 8, height: 6,
            economy: GameEconomy(balance: 10_000, costs: testCosts),
            clock: GameClock(now: GameTime(seconds: .max - 60), speed: .normal)
        )
        await MainActor.run {
            let session = GameSession(world: world)

            // Three ticks, but only one minute is left: nothing advances.
            session.advance(realElapsed: .milliseconds(300))

            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.clockOverflow.playerMessage(in: .english)))
        }
    }

    func testPausedTimeIsDiscardedNotSavedUp() async throws {
        let world = try makeWorld(speed: .normal)
        await MainActor.run {
            let session = GameSession(world: world)
            session.advance(realElapsed: .milliseconds(90))

            session.setSpeed(.paused)
            session.advance(realElapsed: .seconds(10))
            XCTAssertEqual(session.world.clock.now, .zero)

            session.setSpeed(.normal)
            session.advance(realElapsed: .milliseconds(20))
            XCTAssertEqual(session.world.clock.now, .zero, "neither the paused time nor the old partial tick counts")
            session.advance(realElapsed: .milliseconds(80))
            XCTAssertEqual(session.world.clock.now, GameTime(minutes: 1))
        }
    }

    func testAStallIsCappedAtFiveTicks() async throws {
        let world = try makeWorld(speed: .normal)
        await MainActor.run {
            let session = GameSession(world: world)

            session.advance(realElapsed: .seconds(4 * 3_600))

            XCTAssertEqual(session.world.clock.now, GameTime(minutes: 5))
        }
    }

    func testStoppingTheLoopDropsThePartialTick() async throws {
        let world = try makeWorld(speed: .normal)
        await MainActor.run {
            let session = GameSession(world: world)
            session.advance(realElapsed: .milliseconds(90))

            // What the host does when the app leaves the foreground.
            session.stopGameLoop()
            session.advance(realElapsed: .milliseconds(20))

            XCTAssertEqual(session.world.clock.now, .zero)
            XCTAssertFalse(session.isGameLoopRunning)
        }
    }

    func testTheLoopAdvancesInRealTimeAndNeverTicksTwice() async throws {
        let session = await GameSession(world: try makeWorld(speed: .normal))
        let clock = ContinuousClock()
        let start = clock.now

        // Starting twice must not create a second loop.
        await session.startGameLoop()
        await session.startGameLoop()
        let isRunning = await session.isGameLoopRunning
        XCTAssertTrue(isRunning)

        _ = try await waitForMinutes(atLeast: 3, in: session, clock: clock)
        await session.stopGameLoop()
        let elapsed = clock.now - start
        let advanced = await session.world.clock.now.minute

        XCTAssertGreaterThanOrEqual(advanced, 3)
        // One loop turns at most the elapsed real time into ticks; a second
        // loop would roughly double the count.
        XCTAssertLessThanOrEqual(advanced, wholeTicks(in: elapsed))

        // Once stopped, time stands still.
        try await Task.sleep(for: .milliseconds(300))
        let afterStop = await session.world.clock.now.minute
        let isStillRunning = await session.isGameLoopRunning
        XCTAssertEqual(afterStop, advanced)
        XCTAssertFalse(isStillRunning)
    }

    func testRestartingAfterAStopDoesNotReplayTheStoppedTime() async throws {
        let session = await GameSession(world: try makeWorld(speed: .normal))
        let clock = ContinuousClock()

        await session.startGameLoop()
        let firstRun = try await waitForMinutes(atLeast: 1, in: session, clock: clock)
        await session.stopGameLoop()

        // Time passes while stopped, as when the app is in the background.
        try await Task.sleep(for: .milliseconds(500))
        let beforeRestart = await session.world.clock.now.minute
        XCTAssertEqual(beforeRestart, firstRun)

        let restart = clock.now
        await session.startGameLoop()
        await session.startGameLoop()
        _ = try await waitForMinutes(atLeast: firstRun + 2, in: session, clock: clock)
        await session.stopGameLoop()
        let sinceRestart = clock.now - restart
        let total = await session.world.clock.now.minute

        // Only time since the restart counts, and only one loop is ticking.
        XCTAssertLessThanOrEqual(total - firstRun, wholeTicks(in: sinceRestart))
    }

    /// Polls until the world reaches `minutes`, failing after ten seconds.
    private func waitForMinutes(
        atLeast minutes: Int64,
        in session: GameSession,
        clock: ContinuousClock
    ) async throws -> Int64 {
        let deadline = clock.now + .seconds(10)
        while clock.now < deadline {
            let now = await session.world.clock.now.minute
            if now >= minutes { return now }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The game loop did not reach \(minutes) minutes within ten seconds")
        return await session.world.clock.now.minute
    }

    /// Whole 100 ms ticks in `duration`: the most a single loop can produce.
    private func wholeTicks(in duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 10 + components.attoseconds / 100_000_000_000_000_000
    }
}

