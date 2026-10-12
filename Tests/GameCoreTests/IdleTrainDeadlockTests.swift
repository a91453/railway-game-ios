@testable import GameCore
import XCTest

/// A line's spare train (assigned, standing idle because the line runs
/// fewer trains than it has) under traffic control (ARCHITECTURE decision
/// 58, a later fix): it stands where the line's running train has to go,
/// and nothing else would ever move it.
final class IdleTrainDeadlockTests: XCTestCase {
    /// The single track W–M–E with a passing loop at M (`SingleTrackMeet`):
    /// a line over all three runs one train; its train at W is sent out,
    /// its spare stands at E's only platform.
    func spareAtTheFarEnd() throws -> (world: GameWorld, running: TrainID, spare: TrainID) {
        var world = try SingleTrackMeet.world()
        let line = try world.createLine(named: "L", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east]).id
        let running = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let spare = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072)
        for id in [running, spare] { try world.assignTrain(id, to: line) }
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.setTrafficControl(true)
        return (world, running, spare)
    }

    /// Before the fix the running train reached M, waited there for E's
    /// platform all day, and was not even reported as stuck. Now the spare
    /// steps aside to M's free berth and the line runs its trips.
    func testTheRunningTrainIsNotHeldAllDayByTheSpare() throws {
        var (world, running, spare) = try spareAtTheFarEnd()
        var arrivals = 0, wasAtEast = false
        while world.clock.now < GameTime(minutes: 1_440) {
            try world.advance(ticks: 1)
            let atEast = world.train(id: running)?.execution != nil && world.stationsStoppedAt(by: running) == [SingleTrackMeet.east]
            if atEast && !wasAtEast { arrivals += 1 }
            wasAtEast = atEast
        }
        XCTAssertGreaterThan(arrivals, 10, "the line's train calls at E through the day")
        XCTAssertEqual(world.stationsStoppedAt(by: spare), [SingleTrackMeet.middle], "the spare stands aside at M")
        XCTAssertNil(world.train(id: spare)?.execution, "the spare stays without a service")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// The running train waiting at M for the platform the spare stands
    /// on is reported as stuck (before the fix it was not: the spare
    /// waits for nothing), and at the next whole minute the spare sets off
    /// for M's free berth, the nearest that lets it go.
    func testTheSpareIsCountedAndStepsAside() throws {
        var (world, running, spare) = try spareAtTheFarEnd()
        while world.train(id: running)?.execution != .waitingAtStop(1) || world.deadlockedTrains().isEmpty {
            try world.advance(ticks: 1)
            XCTAssertLessThan(world.clock.now, GameTime(minutes: 60))
        }
        XCTAssertEqual(world.deadlockedTrains(), [running])
        XCTAssertEqual(world.trainHoldingRoute(of: running), spare)
        while world.train(id: spare)?.reservation.isEmpty ?? true {
            try world.advance(ticks: 1)
            XCTAssertLessThan(world.clock.now, GameTime(minutes: 60))
        }
        XCTAssertTrue(world.clock.now.isWholeMinute)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertNil(world.train(id: spare)?.execution)
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// The reference model (written from the rules) agrees second by
    /// second, through the spare's move and the running train going on
    /// from M to E (15 minutes).
    func testTheReferenceModelAgreesAtEverySecond() throws {
        var (world, _, _) = try spareAtTheFarEnd()
        var model = SingleTrackMeet.model()
        XCTAssertNil(model.createLine(named: "L", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east]))
        let line = LineID(rawValue: 1)
        for (number, edge) in [(1, SingleTrackMeet.forward(1)), (2, SingleTrackMeet.backward(3))] {
            XCTAssertNil(model.purchaseTrain(named: "T"))
            XCTAssertNil(model.setCars(TrainID(rawValue: number), 2))
            XCTAssertNil(model.placeTrain(TrainID(rawValue: number), at: .onEdge(edge, offset: 3_072)))
            XCTAssertNil(model.setContinuation(TrainID(rawValue: number), along: [], stoppingAt: 3_072))
            XCTAssertNil(model.setRate(TrainID(rawValue: number), 1_024))
        }
        for number in 1...2 { XCTAssertNil(model.assign(TrainID(rawValue: number), to: line)) }
        XCTAssertNil(model.setLineWindow(line, .allDay))
        XCTAssertNil(model.setLineTrains(line, TrainsInService(peak: 1, offPeak: 1, low: 1)))
        XCTAssertNil(model.setTrafficControl(true))
        world.setSpeed(.x1)
        model.setSpeed(.x1)
        for second in 0..<(15 * 60) {
            try world.advance(ticks: 10)
            XCTAssertNil(model.advance(ticks: 10))
            let differences = KernelDifferentialTests.differences(world, model)
            XCTAssertEqual(differences, [], "second \(second)")
            XCTAssertEqual(world.deadlockedTrains(), model.deadlockedTrains(), "second \(second)")
            guard differences.isEmpty else { return }
        }
    }

    /// The two-station shuttle of #447's experiment V3: each end has one
    /// platform, the line runs one train, and its second train stands at
    /// the other end. There is no berth either could stand aside at, so it
    /// stays a reported deadlock, nothing moves, until the player changes
    /// something (decision 58): neither train is a spare while the line
    /// still wants a train out.
    func testAShuttleWithNoBerthToSpareStaysAReportedDeadlock() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 36_864, height: 12_288), economy: GameEconomy(balance: 1_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal))
        for point in SingleTrackMeet.points().prefix(4) { _ = try world.buildTrackNode(at: point) }
        for edge in 1...3 { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        for (name, x) in [("W", Int64(3_072)), ("E", 31_744)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 8_192))
        }
        try world.addTrackPlatform(StationID(rawValue: 1), on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(StationID(rawValue: 2), on: .edge(3), from: 5_120, to: 7_168)
        let line = try world.createLine(named: "L", stops: [StationID(rawValue: 1), StationID(rawValue: 2)]).id
        let first = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let second = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072)
        for id in [first, second] { try world.assignTrain(id, to: line) }
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        world.setFlexDispatch(true)
        try world.setTrafficControl(true)
        let placements = [first, second].map { world.train(id: $0)?.placement }
        try world.advance(ticks: 60)
        XCTAssertEqual(world.deadlockedTrains(), [first, second])
        XCTAssertFalse(world.trains.contains(where: world.isSpare))
        XCTAssertEqual([first, second].map { world.train(id: $0)?.placement }, placements)
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }
}
