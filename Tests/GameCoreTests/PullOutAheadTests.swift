import Foundation
@testable import GameCore
import XCTest

/// Decision 221's later fix: under traffic control a train leaving a depot
/// of a line with runs may take its route ahead of a train still far off
/// on its way along it; that train's reservation is cut back and it
/// follows (Stage U2).
///
/// A straight main line west to east: Alpha at the west end, the junction
/// J some 2.8 km on where the track out of the depot Yard joins from the
/// south-west, then Gamma, with a passing loop beside its platform. The
/// line Main from Alpha to Gamma has a run from Alpha at 06:00, due at
/// Gamma at 06:10, and one back from Gamma at 06:08, which the train on its
/// way from Alpha cannot make: so a train comes out of Yard for it while
/// the first is on its way, its route to Gamma holding J.
final class PullOutAheadTests: XCTestCase {
    private let alpha = StationID(rawValue: 1)
    private let gamma = StationID(rawValue: 2)
    private let yard = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let first = TrainID(rawValue: 1)
    private let fromYard = TrainID(rawValue: 2)
    /// The main line's height, and the edges of the track between Alpha and
    /// J, and between J and the loop.
    private let y: Int64 = 16_384
    private let toJunction = TrackEdgeID.edge(2)

    private func world(performance: TrainPerformance, trafficControl: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 212_992, height: 32_768), economy: GameEconomy(balance: 10_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 350), speed: .normal)
        )
        let points: [(Int64, Int64)] = [
            (2_048, y), (10_240, y), (180_224, y), (184_320, y), (200_704, y), (204_800, y),
            (188_416, y + 4_096), (196_608, y + 4_096), (163_840, y - 4_096),
        ]
        for (x, y) in points { _ = try world.buildTrackNode(at: WorldCoordinate(x: x, y: y)) }
        for edge in 1...5 { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        _ = try world.buildTrackEdge(from: .node(4), to: .node(7), curve: .cubic(.init(x: 186_368, y: y), .init(x: 186_368, y: y + 4_096)))
        _ = try world.buildTrackEdge(from: .node(7), to: .node(8))
        _ = try world.buildTrackEdge(from: .node(8), to: .node(5), curve: .cubic(.init(x: 198_656, y: y + 4_096), .init(x: 198_656, y: y)))
        _ = try world.buildTrackEdge(from: .node(9), to: .node(3), curve: .cubic(.init(x: 172_032, y: y - 4_096), .init(x: 172_032, y: y)))
        _ = try world.buildStation(named: "Alpha", at: PlanPoint(x: 6_144, y: y - 4_096))
        _ = try world.buildStation(named: "Gamma", at: PlanPoint(x: 192_512, y: y + 8_192))
        _ = try world.buildStation(named: "Yard", at: PlanPoint(x: 165_888, y: y - 8_192))
        try world.addTrackPlatform(alpha, on: .edge(1), from: 2_048, to: 8_192)
        try world.addTrackPlatform(gamma, on: .edge(4), from: 4_096, to: 12_288)
        try world.addTrackPlatform(gamma, on: .edge(7), from: 1_024, to: 7_168)
        try world.addTrackPlatform(yard, on: .edge(9), from: 1_024, to: 7_168)
        try world.setStationDepot(yard, to: true)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        func run(_ from: Int, _ to: Int, at minute: Int64) -> LineRun {
            LineRun(from: from, to: to, times: [minute, minute + 16].map { LineRunTime(arrival: $0 * 60, departure: $0 * 60) })
        }
        try world.setLineRuns(main, to: [run(0, 1, at: 360), run(1, 0, at: 374)])
        try world.setLineDepots(main, to: [yard])
        try world.setTrafficControl(trafficControl)
        let places: [(edge: TrackEdgeID, offset: Int64)] = [(.edge(1), 8_000), (.edge(9), 7_000)]
        for (index, place) in places.enumerated() {
            let train = try world.purchaseTrain(named: "T\(index + 1)")
            try world.placeTrain(train.id, at: .onEdge(TrackTraversal(edge: place.edge, direction: .forward), offset: place.offset))
            try world.setTrainContinuation(train.id, along: [], stoppingAt: place.offset)
            try world.setTrainMovementRate(train.id, to: 1024)
            try world.setTrainPerformance(train.id, to: performance)
            try world.assignTrain(train.id, to: main)
        }
        return world
    }

    /// Whether `train` is on its way between Alpha and J, or still at Alpha.
    private func isShortOfTheJunction(_ world: GameWorld, _ train: TrainID) -> Bool {
        world.occupiedResources(of: train).allSatisfy { resource in
            switch resource {
            case .span(let span): span.edge == .edge(1) || span.edge == toJunction
            case .node(let node): node == .node(1) || node == .node(2)
            }
        }
    }

    /// Runs `world` minute by minute to 06:20, checking the invariants
    /// every minute; returns the first minute at which the train out of
    /// Yard has left it, whether the first train was then still short of J,
    /// and whether the first train came to Gamma.
    private func pullOut(_ world: inout GameWorld) throws -> (minute: Int64, aheadOfTheFirst: Bool, firstAtGamma: Bool)? {
        var left: (Int64, Bool)?
        var firstAtGamma = false
        while world.clock.now < GameTime(minutes: 380) {
            try world.advance(ticks: 1)
            XCTAssertEqual(WorldInvariants.violations(in: world), [], "at \(world.clock.now.minute)")
            if left == nil, world.train(id: fromYard)?.isDeadheading == true, world.stationsStoppedAt(by: fromYard) != [yard],
               !world.occupiedResources(of: fromYard).isEmpty {
                left = (world.clock.now.minute, isShortOfTheJunction(world, first))
            }
            if world.stationsStoppedAt(by: first) == [gamma] { firstAtGamma = true }
        }
        return left.map { (minute: $0.0, aheadOfTheFirst: $0.1, firstAtGamma: firstAtGamma) }
    }

    /// With the first train some kilometres off, the train out of Yard
    /// goes ahead of it to the loop at Gamma; the first follows and comes
    /// to the main platform behind it.
    func testTheTrainOutOfTheDepotGoesAheadOfATrainFarOff() throws {
        var world = try world(performance: .standard)
        let left = try XCTUnwrap(try pullOut(&world), "it leaves Yard")
        XCTAssertTrue(left.aheadOfTheFirst, "the first train is still short of J when it leaves, at \(left.minute)")
        XCTAssertTrue(left.firstAtGamma, "the first train comes to Gamma behind it")
        XCTAssertEqual(world.line(id: main)?.runDays, [0, 0], "both runs leave")
    }

    /// Where the first train could not stop short of where the route out
    /// of Yard joins it (its braking distance, here a high-speed train's,
    /// is longer than its way there), the train out of Yard waits for it to
    /// pass, as before.
    func testItWaitsForATrainThatCouldNotStopInTime() throws {
        var world = try world(performance: .highSpeed)
        let left = try XCTUnwrap(try pullOut(&world), "it leaves Yard")
        XCTAssertFalse(left.aheadOfTheFirst, "it leaves only once the first train has passed J, at \(left.minute)")
        XCTAssertTrue(left.firstAtGamma)
    }

    /// One call for the whole hour ends exactly where minute by minute
    /// does.
    func testLongBatchesMatchSingleMinutes() throws {
        var batched = try world(performance: .standard)
        var single = batched
        try batched.advance(ticks: 60)
        for _ in 0..<60 { try single.advance(ticks: 1) }
        XCTAssertEqual(batched, single)
    }
}
