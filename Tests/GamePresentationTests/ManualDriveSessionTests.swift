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
    private func makeSession(limits: Bool = true) throws -> (GameSession, TrainID) {
        var (world, train) = try world(limits: limits)
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

        session.endManualDrive()
        XCTAssertNil(session.manualDriveReading)
        XCTAssertNil(session.stepManualDrive(at: time))
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
