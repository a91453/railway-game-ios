import Foundation
@testable import GameCore
import XCTest

/// The traffic-control speed-ups that keep every result the same, checked
/// against the way each was worked out before.
final class TrafficSpeedTests: XCTestCase {
    /// The way to another berth (decision 57, ``GameWorld/alternativeRoute(of:to:avoiding:memo:)``)
    /// asks the other trains' directions a traversal at a time, and takes
    /// the free way whole when it runs against none of them: the same way
    /// as the search with all of them gathered into a set. Every running
    /// service of the long-leg replay a tick at a time, of the traffic
    /// control and following campaigns, and of a terminus whose other
    /// berth a line runs both ways (decision 278's scene: the free way
    /// there runs against it, so the search is made again), at every step.
    func testTheWayToAnotherBerthIsTheSearchWithTheDirectionsGathered() throws {
        var compared = 0, found = 0, against = 0
        func compare(_ world: GameWorld, _ context: String) {
            var memo = GameWorld.DirectionMemo()
            let holders = world.trackHolders(memo: &memo)
            // Each running service as it travels, and each waiting one as
            // it would set off.
            let candidates = world.trains.compactMap { train -> Train? in
                if case .waitingAtStop(let stop, let cycle)? = train.execution { return world.leaving(train, stop: stop, cycle: cycle).train }
                return train
            }
            for candidate in candidates {
                guard case .travellingToStop(let stop, _)? = candidate.execution, let position = candidate.position else { continue }
                let station = candidate.timetable[stop].station
                let blocked = world.blockedTrack(except: candidate.id, holders: holders)
                let way = world.alternativeRoute(of: candidate, to: station, avoiding: blocked, memo: &memo)
                // As it was worked out before.
                var gathered: TrainPath?
                let (limit, overflow) = world.routeLength(of: candidate).addingReportingOverflow(GameWorld.detourAllowance)
                if let free = world.path(from: position, toStation: station, length: candidate.length, avoiding: blocked),
                   overflow || free.distance <= limit {
                    let forbidden = world.opposingServiceTraversals(for: candidate, memo: &memo).subtracting(world.terminusTraversals(along: free, to: station))
                    if world.runsAlongAny(free, from: position, forbidden.contains) { against += 1 }
                    if let path = world.path(from: position, toStation: station, length: candidate.length, avoiding: blocked, forbidden: forbidden),
                       overflow || path.distance <= limit {
                        gathered = path
                    }
                }
                XCTAssertEqual(way, gathered, "\(context): \(candidate.id)")
                compared += 1
                if way != nil { found += 1 }
            }
        }
        var world = try LongLegReplayTests.world()
        for operation in LongLegReplayTests.operations() {
            var parts = [operation]
            if case .advance(let ticks) = operation { parts = Array(repeating: .advance(1), count: ticks) }
            for part in parts {
                _ = KernelDifferentialTests.apply(part, to: &world)
                compare(world, "long leg \(part)")
            }
        }
        for index in 0..<12 {
            var testCase = PropertyCase(suite: "traffic.alternativeRoute", seed: 0x5EED_A002, index: index)
            var world = try index % 2 == 0
                ? TrafficControlPropertyTests.generateWorld(&testCase, operations: 0)
                : TrafficControlPropertyTests.beginFollowing(&testCase).world
            for step in 0..<40 {
                let operation = index % 2 == 0
                    ? TrafficControlPropertyTests.operation(in: world, using: &testCase.random)
                    : TrafficControlPropertyTests.followingOperation(in: world, using: &testCase.random)
                _ = TrafficControlPropertyTests.apply(operation, to: &world)
                compare(world, "case \(index) step \(step)")
            }
        }
        for blocks in [false, true] {
            var world = try terminusWorld(blocks: blocks)
            for minute in 0..<30 {
                try world.advance(ticks: 1)
                compare(world, "terminus, blocks \(blocks), minute \(minute)")
            }
        }
        XCTAssertGreaterThan(compared, 500)
        XCTAssertGreaterThan(found, 50, "ways found")
        XCTAssertGreaterThan(against, 0, "free ways that run against another train's direction, so searched again")
    }

    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    private func backward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .backward)
    }

    /// `TerminusTests`' scene: the line M runs from S to T's P2 and back,
    /// along e3 both ways; D, from R to T, would stop at P1, where I, a
    /// train without a service, stands.
    ///
    ///                               ┌──e2── P1 (T)
    ///   R ──e0── n1 ──e1── J ───────┼──e3── P2 (T)
    ///         (S on e1)             └──e4───────────── U
    private func terminusWorld(blocks: Bool) throws -> GameWorld {
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
        try world.buildTrackEdge(from: start, to: n1)
        try world.buildTrackEdge(from: n1, to: junction)
        try world.buildTrackEdge(from: junction, to: p1)
        try world.buildTrackEdge(from: junction, to: p2)
        try world.buildTrackEdge(from: junction, to: far)
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
        let line = try world.createLine(named: "M", stops: [s, t]).id
        try world.setLineRoutePreferences(line, to: [
            LineRoutePreference(from: 0, to: 1, tracks: [forward(2), forward(4)], platform: TrackPlatform(station: t, edge: .edge(4), start: 30_720, end: 38_912)),
            LineRoutePreference(from: 1, to: 0, tracks: [backward(4), backward(2)], platform: TrackPlatform(station: s, edge: .edge(2), start: 4_096, end: 8_192)),
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
        return world
    }
}
