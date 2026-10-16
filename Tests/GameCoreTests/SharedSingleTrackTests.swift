@testable import GameCore
import XCTest

/// Two lines sharing a single track with no passing place (decision 255,
/// docs/research/CORE_LOOP_2026-10-16.md §1.2): C ── A ── B, a shuttle
/// between A and B, and a second line from C through A to B. The second
/// line's train can never pass the shuttle, so it cannot reach B while the
/// shuttle runs; under traffic control the two used to stand face to face
/// for good.
final class SharedSingleTrackTests: XCTestCase {
    static let c = StationID(rawValue: 1)
    static let a = StationID(rawValue: 2)
    static let b = StationID(rawValue: 3)

    /// The track, the stations and both lines, each with its train at its
    /// first stop: the shuttle at A heading for B, the other at C heading
    /// for A.
    func world() throws -> (world: GameWorld, shuttle: TrainID, through: TrainID) {
        var world = try GameWorld(bounds: WorldBounds(width: 36_864, height: 8_192), economy: GameEconomy(balance: 1_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal))
        for x in [Int64(1_024), 17_408, 33_792] { _ = try world.buildTrackNode(at: WorldCoordinate(x: x, y: 4_096)) }
        // e1: A → B, e2: A → C.
        _ = try world.buildTrackEdge(from: .node(2), to: .node(3))
        _ = try world.buildTrackEdge(from: .node(2), to: .node(1))
        for (name, x) in [("C", Int64(3_072)), ("A", 17_408), ("B", 31_744)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 6_144))
        }
        let length = try XCTUnwrap(world.trackEdge(.edge(1))?.length)
        try world.addTrackPlatform(Self.a, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(Self.b, on: .edge(1), from: length - 3_072, to: length - 1_024)
        try world.addTrackPlatform(Self.c, on: .edge(2), from: length - 3_072, to: length - 1_024)
        try world.setTrafficControl(true)
        let shuttle = try line(&world, stops: [Self.a, Self.b], at: TrackTraversal(edge: .edge(1), direction: .forward))
        let through = try line(&world, stops: [Self.c, Self.a, Self.b], at: TrackTraversal(edge: .edge(2), direction: .backward))
        return (world, shuttle, through)
    }

    private func line(_ world: inout GameWorld, stops: [StationID], at traversal: TrackTraversal) throws -> TrainID {
        let line = try world.createLine(named: "L\(world.lines.count + 1)", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try SingleTrackMeet.stand(&world, edge: traversal, offset: 3_072)
        try world.assignTrain(train, to: line)
        return train
    }

    /// Over a day neither train is ever left in a deadlock for more than
    /// the dispatcher's minute, and both keep calling: the shuttle at A
    /// and B, the other at C and A.
    func testTwoLinesSharingASingleTrackKeepRunning() throws {
        var (world, shuttle, through) = try world()
        var calls: [TrainID: Set<StationID>] = [:]
        var stuckMinutes = 0
        for _ in 0..<1_440 {
            try world.advance(ticks: 1)
            stuckMinutes = world.deadlockedTrains().isEmpty ? 0 : stuckMinutes + 1
            XCTAssertLessThanOrEqual(stuckMinutes, 2, "deadlocked at \(world.clock.now)")
            if stuckMinutes > 2 { break }
            for id in [shuttle, through] {
                calls[id, default: []].formUnion(world.stationsStoppedAt(by: id))
            }
        }
        XCTAssertEqual(calls[shuttle], [Self.a, Self.b])
        XCTAssertTrue(calls[through]?.isSuperset(of: [Self.c, Self.a]) == true, "\(calls[through] ?? [])")
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// Minute 4: the shuttle waits at B for A, where the other train
    /// waits for B. Minute 5: the dispatcher turns that one back at A, as
    /// its timetable comes back there from B, leaving B out; it waits at
    /// A again, turned round, until it is due to leave for C, and the
    /// shuttle is no longer stuck. A save there loads as it was.
    func testTheThroughTrainTurnsBackShortAtTheSharedStation() throws {
        var (world, shuttle, through) = try world()
        try world.advance(ticks: 4)
        XCTAssertEqual(world.deadlockedTrains(), [shuttle, through])
        XCTAssertEqual(world.train(id: through)?.execution, .waitingAtStop(1))
        XCTAssertEqual(world.train(id: through)?.timetable.map(\.station), [Self.c, Self.a, Self.b, Self.a, Self.c])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(world.train(id: through)?.execution, .waitingAtStop(3))
        XCTAssertEqual(world.stationsStoppedAt(by: through), [Self.a])
        XCTAssertNil(WorldInvariants.roundTripProblem(of: world))
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }
}
