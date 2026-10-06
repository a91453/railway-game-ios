import GameCore
import GamePresentation
import XCTest

/// Stage C3: choosing how trains and lines run (Stage W2c), the journeys
/// that gives a line, and the run a train follows, in words. Session
/// commands are compared with the same commands applied to GameCore
/// directly; expected text is written out by hand.
final class PerformanceSessionTests: XCTestCase {
    private static let crawl = TrainPerformance(acceleration: 250, braking: 250, topSpeed: 1)
    private static let main = LineID(rawValue: 1)
    private static let tram = TrainID(rawValue: 1)

    /// Alpha (1, 0), Beta (3, 0), Gamma (5, 0), Delta (7, 0) above a
    /// straight line of the track network along y = 1, two edges apart
    /// (see `TestLine`); line Main calls at all four, as in
    /// `LineSessionTests`.
    private func makeLineWorld() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 9_216, height: 2_048), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 480), speed: .normal)
        )
        let line = TestLine(tiles: 9, row: 1)
        try line.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            stops.append(try line.buildStation(named: name, beside: x, at: 0, in: &world))
        }
        try world.createLine(named: "Main", stops: stops)
        return world
    }

    // MARK: - Presets and text

    func testThePresetsAreTheReferencesTrainsByName() {
        XCTAssertEqual(PerformancePreset.allCases.count, 14)
        XCTAssertEqual(PerformancePreset.metro.performance, .metro)
        XCTAssertEqual(PerformancePreset.taroko.performance, .tiltingTaroko)
        XCTAssertEqual(
            PerformancePreset.allCases.map { $0.title(in: .traditionalChinese) },
            ["標準", "捷運", "區間車", "普通車", "莒光／復興", "自強", "EMU3000", "推拉式自強", "太魯閣", "普悠瑪", "柴聯自強", "DR1000", "阿里山林鐵", "高鐵"]
        )
        XCTAssertEqual(PerformancePreset.designSpeeds, [60, 80, 90, 100, 120, 140, 150, 160, 180, 200])
        // A design speed changes only the top speed: still the metro.
        XCTAssertEqual(PerformancePreset(matching: TrainPerformance.metro.withTopSpeed(120)), .metro)
        XCTAssertEqual(TrainPerformance.metro.withTopSpeed(120).topSpeed, 120)
        XCTAssertEqual(TrainPerformance.metro.withTopSpeed(120).acceleration, 3_960)
        XCTAssertNil(PerformancePreset(matching: Self.crawl))
        // The DR1000 and diesel expresses run alike: the first is named.
        XCTAssertEqual(PerformancePreset(matching: .dieselRailcar), .dieselExpress)
    }

    func testAPerformanceReadsAsItsNameSpeedAndRates() {
        XCTAssertEqual(TrainPerformance.local.displayText(in: .english), "Local EMU · 120 km/h · 2.5 / 3 km/h/s")
        XCTAssertEqual(TrainPerformance.metro.displayText(in: .english), "Metro · 80 km/h · 3.96 / 4.68 km/h/s")
        XCTAssertEqual(TrainPerformance.highSpeed.displayText(in: .traditionalChinese), "高鐵 · 300 km/h · 1.4 / 1.5 km/h/s")
        XCTAssertEqual(Self.crawl.displayText(in: .english), "Custom · 1 km/h · 0.25 / 0.25 km/h/s")
        XCTAssertEqual(Self.crawl.displayText(in: .traditionalChinese), "自訂 · 1 km/h · 0.25 / 0.25 km/h/s")
        XCTAssertEqual(durationText(seconds: 16, in: .english), "16 s")
        XCTAssertEqual(durationText(seconds: 420, in: .english), "7 min")
        XCTAssertEqual(durationText(seconds: 424, in: .english), "7 min 4 s")
        XCTAssertEqual(durationText(seconds: 424, in: .traditionalChinese), "7 分 4 秒")
    }

    // MARK: - Lines

    func testDisplayedSpeedFollowsTheServiceCurveRatherThanTheManualRate() throws {
        var world = try makeLineWorld()
        let track = TestLine(tiles: 9, row: 1)
        let id = try world.purchaseTrain(named: "Physical speed").id
        try world.placeTrain(id, at: track.at(1, facingEast: true))
        try world.useTrainPerformanceForMovement(id)
        let start = world.clock.now.seconds
        try world.setTrainTimetable(id, to: [
            .init(station: StationID(rawValue: 1), arrival: GameTime(seconds: start), departure: GameTime(seconds: start + 60)),
            .init(station: StationID(rawValue: 2), arrival: GameTime(seconds: start + 80), departure: GameTime(seconds: start + 80)),
        ])
        try world.startTrainService(id)
        world.setSpeed(.x1)
        XCTAssertEqual(world.trainSpeedText(of: id), "0.0 km/h")
        XCTAssertEqual(world.trainPathStatusText(of: id, in: .traditionalChinese), "等候發車")
        try world.advance(ticks: 610)
        XCTAssertEqual(world.trainSpeedText(of: id), "1.5 km/h")
        try world.advance(ticks: 10)
        XCTAssertEqual(world.trainSpeedText(of: id), "3.0 km/h")
        XCTAssertLessThan(world.trainSpeedKMH(of: id), 110, "The top speed is not its instantaneous speed")
        try world.advance(ticks: 180)
        XCTAssertEqual(world.trainSpeedText(of: id), "0.0 km/h")
    }

    /// Two edges between stops: 16 s at the standard performance
    /// (√(2 × 2048 × 0.06) = 15.7), 120 s at a 1 km/h crawl; the rest of a
    /// round trip, 480 s, is the stops. On the track network (Stage F3c)
    /// the journey starts from Alpha's berth that makes the round trip
    /// shortest, the end of its platform east of the node, so the first leg
    /// is 512 shorter (as GameCore's `ServiceLineTests`, F3b-1): 14 s, and
    /// 91 s at the crawl.
    func testALinesPerformanceSetsItsJourney() async throws {
        let world = try makeLineWorld()
        var expected = world
        try expected.setLinePerformance(Self.main, to: Self.crawl)
        XCTAssertEqual(
            world.lineJourneyText(Self.main, in: .english),
            "Round trip 9 min 34 s · legs 14 s, 16 s, 16 s, 16 s, 16 s, 16 s"
        )
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.setSelectedLinePerformance(Self.crawl)
            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Main plans its journeys as Custom · 1 km/h · 0.25 / 0.25 km/h/s."))
            XCTAssertEqual(
                session.world.lineJourneyText(Self.main, in: .english),
                "Round trip 19 min 31 s · legs 1 min 31 s, 2 min, 2 min, 2 min, 2 min, 2 min"
            )
            XCTAssertEqual(
                session.world.lineJourneyText(Self.main, in: .traditionalChinese),
                "來回 19 分 31 秒 · 各段 1 分 31 秒、2 分、2 分、2 分、2 分、2 分"
            )
            session.setSelectedLinePerformance(TrainPerformance(acceleration: 0, braking: 1, topSpeed: 1))
            XCTAssertEqual(session.world, expected, "an invalid performance changes nothing")
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.invalidTrainPerformance.playerMessage(in: .english)))
        }
    }

    // MARK: - Trains

    /// A train's performance is set whether or not it is placed, but not
    /// while it runs a service; once it runs, the panel shows the run it
    /// follows.
    func testATrainsPerformanceAndTheRunItFollows() async throws {
        var world = try makeLineWorld()
        try world.setLinePerformance(Self.main, to: Self.crawl)
        try world.setLineTrainsInService(Self.main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.purchaseTrain(named: "Tram")
        var expected = world
        try expected.setTrainPerformance(Self.tram, to: Self.crawl)
        await MainActor.run { [world, expected] in
            let session = GameSession(world: world)
            session.selectTrain(Self.tram)
            session.setSelectedTrainPerformance(Self.crawl)
            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Tram now runs as Custom · 1 km/h · 0.25 / 0.25 km/h/s."))
            XCTAssertNil(session.world.trainRunText(of: Self.tram, in: .english), "not on a run")
        }

        // Placed at Alpha facing east, given a rate and sent out by the
        // line at 08:00, it leaves at 08:00:42 for Beta, two edges (32 m)
        // in 120 s.
        try expected.placeTrain(Self.tram, at: TestLine(tiles: 9, row: 1).at(1, facingEast: true))
        try expected.setTrainMovementRate(Self.tram, to: 128)
        try expected.assignTrain(Self.tram, to: Self.main)
        try expected.advance(ticks: 1)
        while expected.train(id: Self.tram)?.times?.run == nil {
            try expected.advance(ticks: 1)
        }
        let run = try XCTUnwrap(expected.train(id: Self.tram)?.times?.run)
        XCTAssertEqual(run, ServiceRun(start: GameTime(seconds: 480 * 60 + 42), length: 2_048, seconds: 120))
        XCTAssertEqual(expected.trainRunText(of: Self.tram, in: .english), "Running 2 min over 32 m, due Day 1 · 08:02:42")
        XCTAssertEqual(expected.trainRunText(of: Self.tram, in: .traditionalChinese), "行駛 2 分、32 公尺，預計 第 1 日 · 08:02:42 到")
        await MainActor.run { [expected] in
            let session = GameSession(world: expected)
            session.selectTrain(Self.tram)
            session.setSelectedTrainPerformance(.metro)
            XCTAssertEqual(session.world, expected, "not while it runs a service")
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.trainServiceActive(Self.tram).playerMessage(in: .english)))
        }
    }
}
