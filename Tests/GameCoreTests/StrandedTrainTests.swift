@testable import GameCore
import XCTest

/// Decision 735: a train's default departure keeps out of a berth from
/// which it would have no way on to the call after (the Western Trunk Line
/// train that went into the Yilan Line's track at Badu on the real-world
/// demo and stood there for 37 hours), and a train that stands half an
/// hour past its departure with no way asked for is reported as stranded.
final class StrandedTrainTests: XCTestCase {
    /// ``SingleTrackMeet`` with a siding of M's off the west junction, the
    /// mirror of the passing loop's entrance, ending at a buffer: its berth
    /// is the one nearest W, and from it no way goes on to E.
    private static func withSiding() throws -> (world: GameWorld, siding: TrackEdgeID) {
        var world = try SingleTrackMeet.world()
        let bend = try world.buildTrackNode(at: WorldCoordinate(x: 13_312, y: 2_048))
        let buffer = try world.buildTrackNode(at: WorldCoordinate(x: 17_408, y: 2_048))
        try world.buildTrackEdge(from: .node(2), to: bend, curve: .cubic(.init(x: 11_264, y: 4_096), .init(x: 11_264, y: 2_048)))
        let siding = try world.buildTrackEdge(from: bend, to: buffer)
        try world.addTrackPlatform(SingleTrackMeet.middle, on: siding, from: 0, to: 2_048)
        return (world, siding)
    }

    /// Plays until train `id`'s service waits at stop `stop` or ends, at
    /// most `minutes` minutes.
    private func play(_ world: inout GameWorld, _ id: TrainID, until stop: Int, minutes: Int = 120) throws {
        for _ in 0..<minutes {
            let execution = world.train(id: id)?.execution
            if execution == nil || execution == .waitingAtStop(stop, cycle: 0) { return }
            try world.advance(ticks: 1)
        }
    }

    private func edge(of id: TrainID, in world: GameWorld) -> TrackEdgeID? {
        guard case .onEdge(let traversal, _)? = world.train(id: id)?.position else { return nil }
        return traversal.edge
    }

    func testTheDefaultDepartureTakesABerthWithAWayOn() throws {
        let scene = try Self.withSiding()
        var world = scene.world
        let siding = scene.siding
        let id = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let length = try XCTUnwrap(world.train(id: id)).length
        // The trap: the nearest berth of M is the siding's, and from there
        // no way leads on to E.
        let nearest = try XCTUnwrap(world.path(from: .onEdge(SingleTrackMeet.forward(1), offset: 3_072), toStation: SingleTrackMeet.middle, length: length))
        XCTAssertEqual(nearest.traversals.last?.edge, siding)
        let end = try XCTUnwrap(world.network.edge(siding)).length
        XCTAssertNil(world.path(from: .onEdge(.init(edge: siding, direction: .forward), offset: nearest.end ?? end), toStation: SingleTrackMeet.east, length: length))

        try world.setTrainTimetable(id, to: SingleTrackMeet.timetable(eastbound: true))
        try world.startTrainService(id)
        try play(&world, id, until: 1)
        XCTAssertEqual(world.train(id: id)?.execution, .waitingAtStop(1, cycle: 0))
        XCTAssertEqual(edge(of: id, in: world), .edge(2), "at M's main platform, not in the siding")
        try play(&world, id, until: 2)
        XCTAssertEqual(edge(of: id, in: world), .edge(3), "on to E")
        XCTAssertEqual(world.strandedTrains(), [])
    }

    /// Where no berth of the call that the train can reach has a way on,
    /// the departure is as before: the nearest berth.
    func testWithNoBerthWithAWayOnTheNearestStays() throws {
        let scene = try Self.withSiding()
        var world = scene.world
        let siding = scene.siding
        let id = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        // W, M, then W again without turning round at M: the train comes
        // to M facing east, and no berth facing east leads back west.
        try world.setTrainTimetable(id, to: [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: 0)),
            .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 120), departure: .init(seconds: 120)),
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 240), departure: .init(seconds: 240)),
        ])
        try world.startTrainService(id)
        try play(&world, id, until: 1)
        XCTAssertEqual(world.train(id: id)?.execution, .waitingAtStop(1, cycle: 0))
        XCTAssertEqual(edge(of: id, in: world), siding)
    }

    /// A train due to leave with no way to its next call is stranded once
    /// half an hour has passed since its timetabled departure, with traffic
    /// control on or off; the train that runs is not.
    func testATrainWithNoWayOnIsStrandedAfterHalfAnHour() throws {
        var world = try SingleTrackMeet.world()
        let beyond = try world.buildTrackNode(at: WorldCoordinate(x: 35_840, y: 4_096))
        let edge = try world.buildTrackEdge(from: .node(4), to: beyond)
        let terminus = try world.buildStation(named: "F", at: PlanPoint(x: 35_840, y: 8_192)).id
        try world.addTrackPlatform(terminus, on: edge, from: 512, to: 1_536)
        let east = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let west = try SingleTrackMeet.stand(&world, edge: .init(edge: edge, direction: .forward), offset: 1_536, cars: 1)
        try world.setTrainTimetable(east, to: [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: 60)),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 660), departure: .init(seconds: 720)),
        ])
        try world.setTrainTimetable(west, to: [
            .init(station: terminus, arrival: .init(seconds: 0), departure: .init(seconds: 120)),
            .init(station: SingleTrackMeet.middle, arrival: .init(seconds: 400), departure: .init(seconds: 460)),
        ])
        try world.startTrainService(east)
        try world.startTrainService(west)
        try world.advance(ticks: 3)
        XCTAssertEqual(world.heldDeparture(of: west), .noRoute(to: SingleTrackMeet.middle), "held at once")
        XCTAssertEqual(world.strandedTrains(), [], "not yet half an hour late")
        // 120 s + 1,800 s: the 32nd minute.
        while world.clock.now.seconds < 120 + GameWorld.strandedAfter - 60 { try world.advance(ticks: 1) }
        XCTAssertEqual(world.strandedTrains(), [])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.strandedTrains(), [west])
        XCTAssertEqual(world.deadlockedTrains(), [], "no train holds its way: not a deadlock")
        try world.setTrafficControl(true)
        XCTAssertEqual(world.strandedTrains(), [west])
    }
}
