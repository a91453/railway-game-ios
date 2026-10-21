import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 305: the shortcut over a night no train runs in (research
/// §4.15). A straight track of nine columns: a depot beside column 1,
/// Alpha and Gamma beside columns 3 and 7, the line Main from Alpha to
/// Gamma, open 06:00–20:00 unless asked otherwise.
@MainActor
final class NightSkipTests: XCTestCase {
    private let track = TestLine(tiles: 9)
    private let depot = StationID(rawValue: 1)
    private let alpha = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let day = GameTime.secondsPerDay

    /// The world on day 0 at `minutes`, with one train of Main standing
    /// in the depot (or at Alpha, `withDepot` false); management, so
    /// midnight settles the books.
    private func world(
        at minutes: Int64 = 21 * 60, window: ServiceWindow = .hours(open: 360, close: 1200), withDepot: Bool = true, freight: Bool = false
    ) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 10_240, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: minutes), speed: .normal)
        )
        try track.build(in: &world)
        try track.buildStation(named: "Depot", beside: 1, at: 0, in: &world)
        try track.buildStation(named: "Alpha", beside: 3, at: 0, in: &world)
        try track.buildStation(named: "Gamma", beside: 7, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        if freight {
            world.enableFreight()
            try world.setLand([LandCell(row: 0, column: 0, use: .industrial, residents: 0, jobs: 100)])
            try world.setLineFreight(main, to: true)
        }
        // As DepotTests: a crawl, a link (1024 units) in about a minute.
        try world.setLinePerformance(main, to: TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1))
        try world.setLineServiceWindow(main, to: window)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        if withDepot {
            try world.setStationDepot(depot, to: true)
            try world.setLineDepot(main, to: depot)
        }
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: track.at(withDepot ? 1 : 3, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1024)
        try world.assignTrain(train.id, to: main)
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 400))
        try world.setStationDemand(gamma, to: StationDemand(kind: .office, dailyTrips: 400))
        world.setEconomyMode(.management)
        return world
    }

    /// Runs `session` a tick at a time while its skip runs.
    private func runSkip(_ session: GameSession, limit: Int = 2_000) -> Int {
        var ticks = 0
        while session.nightSkipRun != nil, ticks < limit {
            session.advance(ticks: 1)
            ticks += 1
        }
        return ticks
    }

    /// `world` stepped a tick at a time at its own speed until `time`.
    private func stepped(_ world: GameWorld, to time: GameTime) throws -> GameWorld {
        var world = world
        while world.clock.now < time {
            try world.advance(ticks: 1)
        }
        XCTAssertEqual(world.clock.now, time, "a minute a tick lands on the stop")
        return world
    }

    // MARK: - Where it stops

    /// With a depot the first move is the train leaving it before 06:00,
    /// and the skip stops ten minutes before that, the next morning.
    func testWithADepotItStopsBeforeTheTrainLeavesTheDepot() throws {
        let skip = try XCTUnwrap(NightSkip.plan(for: world()))
        XCTAssertLessThan(skip.firstMove.seconds, day + 6 * 3_600, "out of the depot before the first trip")
        XCTAssertGreaterThan(skip.firstMove.seconds, day + 5 * 3_600)
        XCTAssertEqual(skip.stop.seconds, skip.firstMove.seconds - NightSkip.lead)
        // Stepping minute by minute: nothing moves before the first move.
        var world = try world()
        let still = world.trains.map(\.position)
        while world.clock.now < skip.firstMove {
            XCTAssertEqual(world.trains.map(\.position), still, "moved at \(world.clock.now.clockText)")
            XCTAssertFalse(world.trains.contains(where: NightSkip.isRunning))
            try world.advance(ticks: 1)
        }
        // It moves in the minute that begins there.
        try world.advance(ticks: 1)
        XCTAssertTrue(world.trains.contains(where: NightSkip.isRunning) || world.trains.map(\.position) != still)
    }

    /// Without a depot the train waits at Alpha for the 06:00 trip.
    func testWithoutADepotItStopsBeforeTheFirstTrip() throws {
        let skip = try XCTUnwrap(NightSkip.plan(for: world(withDepot: false)))
        XCTAssertEqual(skip.firstMove.seconds, day + 6 * 3_600)
        XCTAssertEqual(skip.stop.clockText, "05:50")
    }

    /// The stop follows the line's first train, not a fixed hour.
    func testALaterFirstTrainStopsLater() throws {
        let early = try XCTUnwrap(NightSkip.plan(for: world(withDepot: false)))
        let late = try XCTUnwrap(NightSkip.plan(for: world(window: .hours(open: 480, close: 1200), withDepot: false)))
        XCTAssertEqual(late.stop.clockText, "07:50")
        XCTAssertEqual(late.stop.seconds - early.stop.seconds, 2 * 3_600)
        let withDepot = try XCTUnwrap(NightSkip.plan(for: world(window: .hours(open: 480, close: 1200))))
        XCTAssertLessThan(withDepot.stop, late.stop, "the depot's train leaves before 08:00")
        XCTAssertGreaterThan(withDepot.stop.seconds, day + 7 * 3_600)
    }

    /// A line open past midnight: from 21:00 the skip stops before its
    /// next morning, never in the night it still runs.
    func testALineRunningPastMidnightIsSkippedOnlyOnceItCloses() throws {
        var world = try world(at: 6 * 60, window: .hours(open: 360, close: 1_500), withDepot: false)
        try world.advance(ticks: 15 * 60)
        XCTAssertNil(NightSkip.plan(for: world), "the line runs until 01:00")
        var offered: GameTime?
        while world.clock.now.seconds < day + 5 * 3_600, offered == nil {
            if NightSkip.plan(for: world) != nil { offered = world.clock.now }
            try world.advance(ticks: 10)
        }
        let first = try XCTUnwrap(offered)
        XCTAssertGreaterThanOrEqual(first.seconds, day + 3_600, "not before the line closes at 01:00")
    }

    /// A line open all night keeps its train running: nothing to skip.
    func testALineOpenAllNightHasNothingToSkip() throws {
        var world = try world(at: 6 * 60, window: .allDay, withDepot: false)
        try world.advance(ticks: 20 * 60)
        for _ in 0..<16 {
            XCTAssertNil(NightSkip.plan(for: world), "at \(world.clock.now.clockText)")
            try world.advance(ticks: 30)
        }
    }

    /// After the last trip the train runs empty to the depot: no skip
    /// while it does, one once it stands there.
    func testATrainRunningToTheDepotIsWaitedFor() throws {
        var world = try world(at: 6 * 60)
        try world.advance(ticks: 13 * 60 + 50)
        var sawDeadhead = false, offered = false
        for _ in 0..<(3 * 60) {
            let running = world.trains.contains(where: NightSkip.isRunning)
            sawDeadhead = sawDeadhead || world.trains.contains(where: \.isDeadheading)
            let skip = NightSkip.plan(for: world)
            if running { XCTAssertNil(skip, "at \(world.clock.now.clockText)") }
            if skip != nil { offered = true }
            try world.advance(ticks: 1)
        }
        XCTAssertTrue(sawDeadhead, "the train ran empty to the depot")
        XCTAssertTrue(offered, "the night was offered once it stood in the depot")
        let skip = try XCTUnwrap(NightSkip.plan(for: world))
        XCTAssertEqual(skip.stop.seconds / day, 1, "the next morning")
    }

    /// A timetabled line (decision 133, as the real timetables and the
    /// High Speed Rail run): the skip stops before a late run, and before
    /// the first run of the morning after it, back from where the late
    /// one ended.
    func testATimetabledLateTrainIsNotSkippedOver() throws {
        var world = try world(at: 21 * 60, withDepot: false)
        let late = LineRun(from: 0, to: 1, times: [
            LineRunTime(arrival: 23 * 3_600, departure: 23 * 3_600), LineRunTime(arrival: 23 * 3_600 + 1_800, departure: 23 * 3_600 + 1_800),
        ])
        // Back from Gamma, where the late run ends.
        let morning = LineRun(from: 1, to: 0, times: [
            LineRunTime(arrival: 6 * 3_600, departure: 6 * 3_600), LineRunTime(arrival: 6 * 3_600 + 1_800, departure: 6 * 3_600 + 1_800),
        ])
        try world.setLineRuns(main, to: [morning, late])
        let skip = try XCTUnwrap(NightSkip.plan(for: world))
        XCTAssertLessThanOrEqual(skip.firstMove.seconds, 23 * 3_600)
        XCTAssertLessThanOrEqual(skip.stop.seconds, 23 * 3_600 - NightSkip.lead)
        try world.advance(ticks: Int((skip.firstMove.seconds - world.clock.now.seconds) / 60))
        // While the late train runs there is nothing to skip; after it,
        // the morning.
        var after: NightSkip?
        while world.clock.now.seconds < day + 3 * 3_600, after == nil {
            if world.trains.contains(where: NightSkip.isRunning) { XCTAssertNil(NightSkip.plan(for: world)) }
            after = NightSkip.plan(for: world)
            try world.advance(ticks: 1)
        }
        let next = try XCTUnwrap(after)
        XCTAssertGreaterThan(next.stop.seconds, 23 * 3_600 + 1_800)
        XCTAssertLessThanOrEqual(next.firstMove.seconds, day + 6 * 3_600)
    }

    /// A freight line running at night keeps the night from being skipped.
    func testAFreightTrainAtNightHasNothingToSkip() throws {
        var world = try world(at: 6 * 60, window: .allDay, withDepot: false, freight: true)
        try world.advance(ticks: 16 * 60)
        for _ in 0..<12 {
            XCTAssertNil(NightSkip.plan(for: world), "at \(world.clock.now.clockText)")
            try world.advance(ticks: 30)
        }
    }

    func testNoTrainNoSkip() throws {
        var world = try world()
        try world.unplaceTrain(TrainID(rawValue: 1))
        XCTAssertNil(NightSkip.plan(for: world))
    }

    /// Less than an hour (with the lead) to the first move: nothing to skip.
    func testAShortGapIsNotOffered() throws {
        XCTAssertNotNil(NightSkip.plan(for: try world(at: 4 * 60, withDepot: false)))
        XCTAssertNil(NightSkip.plan(for: try world(at: 5 * 60, withDepot: false)), "50 minutes")
        XCTAssertNil(NightSkip.plan(for: try world(at: 4 * 60 + 51, withDepot: false)))
        XCTAssertNotNil(NightSkip.plan(for: try world(at: 4 * 60 + 50, withDepot: false)), "an hour exactly")
    }

    /// Each tick of a skip is the fastest that does not pass the stop.
    func testTheSpeedLandsOnTheStop() {
        XCTAssertEqual(NightSkip.speed(remaining: 36_000), .fast)
        XCTAssertEqual(NightSkip.speed(remaining: 600), .fast)
        XCTAssertEqual(NightSkip.speed(remaining: 540), .double)
        XCTAssertEqual(NightSkip.speed(remaining: 60), .normal)
        XCTAssertEqual(NightSkip.speed(remaining: 59), .x60)
        XCTAssertEqual(NightSkip.speed(remaining: 5), .x10)
    }

    /// The UI test's world (`FeatureUITestWorld` "quiet-night", built the
    /// same way): a full-size line open 06:00–20:00, its train standing at
    /// the west end at 01:00. The skip is offered and stops before 06:00.
    func testAFullSizeLineHasANightToSkip() throws {
        let bounds = try WorldBounds(width: 40_960, height: 20_480)
        let builder = GameSession(world: GameWorld(bounds: bounds, economy: GameEconomy(balance: 100_000_000),
                                                  clock: GameClock(now: GameTime(minutes: 60), speed: .normal)))
        builder.selectTool(.network)
        builder.networkBuildsDouble = true
        builder.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        builder.tapNetwork(at: PlanPoint(x: 34_816, y: 10_240), reach: 16)
        builder.buildNetworkTrack()
        XCTAssertEqual(builder.message?.kind, .success)
        var world = builder.world
        let west = try world.buildStation(named: "海岸", at: PlanPoint(x: 6_144, y: 10_240)).id
        let east = try world.buildStation(named: "山邊", at: PlanPoint(x: 30_720, y: 10_240)).id
        for (station, x) in [(west, Int64(6_144)), (east, 30_720)] {
            let site = try XCTUnwrap(world.trackEdgePoint(near: PlanPoint(x: x, y: 10_240), within: 64))
            try world.addTrackPlatform(station, on: site.edge, from: site.distance - 2_048, to: site.distance + 2_048)
        }
        let line = try world.createLine(named: "海岸線", stops: [west, east]).id
        try world.setLineServiceWindow(line, to: .hours(open: 360, close: 1200))
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "海岸1號").id
        let site = try XCTUnwrap(world.trackEdgePoint(near: PlanPoint(x: 6_144, y: 10_240), within: 64))
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: site.edge, direction: .forward), offset: site.distance))
        try world.setTrainContinuation(train, along: [], stoppingAt: site.distance)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        let skip = try XCTUnwrap(NightSkip.plan(for: world))
        XCTAssertEqual(skip.stop.clockText, "05:50")
        XCTAssertEqual(skip.stop.seconds / day, 0, "the same morning")
    }

    // MARK: - Bit for bit

    /// The skip and a minute a tick reach the same moment with the same
    /// world, crossing midnight's books, with and without a depot, and
    /// from the speed the player ran at.
    func testSkippingMatchesSteppingBitForBit() throws {
        for (withDepot, speed) in [(true, GameSpeed.normal), (false, .normal), (true, .x60), (false, .double)] {
            var opened = try world(withDepot: withDepot)
            opened.setSpeed(speed)
            let session = GameSession(world: opened)
            // The world as the session opened it.
            let start = session.world
            let skip = try XCTUnwrap(session.nightSkip)
            session.skipToMorning()
            XCTAssertEqual(session.world.clock.speed, .fast)
            let ticks = runSkip(session)
            XCTAssertNil(session.nightSkipRun)
            XCTAssertEqual(session.world.clock.now, skip.stop)
            XCTAssertEqual(session.world.clock.speed, speed, "back at the player's speed")
            XCTAssertLessThan(ticks, 70, "about ten minutes a tick")
            var minuteByMinute = start
            minuteByMinute.setSpeed(.normal)
            minuteByMinute = try stepped(minuteByMinute, to: skip.stop)
            minuteByMinute.setSpeed(speed)
            XCTAssertEqual(session.world, minuteByMinute, "depot \(withDepot), \(speed)")
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            XCTAssertEqual(try encoder.encode(SavedGame(world: session.world)), try encoder.encode(SavedGame(world: minuteByMinute)))
            XCTAssertGreaterThan(session.world.accounts.entries.count, start.accounts.entries.count, "midnight's books ran")
        }
    }

    /// Ten more minutes after the stop, the train leaves as it would have.
    func testTheMorningGoesOnAsItWouldHave() throws {
        let start = try world()
        let session = GameSession(world: start)
        let skip = try XCTUnwrap(session.nightSkip)
        session.skipToMorning()
        _ = runSkip(session)
        session.advance(ticks: Int(NightSkip.lead / 60))
        XCTAssertEqual(session.world.clock.now, skip.firstMove)
        XCTAssertFalse(session.world.trains.contains(where: NightSkip.isRunning))
        session.advance(ticks: 1)
        XCTAssertTrue(session.world.trains.contains(where: NightSkip.isRunning) || session.world.trains[0].position != start.trains[0].position)
    }

    // MARK: - Interruptions

    /// Pausing, or choosing a speed, ends the skip; the speed is the
    /// player's.
    func testThePlayerStopsTheSkipWithASpeedOrAPause() throws {
        let session = GameSession(world: try world())
        session.skipToMorning()
        session.advance(ticks: 5)
        session.setSpeed(.x60)
        XCTAssertNil(session.nightSkipRun)
        XCTAssertEqual(session.world.clock.speed, .x60)
        session.advance(ticks: 1)
        XCTAssertEqual(session.world.clock.speed, .x60)

        let paused = GameSession(world: try world())
        paused.skipToMorning()
        paused.advance(ticks: 3)
        paused.togglePause()
        XCTAssertNil(paused.nightSkipRun)
        XCTAssertTrue(paused.world.clock.isPaused)
        XCTAssertEqual(paused.world.clock.runningSpeed, .fast, "resumes as the player left it")

        let stopped = GameSession(world: try world())
        stopped.skipToMorning()
        stopped.advance(ticks: 3)
        stopped.stopNightSkip()
        XCTAssertNil(stopped.nightSkipRun)
        XCTAssertEqual(stopped.world.clock.speed, .normal, "Stop goes back to the speed before")
    }

    /// A skip pressed while paused runs, and is paused again at its stop.
    func testASkipFromAPauseEndsPaused() throws {
        var start = try world()
        start.setSpeed(.x60)
        start.pause()
        let session = GameSession(world: start)
        let skip = try XCTUnwrap(session.nightSkip)
        session.skipToMorning()
        XCTAssertFalse(session.world.clock.isPaused)
        _ = runSkip(session)
        XCTAssertEqual(session.world.clock.now, skip.stop)
        XCTAssertTrue(session.world.clock.isPaused)
        XCTAssertEqual(session.world.clock.runningSpeed, .x60)
    }

    /// A command during the skip ends it at the next tick, back at the
    /// player's speed.
    func testACommandEndsTheSkip() throws {
        let session = GameSession(world: try world())
        session.skipToMorning()
        session.advance(ticks: 3)
        session.setTrafficControl(true)
        session.advance(ticks: 1)
        XCTAssertNil(session.nightSkipRun)
        XCTAssertEqual(session.world.clock.speed, .normal)
    }

    /// A typhoon warning at midnight pauses the game (decision 175): the
    /// skip ends there, paused at the player's speed; without the pause
    /// setting the skip runs through.
    func testATyphoonWarningStopsTheSkip() throws {
        var found: (seed: UInt32, typhoon: Typhoon)?
        let probe = try world()
        let alphaPoint = try XCTUnwrap(probe.station(id: alpha)).point
        // The seed whose typhoon over Alpha is announced soonest.
        for seed in UInt32(1)...400 {
            let disruptions = try XCTUnwrap(Disruptions(level: .standard, country: "TW", seed: seed))
            if let typhoon = disruptions.typhoons(ofYear: 0, in: probe.bounds).first(where: { $0.covers(alphaPoint) && $0.announced >= 2 }),
               typhoon.announced < found?.typhoon.announced ?? .max {
                found = (seed, typhoon)
            }
        }
        let (seed, typhoon) = try XCTUnwrap(found, "no seed in 1...400 puts a typhoon over Alpha")
        for pauses in [true, false] {
            var start = try world(at: 6 * 60)
            start.setDisruptions(Disruptions(level: .standard, country: "TW", seed: seed))
            // To 21:00 on the day before the warning, ten minutes a tick.
            start.setSpeed(.fast)
            try start.advance(ticks: Int((typhoon.announced - 1) * day / 600 + 90))
            start.setSpeed(.normal)
            let session = GameSession(world: start)
            session.pausesForImportantEvents = pauses
            let skip = try XCTUnwrap(session.nightSkip, "a quiet night before the warning")
            session.skipToMorning()
            _ = runSkip(session)
            XCTAssertNil(session.nightSkipRun)
            if pauses {
                XCTAssertTrue(session.world.clock.isPaused)
                XCTAssertTrue(session.isPausedForEvent)
                XCTAssertEqual(session.world.clock.runningSpeed, .normal)
                XCTAssertLessThan(session.world.clock.now.seconds, typhoon.announced * day + 3_600, "stopped at midnight")
            } else {
                XCTAssertEqual(session.world.clock.now, skip.stop)
                XCTAssertFalse(session.world.clock.isPaused)
            }
        }
    }

    // MARK: - The setting

    /// Off by default; on, a quiet night is skipped by itself, once: a
    /// skip the player stopped is not started again.
    func testTheSettingSkipsByItselfOnlyWhenOn() throws {
        let off = GameSession(world: try world())
        XCTAssertFalse(off.skipsQuietNights)
        off.advance(ticks: 1)
        XCTAssertNil(off.nightSkipRun)

        let on = GameSession(world: try world())
        on.skipsQuietNights = true
        on.advance(ticks: 1)
        let run = try XCTUnwrap(on.nightSkipRun)
        on.advance(ticks: 2)
        on.setSpeed(.normal)
        on.advance(ticks: 5)
        XCTAssertNil(on.nightSkipRun, "stopped by the player, not started again")

        // The same code as the shortcut: the same world at the stop.
        let manual = GameSession(world: try world())
        manual.advance(ticks: 1)
        manual.skipToMorning()
        _ = runSkip(manual)
        let auto = GameSession(world: try world())
        auto.skipsQuietNights = true
        auto.advance(ticks: 1)
        _ = runSkip(auto)
        XCTAssertEqual(run.stop, auto.world.clock.now)
        XCTAssertEqual(auto.world, manual.world)
    }

    /// Nothing to skip, nothing done.
    func testTheShortcutDoesNothingWithoutANightToSkip() throws {
        let session = GameSession(world: try world(at: 6 * 60, window: .allDay, withDepot: false))
        session.advance(ticks: 60)
        let before = session.world
        XCTAssertNil(session.nightSkip)
        session.skipToMorning()
        XCTAssertNil(session.nightSkipRun)
        XCTAssertEqual(session.world, before)
    }

    /// What the shortcut shows is ``GameSession/nightSkip`` after each
    /// tick, and after a command while paused, and stays the same value
    /// from tick to tick while the night lasts.
    func testTheOfferFollowsTheSkip() throws {
        let session = GameSession(world: try world())
        let skip = try XCTUnwrap(session.nightSkip)
        XCTAssertEqual(session.nightSkipOffer, skip, "a new session shows it at once")
        session.advance(ticks: 30)
        XCTAssertEqual(session.nightSkipOffer, session.nightSkip)
        XCTAssertEqual(session.nightSkipOffer?.stop, skip.stop, "the same stop while the night lasts")
        session.skipToMorning()
        _ = runSkip(session)
        XCTAssertNil(session.nightSkipOffer, "nothing left to skip at the stop")

        let paused = GameSession(world: try world())
        paused.togglePause()
        XCTAssertNotNil(paused.nightSkipOffer)
        paused.setSelectedLineAllDay(true)
        XCTAssertNil(paused.nightSkip, "the line now runs all night")
        XCTAssertNil(paused.nightSkipOffer, "a command while paused is looked at at once")
    }

    /// Decision 328: the game loop's tick runs ahead off the main actor,
    /// and the session takes what it found instead of running ahead
    /// again; a tick the memo still answers for does not run ahead.
    func testTheGameLoopRunsAheadOffTheMainActor() async throws {
        let session = GameSession(world: try world())
        let expected = try XCTUnwrap(session.nightSkip)
        session.nightSkipMemo = nil
        let tick = try XCTUnwrap(session.beginLoopTick())
        let outcome = await tick.work()
        let found = try XCTUnwrap(try outcome.get().nightSkip, "every train at rest and no memo: the tick runs ahead")
        XCTAssertTrue(session.finish(tick, with: outcome))
        let memo = try XCTUnwrap(session.nightSkipMemo)
        XCTAssertEqual(memo.from, found.from)
        XCTAssertEqual(memo.firstMove, found.firstMove)
        XCTAssertEqual(memo.from, session.world.clock.now)
        XCTAssertEqual(session.nightSkipOffer?.stop, expected.stop)
        XCTAssertEqual(session.nightSkipOffer, NightSkip.plan(for: session.world), "as the main actor would have found it")

        let next = try XCTUnwrap(session.beginLoopTick())
        let again = try await next.work().get()
        XCTAssertNil(again.nightSkip, "the memo still answers")
    }

    /// A train about to leave makes the first move the moment the memo was
    /// worked out: the main actor uses the tick's answer for that moment
    /// instead of running ahead again (decision 328).
    func testAMemoAnswersTheMomentItWasWorkedOut() {
        let now = GameTime(seconds: 63_072_072)
        let memo = NightSkipMemo(revision: 3, from: now, firstMove: now)
        XCTAssertTrue(memo.covers(now, revision: 3))
        XCTAssertFalse(memo.covers(GameTime(seconds: now.seconds + 6), revision: 3))
        XCTAssertFalse(memo.covers(now, revision: 4))
        XCTAssertFalse(memo.covers(GameTime(seconds: now.seconds - 6), revision: 3))
    }

    // MARK: - Text

    func testTheTextSaysWhatItDoesInBothLanguages() throws {
        let skip = try XCTUnwrap(NightSkip.plan(for: world(withDepot: false)))
        XCTAssertEqual(skip.buttonTitle(in: .english), "Skip to Morning · 05:50")
        XCTAssertEqual(skip.buttonTitle(in: .traditionalChinese), "快轉到早上 · 05:50")
        XCTAssertEqual(NightSkip.stopTitle(at: skip.stop, in: .traditionalChinese), "快轉到 05:50 · 停止")
        XCTAssertEqual(NightSkip.settingTitle(in: .traditionalChinese), "夜裡沒有車時自動快轉")
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertFalse(NightSkip.hint(in: language).isEmpty)
            XCTAssertFalse(NightSkip.settingFooter(in: language).isEmpty)
        }
    }
}
