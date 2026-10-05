import Foundation
@testable import GameCore
import XCTest

/// Deadlocks and passing places (Phase 4.6 Stage V2, ARCHITECTURE decision
/// 58), on the 512 m single track with a passing loop at M
/// (`SingleTrackMeet`), and on the same track without the loop.
final class DeadlockTests: XCTestCase {
    /// Two express services face each other across the single track, each
    /// to the other's terminal without calling at M: each route needs the
    /// other's platform, so both wait (decision 32, point 15).
    func expresses(_ world: inout GameWorld) throws -> (east: TrainID, west: TrainID) {
        let east = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let west = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072)
        for (id, stops) in [(east, [SingleTrackMeet.west, SingleTrackMeet.east]), (west, [SingleTrackMeet.east, SingleTrackMeet.west])] {
            try world.setTrainTimetable(id, to: stops.enumerated().map {
                ScheduledStop(station: $0.element, arrival: .init(seconds: Int64($0.offset) * 240), departure: .init(seconds: Int64($0.offset) * 240))
            })
            try world.startTrainService(id)
        }
        try world.setTrafficControl(true)
        return (east, west)
    }

    func testFacingExpressesPassAtAPassingPlace() throws {
        var world = try SingleTrackMeet.world()
        let (east, west) = try expresses(&world)
        // 0:42: both due, each route held by the other.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.trainHoldingRoute(of: east), west)
        XCTAssertEqual(world.trainHoldingRoute(of: west), east)
        XCTAssertEqual(world.deadlockedTrains(), [east, west])
        // 1:00: the dispatcher sends the eastbound train, the first, to
        // M's main platform, on its own way (the whole way through it is
        // no longer than its route), where it stands aside.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(world.train(id: east)?.execution, .travellingToStop(1))
        XCTAssertEqual(world.train(id: east)?.times?.departure, GameTime(seconds: 60))
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.middle])
        XCTAssertTrue(world.isAtPassingPlace(world.train(id: east)!))
        XCTAssertEqual(world.trainHoldingRoute(of: east), west)
        // The westbound train goes round it through the loop (V1), and the
        // eastbound one goes on once its way to E is free.
        try world.advance(ticks: 8)
        XCTAssertNil(world.train(id: east)?.execution)
        XCTAssertNil(world.train(id: west)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.east])
        XCTAssertEqual(world.stationsStoppedAt(by: west), [SingleTrackMeet.west])
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    func testThePassingPlaceIsTheFirstThatLetsAnotherGo() throws {
        var world = try SingleTrackMeet.world()
        let (east, west) = try expresses(&world)
        try world.advance(ticks: 1)
        var memo = GameWorld.DirectionMemo()
        let stuck = world.deadlock(memo: &memo)
        let request = try XCTUnwrap(stuck[east])
        let passing = try XCTUnwrap(world.passingPlace(for: request.candidate, in: stuck, memo: &memo))
        // Hand arithmetic: 5120 left on e1 + 9216 to M's main berth; on
        // from there 7168 on e2 + 7168 to E's berth = 28672, the default.
        XCTAssertEqual(passing.path, TrainPath(traversals: [SingleTrackMeet.forward(2)], end: 9_216, distance: 14_336))
        XCTAssertEqual(passing.distance, 28_672)
        XCTAssertEqual(world.path(from: request.candidate.position!, toStation: SingleTrackMeet.east, length: 2_048)?.distance, 28_672)
        // The westbound train, going round the loop, would be 636 longer.
        XCTAssertNotNil(stuck[west])
    }

    /// Without the loop no passing place lets the other train go: the
    /// deadlock stays, and both keep waiting where they are.
    func testADeadlockWithNoWayOutIsReportedAndLeftAsItIs() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 36_864, height: 12_288), economy: GameEconomy(balance: 1_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal))
        for point in SingleTrackMeet.points().prefix(4) { _ = try world.buildTrackNode(at: point) }
        for edge in 1...3 { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 8_192))
        }
        for (station, edge, start, end) in SingleTrackMeet.platforms() where edge != 5 {
            try world.addTrackPlatform(station, on: .edge(edge), from: start, to: end)
        }
        let (east, west) = try expresses(&world)
        try world.advance(ticks: 10)
        XCTAssertEqual(world.deadlockedTrains(), [east, west])
        XCTAssertEqual(world.train(id: east)?.execution, .waitingAtStop(0))
        XCTAssertEqual(world.train(id: west)?.execution, .waitingAtStop(0))
        XCTAssertEqual(world.trainHoldingRoute(of: east), west)
        XCTAssertEqual(world.trainHoldingRoute(of: west), east)
        // Decision 64: each waits for track the other stands on and fouls
        // at its terminal, and for nothing the other does not hold.
        for (id, other) in [(east, west), (west, east)] {
            let contested = world.contestedResources(of: id)
            XCTAssertFalse(contested.isEmpty)
            XCTAssertTrue(Set(contested).isSubset(of: world.heldResources(of: other)))
            XCTAssertTrue(Set(contested).isSuperset(of: world.occupiedResources(of: other)))
        }
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// A train waiting for one that will leave by itself is not in a
    /// deadlock: the westbound service waits for M's main platform while
    /// the eastbound one stands there until its departure is due.
    func testWaitingForATrainThatWillLeaveIsNoDeadlock() throws {
        var world = try SingleTrackMeet.world()
        let standing = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(2), offset: 9_216)
        let loop = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(5), offset: 5_120)
        let west = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072)
        try world.setTrainTimetable(standing, to: [
            ScheduledStop(station: SingleTrackMeet.middle, arrival: .init(seconds: 0), departure: .init(seconds: 600)),
            ScheduledStop(station: SingleTrackMeet.east, arrival: .init(seconds: 840), departure: .init(seconds: 840)),
        ])
        try world.startTrainService(standing)
        try world.setTrainTimetable(west, to: Array(SingleTrackMeet.timetable(eastbound: false).prefix(2)))
        try world.startTrainService(west)
        try world.setTrafficControl(true)
        try world.advance(ticks: 3)
        XCTAssertEqual(world.trainHoldingRoute(of: west), standing)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertTrue(Set(world.contestedResources(of: west)).isSubset(of: world.heldResources(of: standing)))
        XCTAssertFalse(world.contestedResources(of: west).isEmpty)
        XCTAssertEqual(world.contestedResources(of: standing), [])
        _ = loop
    }

    /// The dispatcher works at whole minutes only, so a batch of a minute
    /// at a time is exactly a second at a time.
    func testBatchedMinutesResolveExactlyAsSingleSeconds() throws {
        var world = try SingleTrackMeet.world()
        _ = try expresses(&world)
        var seconds = world
        seconds.setSpeed(.x1)
        try world.advance(ticks: 12)
        for _ in 0..<(12 * 60) { try seconds.advance(ticks: 10) }
        world.setSpeed(.x1)
        XCTAssertEqual(world, seconds)
    }

    func testTheReferenceModelAgreesAtEverySecond() throws {
        var world = try SingleTrackMeet.world()
        var model = SingleTrackMeet.model()
        for (edge, offset) in [(SingleTrackMeet.forward(1), Int64(3_072)), (SingleTrackMeet.backward(3), 3_072)] {
            let id = try SingleTrackMeet.stand(&world, edge: edge, offset: offset)
            XCTAssertNil(model.purchaseTrain(named: "T"))
            XCTAssertNil(model.setCars(id, 2))
            XCTAssertNil(model.placeTrain(id, at: .onEdge(edge, offset: offset)))
            XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: offset))
            XCTAssertNil(model.setRate(id, 1_024))
        }
        for (number, stops) in [(1, [SingleTrackMeet.west, SingleTrackMeet.east]), (2, [SingleTrackMeet.east, SingleTrackMeet.west])] {
            let id = TrainID(rawValue: number)
            let timetable = stops.enumerated().map {
                ScheduledStop(station: $0.element, arrival: .init(seconds: Int64($0.offset) * 240), departure: .init(seconds: Int64($0.offset) * 240))
            }
            try world.setTrainTimetable(id, to: timetable)
            try world.startTrainService(id)
            XCTAssertNil(model.setTimetable(id, timetable))
            XCTAssertNil(model.startService(id))
        }
        try world.setTrafficControl(true)
        XCTAssertNil(model.setTrafficControl(true))
        world.setSpeed(.x1)
        model.setSpeed(.x1)
        for second in 0..<(10 * 60) {
            try world.advance(ticks: 10)
            XCTAssertNil(model.advance(ticks: 10))
            let differences = KernelDifferentialTests.differences(world, model)
            XCTAssertEqual(differences, [], "second \(second)")
            XCTAssertEqual(world.deadlockedTrains(), model.deadlockedTrains(), "second \(second)")
            XCTAssertEqual(world.routeWaits(), WorldInvariants.routeWaitsOneByOne(in: world), "second \(second)")
            for train in world.trains {
                XCTAssertEqual(world.trainHoldingRoute(of: train.id), model.trainHoldingRoute(of: train.id), "second \(second)")
                XCTAssertEqual(world.contestedResources(of: train.id), model.contestedResources(of: train.id), "second \(second)")
                XCTAssertEqual(world.reservedResources(of: train.id), model.reservedResources(of: train.id), "second \(second)")
            }
            guard differences.isEmpty else { return }
        }
    }

    /// A save made while a train stands at a passing place loads as it was
    /// and runs on the same.
    func testASaveAtAPassingPlaceRoundTripsAndRunsOn() throws {
        var world = try SingleTrackMeet.world()
        let (east, _) = try expresses(&world)
        world.setSpeed(.x1)
        try world.advance(ticks: 1_200)
        XCTAssertTrue(world.isAtPassingPlace(world.train(id: east)!))
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        var (a, b) = (world, loaded)
        try a.advance(ticks: 3_000)
        try b.advance(ticks: 3_000)
        XCTAssertEqual(a, b)
        XCTAssertEqual(WorldInvariants.violations(in: a), [])
    }

    /// Turning traffic control off sends a train at a passing place on at
    /// once: nothing holds its way any more.
    func testWithoutTrafficControlAPassingPlaceIsLeftAtOnce() throws {
        var world = try SingleTrackMeet.world()
        let (east, _) = try expresses(&world)
        world.setSpeed(.x1)
        try world.advance(ticks: 1_200)
        XCTAssertTrue(world.isAtPassingPlace(world.train(id: east)!))
        try world.setTrafficControl(false)
        try world.advance(ticks: 10)
        XCTAssertFalse(world.isAtPassingPlace(world.train(id: east)!))
        XCTAssertEqual(world.train(id: east)?.movement.edges, [.edge(3)])
    }
}
