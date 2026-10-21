@testable import GameCore
import XCTest

/// Decision 308: without block sections, a following train (Stage U2,
/// decision 56) comes no nearer to a line's train standing without a
/// service where its path ends. In the high-speed demo THSR 31 followed
/// THSR 19 to Zuoying's berth; THSR 19 ended its service there, and THSR
/// 31 went on until it stood in the throat, on the only way THSR 19 had to
/// the depot. Neither ever moved again.
final class FollowerStandingTrainTests: XCTestCase {
    private func forward(_ edge: Int) -> TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: .forward)
    }

    //   n0 ──e1── m ──e2── z
    //
    // X, of the line Main, stands without a service near the end of e2,
    // where its path ends. F, on e1, follows it, its route along e2 to X's
    // place.
    private func makeWorld() throws -> (world: GameWorld, f: TrainID, x: TrainID, start: TrainPosition) {
        var world = try GameWorld(bounds: WorldBounds(width: 106_496, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
                                  clock: GameClock(speed: .normal))
        let n0 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let m = try world.buildTrackNode(at: WorldCoordinate(x: 49_152, y: 8_192))
        let z = try world.buildTrackNode(at: WorldCoordinate(x: 98_304, y: 8_192))
        try world.buildTrackEdge(from: n0, to: m) // e1
        try world.buildTrackEdge(from: m, to: z)  // e2
        let e2 = try XCTUnwrap(world.trackEdge(.edge(2))?.length)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 4_096, y: 10_240)).id
        try world.addTrackPlatform(b, on: .edge(1), from: 1_024, to: 9_216)
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 94_208, y: 10_240)).id
        try world.addTrackPlatform(a, on: .edge(2), from: e2 - 10_240, to: e2 - 2_048)
        let line = try world.createLine(named: "Main", stops: [b, a]).id
        // Its one run long after the test.
        try world.setLineRuns(line, to: [
            LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 1_200 * 60, departure: 1_200 * 60), LineRunTime(arrival: 1_210 * 60, departure: 1_210 * 60)]),
        ])
        var ids: [TrainID] = []
        for name in ["F", "X"] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            ids.append(id)
        }
        let (f, x) = (ids[0], ids[1])
        let start = TrainPosition.onEdge(forward(1), offset: 12_288)
        for (id, position) in [(f, start), (x, .onEdge(forward(2), offset: e2 - 2_048))] {
            try world.placeTrain(id, at: position)
            guard case .onEdge(_, let offset) = position else { continue }
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 16_384)
        }
        try world.assignTrain(x, to: line)
        try world.setTrafficControl(true)
        var train = try XCTUnwrap(world.train(id: f))
        train.movement.edges = [.edge(2)]
        train.movement.end = e2 - 2_048
        train.movement.cursor = 0
        train.reservation = world.authorityEnvelope(of: train, to: 0).sorted()
        world = world.replacing(train)
        return (world, f, x, start)
    }

    func testAFollowingTrainWaitsShortOfAStandingLineTrain() throws {
        var (world, f, x, _) = try makeWorld()
        XCTAssertTrue(world.isFollowing(try XCTUnwrap(world.train(id: f))))
        XCTAssertNil(world.train(id: x)?.execution)
        let held = world.heldResources(of: f)
        try world.advance(ticks: 10)
        // It takes no more of its route: before, it went on along e2 to
        // ``GameWorld/followingGap`` short of X.
        guard case .onEdge(let traversal, let offset)? = world.train(id: f)?.position else { return XCTFail("F is placed") }
        XCTAssertEqual(traversal, forward(1))
        XCTAssertGreaterThanOrEqual(offset, 12_288)
        XCTAssertTrue(Set(world.heldResources(of: f)).isSubset(of: Set(held)))
        // Once X has gone, it goes on to the end of its route.
        try world.unplaceTrain(x)
        try world.advance(ticks: 10)
        let e2 = try XCTUnwrap(world.trackEdge(.edge(2))?.length)
        XCTAssertEqual(world.train(id: f)?.position, .onEdge(forward(2), offset: e2 - 2_048))
    }

    /// A batch ends where minute by minute does.
    func testABatchEndsWhereMinutesDo() throws {
        var start = try makeWorld()
        try start.world.advance(ticks: 3)
        try start.world.unplaceTrain(start.x)
        var single = start.world
        for _ in 0..<10 { try single.advance(ticks: 1) }
        var batched = start.world
        try batched.advance(ticks: 10)
        XCTAssertEqual(batched, single)
    }
}
