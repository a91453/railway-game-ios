import Foundation
@testable import GameCore
import XCTest

/// Decision 278: decision 57's direction protection does not forbid the
/// way into a terminus. Every track there is run both ways, by each train
/// coming in and going out turned round, so the planned directions of the
/// lines that use it forbade every berth but the one a route names. In
/// the high-speed demo under traffic control a set at Tainan waited for
/// the one set standing on its berth at Zuoying with seven of its eight
/// tracks free (and the depot's sets for Zuoying with it).
///
///                               ┌──e2── P1 (T)
///   R ──e0── n1 ──e1── J ───────┼──e3── P2 (T)
///         (S on e1)             └──e4───────────── U
///
/// The line M runs from S to T's P2 and back, so it is planned along e3
/// both ways. D, a service from R to T, would stop at P1, where I, a
/// train without a service, stands. With block sections only: without
/// them a train following others may stop in a terminus's throat, and
/// letting more trains in filled Zuoying (see `terminusTraversals`).
final class TerminusTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private func backward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .backward)
    }

    private struct Scene {
        var world: GameWorld
        let service: TrainID
        let idle: TrainID
        let t: StationID
    }

    private func makeScene(blocks: Bool = true) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 106_496, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let junction = try world.buildTrackNode(at: WorldCoordinate(x: 40_960, y: 8_192))
        let p1 = try world.buildTrackNode(at: WorldCoordinate(x: 81_920, y: 10_240))
        let p2 = try world.buildTrackNode(at: WorldCoordinate(x: 81_920, y: 6_144))
        let far = try world.buildTrackNode(at: WorldCoordinate(x: 102_400, y: 8_192))
        try world.buildTrackEdge(from: start, to: n1)     // e0
        try world.buildTrackEdge(from: n1, to: junction)  // e1
        try world.buildTrackEdge(from: junction, to: p1)  // e2
        try world.buildTrackEdge(from: junction, to: p2)  // e3
        try world.buildTrackEdge(from: junction, to: far) // e4
        let r = try world.buildStation(named: "R", at: PlanPoint(x: 4_096, y: 6_144)).id
        try world.addTrackPlatform(r, on: .edge(1), from: 1_024, to: 5_120)
        let s = try world.buildStation(named: "S", at: PlanPoint(x: 24_576, y: 6_144)).id
        try world.addTrackPlatform(s, on: .edge(2), from: 4_096, to: 8_192)
        let t = try world.buildStation(named: "T", at: PlanPoint(x: 77_824, y: 8_192)).id
        try world.addTrackPlatform(t, on: .edge(3), from: 28_672, to: 36_864)
        try world.addTrackPlatform(t, on: .edge(4), from: 30_720, to: 38_912)
        let u = try world.buildStation(named: "U", at: PlanPoint(x: 98_304, y: 6_144)).id
        let e4 = try XCTUnwrap(world.trackEdge(.edge(5))?.length)
        try world.addTrackPlatform(u, on: .edge(5), from: e4 - 6_144, to: e4 - 2_048)

        // M: S to T's P2 and back, along e3 both ways; its train stands at
        // U, out of D's way, and the line sends none out.
        let line = try world.createLine(named: "M", stops: [s, t]).id
        let p2Platform = TrackPlatform(station: t, edge: .edge(4), start: 30_720, end: 38_912)
        let sPlatform = TrackPlatform(station: s, edge: .edge(2), start: 4_096, end: 8_192)
        try world.setLineRoutePreferences(line, to: [
            LineRoutePreference(from: 0, to: 1, tracks: [forward(2), forward(4)], platform: p2Platform),
            LineRoutePreference(from: 1, to: 0, tracks: [backward(4), backward(2)], platform: sPlatform),
        ])
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 0, offPeak: 0, low: 0))
        let m = try world.purchaseTrain(named: "M1").id
        try world.setTrainCars(m, to: 2)
        try world.placeTrain(m, at: .onEdge(forward(5), offset: e4 - 2_048))
        try world.assignTrain(m, to: line)

        let idle = try world.purchaseTrain(named: "I").id
        try world.setTrainCars(idle, to: 2)
        try world.placeTrain(idle, at: .onEdge(forward(3), offset: 36_864))

        let service = try world.purchaseTrain(named: "D").id
        try world.setTrainCars(service, to: 2)
        try world.placeTrain(service, at: .onEdge(forward(1), offset: 5_120))
        try world.setTrainContinuation(service, along: [], stoppingAt: 5_120)
        try world.setTrainMovementRate(service, to: 4_096)
        try world.setTrainTimetable(service, to: [
            ScheduledStop(station: r, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: t, arrival: GameTime(minutes: 30), departure: GameTime(minutes: 30)),
        ])
        world.setBlockSections(blocks)
        try world.setTrafficControl(true)
        try world.startTrainService(service)
        return Scene(world: world, service: service, idle: idle, t: t)
    }

    /// Before decision 278 D waited at R for I all along: the only other
    /// berth, P2, lies on track M runs both ways. Now D sets off for P2.
    func testAServiceTakesAnotherBerthOfATerminusTheLinesRunBothWays() throws {
        var scene = try makeScene()
        var arrived = false
        for _ in 0..<60 {
            try scene.world.advance(ticks: 1)
            if scene.world.stationsStoppedAt(by: scene.service) == [scene.t] {
                arrived = true
                break
            }
        }
        XCTAssertTrue(arrived, "D calls at T; held by \(String(describing: scene.world.trainHoldingRoute(of: scene.service)))")
        guard case .onEdge(let traversal, _)? = scene.world.train(id: scene.service)?.position else { return XCTFail("D is placed") }
        XCTAssertEqual(traversal.edge, .edge(4), "at P2")
        XCTAssertEqual(WorldInvariants.violations(in: scene.world), [])
    }

    /// Only the way into the terminus is exempt: e3 leads only to P2, a
    /// dead end with T's platform; e1 has S's platform on it.
    func testTheWayIntoATerminus() throws {
        let scene = try makeScene()
        let path = TrainPath(traversals: [forward(2), forward(4)], end: 38_912, distance: 0)
        XCTAssertEqual(scene.world.terminusTraversals(along: path, to: scene.t), [forward(4)])
        XCTAssertEqual(scene.world.terminusTraversals(along: TrainPath(traversals: [forward(5)], end: nil, distance: 0), to: scene.t), [],
                       "e4 runs on to U's platform")
        XCTAssertEqual(try makeScene(blocks: false).world.terminusTraversals(along: path, to: scene.t), [], "without block sections, none")
    }
}
