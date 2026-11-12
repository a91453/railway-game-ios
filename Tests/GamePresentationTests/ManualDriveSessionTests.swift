@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 686: a hand-driven run as a session keeps it, on the world's
/// track: the world's train is never touched.
@MainActor
final class ManualDriveSessionTests: XCTestCase {
    /// Station A, 1 km east, a 300 m quarter circle (75 km/h), 1 km north,
    /// station B; one standard train on the line A–B (as
    /// `CurveSpeedTextTests`).
    private func world(limits: Bool) throws -> (GameWorld, TrainID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500))
        )
        let r: Int64 = 300 * 64, k = r * 5523 / 10_000, x: Int64 = 8_192, y: Int64 = 8_192
        let points = [
            WorldCoordinate(x: x, y: y), WorldCoordinate(x: x + 4_096, y: y), WorldCoordinate(x: x + 68_096, y: y),
            WorldCoordinate(x: x + 68_096 + r, y: y + r), WorldCoordinate(x: x + 68_096 + r, y: y + r + 64_000),
            WorldCoordinate(x: x + 68_096 + r, y: y + r + 68_096),
        ]
        let nodes = try points.map { try world.buildTrackNode(at: $0) }
        let first = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        _ = try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        _ = try world.buildTrackEdge(from: nodes[2], to: nodes[3], curve: .cubic(
            PlanPoint(x: points[2].x + k, y: points[2].y), PlanPoint(x: points[3].x, y: points[3].y - k)))
        _ = try world.buildTrackEdge(from: nodes[3], to: nodes[4])
        let last = try world.buildTrackEdge(from: nodes[4], to: nodes[5])
        let a = try world.buildStation(named: "A", at: PlanPoint(x: x + 2_048, y: y + 512)).id
        try world.addTrackPlatform(a, on: first, from: 0, to: 4_096)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: points[4].x + 512, y: points[4].y + 2_048)).id
        try world.addTrackPlatform(b, on: last, from: 0, to: 4_096)
        try world.createLine(named: "Main", stops: [a, b])
        let line = LineID(rawValue: 1)
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        world.setRealisticOperation(true)
        world.setCurveSpeedLimits(limits)
        let train = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 4_096))
        try world.setTrainMovementRate(train, to: 1024)
        try world.assignTrain(train, to: line)
        world.setSpeed(.normal)
        return (world, train)
    }

    /// A session following the train at 1×, the 3D map open.
    private func makeSession(limits: Bool = true, managed: Bool = false) throws -> (GameSession, TrainID) {
        var (world, train) = try world(limits: limits)
        if managed { world.setEconomyMode(.management) }
        world.setSpeed(.x1)
        let session = GameSession(world: world)
        session.setMap3DOpen(true)
        session.followTrain(train)
        return (session, train)
    }

    /// Ticks the game a tenth of a second at a time, stepping the run at
    /// each, until `done`; whether it came.
    private func run(_ session: GameSession, from time: inout Double, ticks: Int = 6_000, until done: () -> Bool) -> Bool {
        for _ in 0..<ticks {
            if done() { return true }
            session.advance(realElapsed: GameSession.tickInterval)
            time += 0.1
            session.stepManualDrive(at: time)
        }
        return done()
    }

    private func head(of train: TrainID, in world: GameWorld) throws -> WorldCoordinate {
        try XCTUnwrap(world.train(id: train)?.position.flatMap { world.location(of: $0) }).position
    }

    func testOnlyATrainOnATimetableCanBeDriven() throws {
        let (session, train) = try makeSession()
        XCTAssertTrue(session.canManualDrive)
        XCTAssertFalse(session.world.canManualDrive(TrainID(rawValue: 99)))
        session.stopFollowingTrain()
        XCTAssertFalse(session.canManualDrive)
        session.startManualDrive()
        XCTAssertNil(session.manualDriveReading, "nothing to drive")
        _ = train
    }

    func testTheRunWaitsForTheTrainToLeaveThenIsDrivenToTheStopWithoutTouchingTheWorld() throws {
        let (session, train) = try makeSession()
        let (plain, _) = try makeSession()
        session.startManualDrive()
        XCTAssertEqual(session.manualDriveReading, .waiting)
        XCTAssertNil(session.stepManualDrive(at: 0))
        var time = 0.0, other = 0.0
        XCTAssertTrue(run(session, from: &time) { session.manualDriveReading?.phase == .driving }, "taken over as it left A")
        let taken = try XCTUnwrap(session.manualDriveRun?.driving)
        let hud = try XCTUnwrap(session.world.map3DDriverHUD(of: train, in: .english))
        XCTAssertEqual(taken.track.stopMetres, Double(try XCTUnwrap(hud.metresToNext)), accuracy: 3, "the stop the display names")
        XCTAssertEqual(taken.drive.course.limits.map { Int(($0.speed * 3.6).rounded()) }, [75], "the curve's limit is on the way")
        XCTAssertEqual(taken.drive.speed, session.world.trainSpeedKMH(of: train) / 3.6, accuracy: 1e-9)
        let scheduled = taken.drive.course.scheduled
        XCTAssertGreaterThan(scheduled, 60)

        // Drawn where the world's train is at the take-over.
        let at = try head(of: train, in: session.world)
        let motion = TrainMotion(world: session.world, time: time)
        let drawn = try XCTUnwrap(motion.driving(on: taken.track, metres: 0).head(of: train, at: time))
        XCTAssertEqual(drawn.x, Double(at.x), accuracy: 1)
        XCTAssertEqual(drawn.y, Double(at.y), accuracy: 1)

        // Full power, never braked: the player's train runs away from the
        // timetable's and past the stop.
        session.moveManualDriveNotch(up: true)
        XCTAssertEqual(session.manualDriveReading?.notch.mark, "P1")
        session.setManualDriveNotch(.fullPower)
        _ = run(plain, from: &other, ticks: Int(time * 10)) { false }
        XCTAssertTrue(run(session, from: &time) {
            if session.manualDriveReading?.phase == .driving { _ = run(plain, from: &other, ticks: 1) { false } }
            return session.manualDriveReading?.phase == .over
        })
        XCTAssertEqual(session.manualDriveReading?.result?.outcome, .passed)
        // Decision 693: the run is settled once, as a logged command; one
        // that ran past earns nothing and is still counted.
        let settled = try XCTUnwrap(session.manualDriveSettlement)
        XCTAssertEqual(settled.bonus, .zero)
        XCTAssertEqual(settled.record.runs, 1)
        XCTAssertEqual(settled.record.arrivals, 0)
        XCTAssertEqual(session.world.driving, settled.record)
        let logged = session.commandLog.entries.filter {
            if case .command(.edit(.settleDrivenRun(let run))) = $0.action { return run.train == train && run.outcome == .passed && !$0.refused }
            return false
        }
        XCTAssertEqual(logged.count, 1)
        let shown = try XCTUnwrap(session.stepManualDrive(at: time), "it stays where it ended until the player lets go")
        XCTAssertGreaterThan(shown.metres, taken.track.stopMetres + ManualDrive.overrunMetres)
        XCTAssertEqual(shown.length, Double(try XCTUnwrap(session.world.train(id: train)).length))
        // The world ran exactly as one nobody drove in.
        XCTAssertEqual(session.world.clock.now, plain.world.clock.now)
        XCTAssertEqual(try head(of: train, in: session.world), try head(of: train, in: plain.world))
        XCTAssertEqual(session.world.train(id: train)?.execution, plain.world.train(id: train)?.execution)

        // The stopping point on the track read is where the world's train
        // stands at B.
        XCTAssertTrue(run(session, from: &time) {
            if case .waitingAtStop(let stop, _)? = session.world.train(id: train)?.execution { return stop == 1 }
            return false
        })
        let stood = try head(of: train, in: session.world)
        let stopHead = try XCTUnwrap(motion.driving(on: taken.track, metres: taken.track.stopMetres).head(of: train, at: time))
        XCTAssertEqual(stopHead.x, Double(stood.x), accuracy: 64, "within a metre")
        XCTAssertEqual(stopHead.y, Double(stood.y), accuracy: 64)
        // Its heights are read from the track under it there.
        let body = taken.track.body(metres: taken.track.stopMetres, length: shown.length)
        XCTAssertGreaterThan(body.count, 2)
        XCTAssertTrue(body.contains { abs($0.x - stood.x) <= 128 && abs($0.y - stood.y) <= 128 })
        let heights = Map3DTrains.Heights(world: session.world).driving(on: taken.track, metres: taken.track.stopMetres, length: shown.length)
        XCTAssertEqual(heights.height(of: train, x: Double(stood.x), y: Double(stood.y)), Double(stood.z))

        XCTAssertEqual(session.world.driving?.runs, 1, "stepping the ended run on settles nothing more")
        session.endManualDrive()
        XCTAssertNil(session.manualDriveReading)
        XCTAssertNil(session.manualDriveSettlement)
        XCTAssertEqual(session.world.driving?.runs, 1, "the record stays")
        XCTAssertNil(session.stepManualDrive(at: time))
    }

    /// Decision 693: a good run earns a managed company money, the card
    /// says so, and the logged game replays to the same world.
    func testAGoodRunEarnsAManagedCompanyMoneyAndTheCardSaysSo() throws {
        let (session, train) = try makeSession(managed: true)
        session.startManualDrive()
        var time = 0.0
        XCTAssertTrue(run(session, from: &time) { session.manualDrivePhase == .driving })
        let before = session.world.economy.balance
        session.finishManualDriveForScreenshot()
        let result = try XCTUnwrap(session.manualDriveReading?.result)
        let settled = try XCTUnwrap(session.manualDriveSettlement)
        XCTAssertEqual(settled.marks.total, result.total, "the card's marks are the world's")
        XCTAssertTrue(settled.keepsAccounts)
        XCTAssertTrue(settled.isBest)
        XCTAssertEqual(settled.bonus, DrivenRun.bonus(marks: result.total, riders: session.world.riderCount(of: train)))
        XCTAssertGreaterThan(settled.bonus, .zero)
        XCTAssertEqual(session.world.economy.balance, before + settled.bonus)
        XCTAssertEqual(session.world.driving?.earned, settled.bonus)
        let zh = result.text(in: .traditionalChinese, settled: settled).lines
        XCTAssertEqual(zh.count, 3)
        XCTAssertTrue(zh[2].contains("替公司多賺"), zh[2])
        XCTAssertFalse(zh[2].contains("新紀錄"), "the first arrival is no record beaten")
        let en = result.text(in: .english, settled: settled).lines
        XCTAssertTrue(en[2].hasPrefix("Earned the company NT$"), en[2])
        // Shown again and again, it is settled once.
        session.finishManualDriveForScreenshot()
        session.stepManualDrive(at: time + 1)
        XCTAssertEqual(session.world.driving?.runs, 1)

        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.5.0", build: "57", data: [:]).encoded()
        )
        XCTAssertNil(try CommandLogReplay(report).stopped?.reason, "the settlement replays")
    }

    /// Decision 690: the driving card names the way and, once the run is
    /// taken over, the stop driven to; it keeps that stop while the
    /// world's train runs on, stands there and turns back.
    func testTheHeadingNamesTheWayAndKeepsTheStopTheRunIsDrivenTo() throws {
        let (session, train) = try makeSession()
        XCTAssertNil(session.manualDriveHeading)
        session.startManualDrive()
        let waiting = try XCTUnwrap(session.manualDriveHeading)
        XCTAssertEqual(waiting.line, LineID(rawValue: 1))
        XCTAssertEqual(waiting.route, "Main", "before its first run it has only its line to name")
        XCTAssertNil(waiting.stop, "it stands at A: no stop to drive to yet")
        var time = 0.0
        XCTAssertTrue(run(session, from: &time) { session.manualDriveReading?.phase == .driving })
        XCTAssertEqual(session.manualDriveHeading?.stop, "B")
        XCTAssertEqual(session.manualDriveHeading?.route, "A → B")
        // The world's train reaches B and waits there; the card still says B.
        XCTAssertTrue(run(session, from: &time) {
            if case .waitingAtStop(let stop, _)? = session.world.train(id: train)?.execution { return stop == 1 }
            return false
        })
        XCTAssertEqual(session.manualDriveHeading?.stop, "B")
        session.endManualDrive()
        XCTAssertNil(session.manualDriveHeading)
    }

    func testTheDrawnTrainMovesAsThePlayerDrivesAndItsBodyLiesBehindItOnTheTrack() throws {
        let (session, train) = try makeSession(limits: false)
        session.startManualDrive()
        var time = 0.0
        XCTAssertTrue(run(session, from: &time) { session.manualDriveReading?.phase == .driving })
        let taken = try XCTUnwrap(session.manualDriveRun?.driving)
        let motion = TrainMotion(world: session.world, time: time)
        let run = try XCTUnwrap(motion.driving(on: taken.track, metres: 500).runs.first { $0.train == train })
        XCTAssertEqual(run.lag, 0, "it stands where it is driven: no glide of the world's")
        let head = try XCTUnwrap(run.head(at: 1))
        // 500 m east of A's platform end, on the straight.
        XCTAssertEqual(head.point.x, Double(8_192 + 4_096 + 500 * 64), accuracy: 96)
        XCTAssertEqual(head.heading.x, 1, accuracy: 1e-6)
        let body = run.body(at: 1)
        XCTAssertEqual(try XCTUnwrap(body.last).x, head.point.x - run.length, accuracy: 1, "its tail a train's length behind")
        XCTAssertNotNil(run.steadyHead(at: 1, over: Map3DTrains.steadySpan))
        XCTAssertFalse(run.ahead.isEmpty, "and track ahead for its first car's front half")
        // Another train's glide is left as it is.
        XCTAssertEqual(motion.driving(on: taken.track, metres: 500).runs.count, motion.runs.count)
    }

    /// Decision 710: the mark stands on the track where the head stops,
    /// and the frame's step says how far into the run that is.
    func testTheStoppingPointsMarkStandsOnTheTrackWhereTheHeadStops() throws {
        let (session, train) = try makeSession(limits: false)
        session.startManualDrive()
        var time = 0.0
        XCTAssertTrue(run(session, from: &time) { session.manualDriveReading?.phase == .driving })
        let taken = try XCTUnwrap(session.manualDriveRun?.driving)
        let shown = try XCTUnwrap(session.stepManualDrive(at: time))
        XCTAssertEqual(shown.stop, taken.drive.course.stop)
        XCTAssertEqual(shown.stop, taken.track.stopMetres)
        // Where the train's head is drawn when it stands on the point.
        let stop = try XCTUnwrap(taken.track.place(metres: shown.stop))
        let motion = TrainMotion(world: session.world, time: time)
        let run = try XCTUnwrap(motion.driving(on: taken.track, metres: shown.stop).runs.first { $0.train == train })
        let head = try XCTUnwrap(run.head(at: 1))
        XCTAssertEqual(Double(stop.coordinate.x), head.point.x, accuracy: 1)
        XCTAssertEqual(Double(stop.coordinate.y), head.point.y, accuracy: 1)
        XCTAssertEqual(stop.direction.x, head.heading.x, accuracy: 1e-6)
        XCTAssertEqual(stop.direction.y, head.heading.y, accuracy: 1e-6)
        let start = try XCTUnwrap(taken.track.place(metres: 0))
        XCTAssertNotEqual(start.coordinate, stop.coordinate)
    }

    /// Decision 710: the screenshot review's looks at the stopping bar:
    /// the train standing short of its own stopping point, on it, past it.
    func testTheScreenshotReviewStandsTheTrainNearItsOwnStoppingPoint() throws {
        let (session, _) = try makeSession(limits: false)
        session.startManualDrive()
        var time = 0.0
        XCTAssertTrue(run(session, from: &time) { session.manualDriveReading?.phase == .driving })
        let stop = try XCTUnwrap(session.manualDriveRun?.driving).drive.course.stop
        for (metres, state) in [(12.0, ManualDrive.StopBar.State.short), (0.2, .onTarget), (-3, .past)] {
            session.nearStopForScreenshot(standing: metres)
            XCTAssertEqual(session.manualDriveReading?.stopBar?.state, state)
            time += 1
            let shown = try XCTUnwrap(session.stepManualDrive(at: time))
            XCTAssertEqual(shown.metres, stop - metres, accuracy: 1e-6, "it stands there")
            XCTAssertEqual(shown.stop, stop, "the mark where it was")
            XCTAssertEqual(session.manualDriveReading?.phase, .driving, "and the run goes on")
        }
        session.finishManualDriveForScreenshot()
        let shown = try XCTUnwrap(session.stepManualDrive(at: time + 1))
        XCTAssertEqual(shown.metres, stop, accuracy: 1, "the result is looked at where the train would stand")
        XCTAssertEqual(session.manualDriveReading?.result?.outcome, .stopped)
        XCTAssertNil(session.manualDriveReading?.stopBar)
    }

    /// Decision 710: the stopping assist is the run's from the start, and
    /// turned on or off while it is driven.
    func testTheStoppingAssistIsOnForTheRunItWasStartedWithAndCanBeTurnedOff() throws {
        let (session, _) = try makeSession(limits: false)
        session.startManualDrive(assist: true)
        XCTAssertEqual(session.manualDriveRun?.assists, true, "kept while the train waits at its stop")
        var time = 0.0
        XCTAssertTrue(run(session, from: &time) { session.manualDriveReading?.phase == .driving })
        XCTAssertEqual(session.manualDriveRun?.driving?.drive.assists, true)
        session.setManualDriveAssist(false)
        XCTAssertEqual(session.manualDriveRun?.driving?.drive.assists, false)
        XCTAssertEqual(session.manualDriveRun?.assists, false)
        session.endManualDrive()
        session.startManualDrive()
        XCTAssertEqual(session.manualDriveRun?.assists, false, "off unless asked for")
    }

    func testStartingSlowsTheGameToOneTimesAndLettingGoOfTheTrainEndsTheRun() throws {
        let (session, _) = try makeSession()
        session.setSpeed(.x10)
        session.startManualDrive()
        XCTAssertEqual(session.world.clock.speed, .x1)
        XCTAssertNotNil(session.manualDriveReading)
        session.stopFollowingTrain()
        XCTAssertNil(session.manualDriveReading)
        XCTAssertNil(session.manualDriveRun)
    }

    /// Review L17-5: a game paused at 10× resumed at 10× under the
    /// player's hands, and the speed menu still set 10× while driving.
    /// Paused, it stays paused and resumes at 1×; while driving the menu
    /// stops at 1× and a faster speed asked is 1×; the handle given back,
    /// the 3D map's own limit is the menu's again.
    func testAPausedGameResumesAtOneTimesAndTheSpeedStaysThereWhileDriving() throws {
        let (session, _) = try makeSession()
        session.setSpeed(.x10)
        XCTAssertEqual(session.speedCap, .x10)
        session.togglePause()
        XCTAssertTrue(session.world.clock.isPaused)
        session.startManualDrive()
        XCTAssertTrue(session.world.clock.isPaused, "starting does not resume it")
        XCTAssertEqual(session.world.clock.runningSpeed, .x1)
        session.togglePause()
        XCTAssertFalse(session.world.clock.isPaused)
        XCTAssertEqual(session.world.clock.speed, .x1)

        XCTAssertEqual(session.speedCap, .x1)
        XCTAssertEqual(session.speedChoices, [.x1])
        session.setSpeed(.x10)
        XCTAssertEqual(session.world.clock.speed, .x1)
        session.setSpeed(.fast)
        XCTAssertEqual(session.world.clock.speed, .x1)
        XCTAssertEqual(Map3DFollowSpeed.limitText(upTo: .x1, in: .english), "1× while you drive the train")
        XCTAssertEqual(Map3DFollowSpeed.limitText(upTo: .x1, in: .traditionalChinese), "自己駕駛時是 1×")
        XCTAssertEqual(Map3DFollowSpeed.limitText(upTo: .x10, in: .english), Map3DFollowSpeed.limitText(in: .english))

        session.endManualDrive()
        XCTAssertEqual(session.speedCap, .x10)
        XCTAssertEqual(session.speedChoices, [.x1, .x10])
        session.setSpeed(.x10)
        XCTAssertEqual(session.world.clock.speed, .x10)
    }

    /// The run is stepped a second of the game for each of the clock's at
    /// 1×, whatever the clock runs at: at 10× (which the menu does not
    /// give while driving) the driven train goes no faster.
    func testTheDrivenTrainIsSteppedAtOneTimesWhateverTheClockRunsAt() throws {
        func driven(at speed: GameSpeed) throws -> Double {
            let (session, _) = try makeSession()
            session.startManualDrive()
            var time = 0.0
            XCTAssertTrue(run(session, from: &time) { session.manualDrivePhase == .driving })
            session.setManualDriveNotch(ManualDrive.Notch(step: 2))
            let from = try XCTUnwrap(session.stepManualDrive(at: time)).metres
            if speed != .x1 { session.changeSpeed(speed) }
            for _ in 0..<50 {
                time += 0.1
                session.stepManualDrive(at: time)
            }
            return try XCTUnwrap(session.stepManualDrive(at: time)).metres - from
        }
        let slow = try driven(at: .x1)
        XCTAssertGreaterThan(slow, 0)
        XCTAssertEqual(try driven(at: .x10), slow, accuracy: 0.001)
    }

    func testTheScreenshotReviewsResultIsAStopJustShortAFewSecondsLate() throws {
        let (session, _) = try makeSession()
        session.finishManualDriveForScreenshot()
        XCTAssertNil(session.manualDrivePhase, "nothing while not driving")
        session.startManualDrive()
        var time = 0.0
        XCTAssertTrue(run(session, from: &time) { session.manualDrivePhase == .driving })
        session.finishManualDriveForScreenshot()
        XCTAssertEqual(session.manualDrivePhase, .over)
        let result = try XCTUnwrap(session.manualDriveReading?.result)
        XCTAssertEqual(result.outcome, .stopped)
        XCTAssertEqual(result.offset, -0.7, accuracy: 0.2)
        XCTAssertEqual(result.lateness, 5, accuracy: 2)
        XCTAssertGreaterThanOrEqual(result.total, 95)
        XCTAssertEqual(result.text(in: .traditionalChinese).lines.count, 2)
    }

    /// Review L17-14: a run that ends past the mark keeps the speed it
    /// ended at for its result, and the train is drawn standing: it is
    /// heard standing too, not running on until the card is closed.
    func testARunThatPassedItsStopIsHeardStanding() throws {
        let (session, _) = try makeSession()
        var told: [RunningSound?] = []
        session.runningSound = { told.append($0) }
        session.startManualDrive()
        var time = 0.0
        XCTAssertTrue(run(session, from: &time) { session.manualDriveReading?.phase == .driving })
        session.setManualDriveNotch(.fullPower)
        XCTAssertTrue(run(session, from: &time, ticks: 30_000) { session.manualDriveReading?.phase == .over })
        XCTAssertEqual(session.manualDriveReading?.result?.outcome, .passed)
        XCTAssertGreaterThan(session.manualDriveReading?.speed ?? 0, 0, "the speed it passed at")
        XCTAssertTrue(told.contains { $0?.motor != nil }, "it was heard pulling on the way")
        XCTAssertNil((told.last ?? nil)?.motor)
        XCTAssertNil(told.last ?? nil, "an electric train standing is silent")
        XCTAssertEqual(session.manualDriveSound?.kmh, 0)
    }

    func testTheMotorsAreHeardAsTheHandleStands() throws {
        let (session, train) = try makeSession()
        var told: [RunningSound?] = []
        session.runningSound = { told.append($0) }
        session.startManualDrive()
        var time = 0.0
        XCTAssertTrue(run(session, from: &time) { session.manualDriveReading?.phase == .driving })
        session.setManualDriveNotch(.fullPower)
        XCTAssertTrue(run(session, from: &time) { (session.manualDriveReading?.speed ?? 0) >= 40 })
        XCTAssertEqual((told.last ?? nil)?.motor?.loop.mode, .power, "pulling: the motors' rising song")
        session.setManualDriveNotch(.neutral)
        XCTAssertTrue(run(session, from: &time, ticks: 30) { false } == false)
        XCTAssertNil((told.last ?? nil)?.motor, "rolling: the wheels alone")
        XCTAssertNotNil(told.last ?? nil)
        session.setManualDriveNotch(.fullBrake)
        XCTAssertTrue(run(session, from: &time) { (session.manualDriveReading?.speed ?? 99) <= 30 })
        XCTAssertEqual((told.last ?? nil)?.motor?.loop.mode, .brake)
        // The world's train is not what is heard.
        let own = RunningSound.of(following: session.world.train(id: train), in: session.world)
        XCTAssertNotEqual(own, told.last ?? nil)
    }
}
