import Foundation
@testable import GameCore
import XCTest

/// Stage S4 (ARCHITECTURE decision 30): heights, grades, structures,
/// clearance, tunnels, platforms at several levels and the renderer
/// snapshot, with expected values worked out by hand from the rules.
final class VerticalRailwayTests: XCTestCase {
    private let first = TrainID(rawValue: 1)
    private let second = TrainID(rawValue: 2)

    /// A 32 × 32 map (32768 world units a side) running at 1×, with a large
    /// balance and track at 100 a tile.
    private func makeWorld() throws -> GameWorld {
        try GameWorld(
            width: 32, height: 32, economy: GameEconomy(balance: 100_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500)),
            clock: GameClock(speed: .normal)
        )
    }

    private func node(_ x: Int64, _ y: Int64, _ z: Int64 = 0, in world: inout GameWorld) throws -> TrackNodeID {
        try world.buildTrackNode(at: WorldCoordinate(x: x, y: y, z: z))
    }

    private func forward(_ edge: TrackEdgeID) -> TrackTraversal {
        TrackTraversal(edge: edge, direction: .forward)
    }

    private func backward(_ edge: TrackEdgeID) -> TrackTraversal {
        TrackTraversal(edge: edge, direction: .backward)
    }

    /// The span of `edge` from `start` to `end` (Stage S3A).
    private func span(_ edge: TrackEdgeID, _ start: Int64, _ end: Int64) -> TrackResource {
        .span(TrackSpan(edge: edge, start: start, end: end))
    }

    private func refused(_ expected: GameError, in world: GameWorld, file: StaticString = #filePath, line: UInt = #line, _ body: (inout GameWorld) throws -> Void) {
        var copy = world
        do {
            try body(&copy)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GameError, expected, file: file, line: line)
            XCTAssertEqual(copy, world, "a refused command changes nothing", file: file, line: line)
        }
    }

    // MARK: - The vertical profile

    func testAUniformRampClimbsAtOneGrade() throws {
        // 512 up over 12800: 1 in 25, exactly the steepest allowed.
        let ramp = try XCTUnwrap(TrackGeometry(from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 12_800, y: 0, z: 512), curve: .straight))
        XCTAssertEqual(ramp.length, 12_800, "the length is the horizontal chainage")
        // 512 × s / 12800, rounded halves up: 0.04 → 0, 0.48 → 0, 0.52 → 1.
        XCTAssertEqual([0, 1, 12, 13, 6_400, 12_800].map(ramp.height(at:)), [0, 0, 0, 1, 256, 512])
        XCTAssertEqual(ramp.grade(at: 5), TrackGrade(rise: 1, run: 25))
        XCTAssertEqual(ramp.steepestGrade, TrackGrade(rise: 40, run: 1_000))
        XCTAssertEqual(ramp.segments, [TrackProfileSegment(kind: .up, start: 0, end: 12_800)])
        XCTAssertEqual(ramp.points, [WorldCoordinate(x: 0, y: 0), WorldCoordinate(x: 12_800, y: 0, z: 512)])
        XCTAssertEqual(ramp.location(at: 6_400), TrackLocation(position: WorldCoordinate(x: 6_400, y: 0, z: 256), direction: PlanVector(dx: 12_800, dy: 0), grade: TrackGrade(rise: 1, run: 25)))
        // Going back down the same ramp, the grade is negative.
        XCTAssertEqual(ramp.location(at: 6_400, going: .backward).grade, TrackGrade(rise: -1, run: 25))

        // Falling the other way: −0.52 rounds up to −1... halves up, so
        // −0.48 → 0 and −0.52 → −1.
        let down = try XCTUnwrap(TrackGeometry(from: WorldCoordinate(x: 0, y: 0, z: 512), to: WorldCoordinate(x: 12_800, y: 0), curve: .straight))
        XCTAssertEqual([12, 13, 6_400].map(down.height(at:)), [512, 511, 256])
        XCTAssertEqual(down.segments, [TrackProfileSegment(kind: .down, start: 0, end: 12_800)])
        XCTAssertEqual(down.grade(at: 0), TrackGrade(rise: -1, run: 25))

        let level = try XCTUnwrap(TrackGeometry(from: WorldCoordinate(x: 0, y: 0, z: -512), to: WorldCoordinate(x: 3_000, y: 4_000, z: -512), curve: .straight))
        XCTAssertEqual(level.segments, [TrackProfileSegment(kind: .level, start: 0, end: 5_000)])
        XCTAssertEqual(level.steepestGrade, .level)
        XCTAssertEqual(level.location(at: 2_500).position, WorldCoordinate(x: 1_500, y: 2_000, z: -512))
    }

    func testVerticalCurvesEaseIntoAndOutOfTheGrade() throws {
        // 512 up over 16384 with vertical curves of 2048 at both ends:
        // D = 2 × 16384 − 4096 = 28672, the steady grade 1024 / 28672 = 1/28.
        let profile = TrackProfile(startTransition: 2_048, endTransition: 2_048)
        let edge = try XCTUnwrap(TrackGeometry(from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 16_384, y: 0, z: 512), curve: .straight, profile: profile))
        // 512 × 1024² / (2048 × 28672) = 9.14 → 9; at 2048, 512 × 2048 / 28672
        // = 36.57 → 37; the middle 256 exactly; 1024 from the end,
        // 512 × (2048 × 28672 − 1024²) / (2048 × 28672) = 502.86 → 503.
        XCTAssertEqual([0, 1_024, 2_048, 8_192, 15_360, 16_384].map(edge.height(at:)), [0, 9, 37, 256, 503, 512])
        XCTAssertEqual([0, 1_024, 2_048, 8_192, 15_360, 16_384].map(edge.grade(at:)), [
            .level, TrackGrade(rise: 1, run: 56), TrackGrade(rise: 1, run: 28), TrackGrade(rise: 1, run: 28), TrackGrade(rise: 1, run: 56), .level,
        ])
        XCTAssertEqual(edge.steepestGrade, TrackGrade(rise: 1, run: 28))
        XCTAssertEqual(edge.segments, [
            TrackProfileSegment(kind: .transition, start: 0, end: 2_048),
            TrackProfileSegment(kind: .up, start: 2_048, end: 14_336),
            TrackProfileSegment(kind: .transition, start: 14_336, end: 16_384),
        ])
        // Transitions filling the whole edge leave no steady stretch.
        let eased = try XCTUnwrap(TrackGeometry(
            from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 4_096, y: 0, z: 64), curve: .straight,
            profile: TrackProfile(startTransition: 2_048, endTransition: 2_048)
        ))
        XCTAssertEqual(eased.segments.map(\.kind), [.transition, .transition])
        XCTAssertEqual(eased.height(at: 2_048), 32)

        // Profiles that do not fit are no edge at all.
        let p = WorldCoordinate(x: 0, y: 0)
        let q = WorldCoordinate(x: 4_096, y: 0, z: 64)
        XCTAssertNil(TrackGeometry(from: p, to: q, curve: .straight, profile: TrackProfile(startTransition: -1)))
        XCTAssertNil(TrackGeometry(from: p, to: q, curve: .straight, profile: TrackProfile(startTransition: 2_048, endTransition: 2_049)))
        XCTAssertNil(TrackGeometry(from: p, to: WorldCoordinate(x: 4_096, y: 0), curve: .straight, profile: TrackProfile(endTransition: 1)), "a level edge has no vertical curve")
    }

    func testTheVerticalProfileNeverOverflows() throws {
        // A sloping edge rises at most 2^13 and is at most 2^24 long.
        XCTAssertNil(TrackGeometry(from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 1 << 24 + 1, y: 0, z: 1), curve: .straight))
        XCTAssertNil(TrackGeometry(from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 1 << 20, y: 0, z: 8_193), curve: .straight))
        XCTAssertNotNil(TrackGeometry(from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 1 << 25, y: 0), curve: .straight), "level edges keep Stage S3's range")
        // At both bounds, with the longest transitions, every product fits.
        let extreme = try XCTUnwrap(TrackGeometry(
            from: WorldCoordinate(x: 0, y: 0, z: -4_096), to: WorldCoordinate(x: 1 << 24, y: 0, z: 4_096), curve: .straight,
            profile: TrackProfile(startTransition: 1 << 23, endTransition: 1 << 23)
        ))
        XCTAssertEqual(extreme.height(at: 1 << 23), 0)
        XCTAssertEqual(extreme.height(at: 1 << 24), 4_096)
        XCTAssertEqual(extreme.height(at: (1 << 24) - 1), 4_096, "8192 / 2^48 of a unit below the top")
        XCTAssertEqual(extreme.grade(at: 1 << 23), TrackGrade(rise: 1, run: 1 << 10))
        // The 128-bit helpers and grade comparisons at the extremes.
        XCTAssertEqual(FixedPoint.roundedProduct(.max, times: .max, over: .max), .max)
        XCTAssertEqual(FixedPoint.roundedProduct(3, times: 1, over: 2), 2, "1.5 rounds up")
        XCTAssertEqual(FixedPoint.roundedProduct(1, times: 1, over: 3), 0)
        XCTAssertEqual(FixedPoint.roundedProduct(1 << 62, times: 6, over: 1 << 62), 6)
        XCTAssertFalse(TrackGrade(rise: .max, run: 1).isNoSteeper(than: TrackGrade(rise: .max - 1, run: 1)))
        XCTAssertTrue(TrackGrade(rise: -(.max), run: .max).isNoSteeper(than: TrackGrade(rise: 1, run: 1)))
        XCTAssertEqual(TrackGrade(rise: -40, run: 1_000), TrackGrade(rise: -1, run: 25))
        // A world's heights: 4096 above or below the ground.
        var world = try makeWorld()
        XCTAssertNoThrow(try node(0, 0, 4_096, in: &world))
        XCTAssertNoThrow(try node(0, 0, -4_096, in: &world))
        refused(.invalidTrackGeometry, in: world) { _ = try $0.buildTrackNode(at: WorldCoordinate(x: 0, y: 0, z: 4_097)) }
        refused(.invalidTrackGeometry, in: world) { _ = try $0.buildTrackNode(at: WorldCoordinate(x: 0, y: 0, z: -4_097)) }
    }

    // MARK: - Building

    func testRampsAreBuiltWithinTheMaximumGradeOnTheirStructures() throws {
        var world = try makeWorld()
        let balance = world.economy.balance
        let a = try node(2_048, 4_096, in: &world)
        let b = try node(14_848, 4_096, 512, in: &world)
        let up = try world.buildTrackEdge(from: a, to: b, structure: .elevated)
        // 12800 long: 13 tiles, at three times the price of surface track.
        XCTAssertEqual(world.economy.balance, balance - Money(13 * 100 * 3))
        XCTAssertEqual(world.trackEdge(up)?.structure, .elevated)
        let c = try node(27_648, 4_096, in: &world)
        let down = try world.buildTrackEdge(from: b, to: c, structure: .bridge)
        XCTAssertEqual(world.trackAlignment(of: down)?.segments.map(\.kind), [.down])
        XCTAssertEqual(world.economy.balance, balance - Money(13 * 100 * 3 + 13 * 100 * 4))
        // A train on the ramp faces up it, then down it.
        XCTAssertEqual(world.trackGeometry(of: up)?.location(at: 6_400).position.z, 256)

        // One unit more is too steep.
        let d = try node(2_048, 5_120, in: &world)
        let e = try node(14_848, 5_120, 513, in: &world)
        refused(.trackTooSteep, in: world) { _ = try $0.buildTrackEdge(from: d, to: e, structure: .elevated) }
        // Transitions steepen the steady grade: 4096 at each end makes it
        // 1024 / 24576 = 1/24, too steep; 2048 makes it 1/28.
        let f = try node(2_048, 6_144, in: &world)
        let g = try node(18_432, 6_144, 512, in: &world)
        refused(.trackTooSteep, in: world) {
            _ = try $0.buildTrackEdge(from: f, to: g, profile: TrackProfile(startTransition: 4_096, endTransition: 4_096), structure: .elevated)
        }
        let eased = try world.buildTrackEdge(from: f, to: g, profile: TrackProfile(startTransition: 2_048, endTransition: 2_048), structure: .elevated)
        XCTAssertEqual(world.trackAlignment(of: eased)?.steepestGrade, TrackGrade(rise: 1, run: 28))

        // Each structure carries track only at its heights.
        let h = try node(2_048, 8_192, in: &world)
        let i = try node(5_248, 8_192, 128, in: &world)
        let j = try node(8_448, 8_192, 129, in: &world)
        let k = try node(8_448, 9_216, -1, in: &world)
        XCTAssertNoThrow(try world.buildTrackEdge(from: h, to: i), "2 m up on an embankment, 1 in 25")
        refused(.invalidTrackStructure, in: world) { _ = try $0.buildTrackEdge(from: i, to: j) }
        refused(.invalidTrackStructure, in: world) { _ = try $0.buildTrackEdge(from: h, to: k, structure: .elevated) }
        refused(.invalidTrackStructure, in: world) { _ = try $0.buildTrackEdge(from: h, to: i, structure: .tunnel) }
        XCTAssertNoThrow(try world.buildTrackEdge(from: i, to: j, structure: .bridge))
        XCTAssertNoThrow(try world.buildTrackEdge(from: h, to: k, structure: .tunnel))

        // The order of refusals: geometry, grade, structure, clearance.
        refused(.invalidTrackGeometry, in: world) {
            _ = try $0.buildTrackEdge(from: d, to: e, profile: TrackProfile(startTransition: -5), structure: .tunnel)
        }
        refused(.trackTooSteep, in: world) { _ = try $0.buildTrackEdge(from: d, to: e, structure: .tunnel) }
        refused(.invalidTrackGeometry, in: world) {
            _ = try $0.buildTrackEdge(from: h, to: .node(1), profile: TrackProfile(startTransition: 1))
        }
    }

    // MARK: - Crossings

    func testTracksCrossOneOverTheOtherOrAtANodeTheyShare() throws {
        var world = try makeWorld()
        // North–south on the ground, crossed west–east at (8192, 8192).
        let n = try node(8_192, 2_048, in: &world)
        let s = try node(8_192, 14_336, in: &world)
        let ns = try world.buildTrackEdge(from: n, to: s)
        // At the same height: refused, naming the edge in the way.
        let w0 = try node(2_048, 8_192, in: &world)
        let e0 = try node(14_336, 8_192, in: &world)
        refused(.trackConflict(ns), in: world) { _ = try $0.buildTrackEdge(from: w0, to: e0) }
        // On an embankment at 128 or a viaduct at 511: not high enough.
        let w1 = try node(2_048, 8_192, 511, in: &world)
        let e1 = try node(14_336, 8_192, 511, in: &world)
        refused(.trackConflict(ns), in: world) { _ = try $0.buildTrackEdge(from: w1, to: e1, structure: .elevated) }
        // At 512, exactly the clearance: a grade-separated crossing.
        let w2 = try node(2_048, 8_192, 512, in: &world)
        let e2 = try node(14_336, 8_192, 512, in: &world)
        let over = try world.buildTrackEdge(from: w2, to: e2, structure: .elevated)
        // And a tunnel 512 under the surface, 1024 under the viaduct.
        let w3 = try node(2_048, 8_192, -512, in: &world)
        let e3 = try node(14_336, 8_192, -512, in: &world)
        let under = try world.buildTrackEdge(from: w3, to: e3, structure: .tunnel)
        // Along the same line as the first viaduct, 256 above it: refused;
        // 512 above it: a second deck.
        let w5 = try node(2_048, 8_192, 768, in: &world)
        let e5 = try node(14_336, 8_192, 768, in: &world)
        refused(.trackConflict(over), in: world) { _ = try $0.buildTrackEdge(from: w5, to: e5, structure: .elevated) }
        let w4 = try node(2_048, 8_192, 1_024, in: &world)
        let e4 = try node(14_336, 8_192, 1_024, in: &world)
        XCTAssertNoThrow(try world.buildTrackEdge(from: w4, to: e4, structure: .elevated))

        // Nothing joins, nothing is shared: trains at the crossing point on
        // all three levels occupy only their own edges. Each edge (12288) is
        // 12 spans of 1024; a train 1024 long from 5120 to 6144 fills one and
        // touches the two beside it.
        XCTAssertEqual(world.transitions(after: forward(over)), [])
        for (k, edge) in [ns, over, under].enumerated() {
            try world.purchaseTrain(named: "T\(k)")
            let id = TrainID(rawValue: k + 1)
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(forward(edge), offset: 6_144))
            XCTAssertEqual(world.occupiedResources(of: id), [span(edge, 4_096, 5_120), span(edge, 5_120, 6_144), span(edge, 6_144, 7_168)])
        }
        XCTAssertEqual(world.occupancyConflicts(), [])
        XCTAssertNil(world.route(from: .onEdge(forward(over), offset: 6_144), to: s))
        XCTAssertEqual(world.location(of: world.train(id: TrainID(rawValue: 2))!.position!)?.position, WorldCoordinate(x: 8_192, y: 8_192, z: 512))
        XCTAssertEqual(world.location(of: world.train(id: TrainID(rawValue: 3))!.position!)?.position, WorldCoordinate(x: 8_192, y: 8_192, z: -512))

        // A real level crossing is a node both lines end at: the resource
        // two trains share, as in Stage S1.
        let x = try node(20_480, 20_480, in: &world)
        let wx = try node(16_384, 20_480, in: &world)
        let ex = try node(24_576, 20_480, in: &world)
        let nx = try node(20_480, 16_384, in: &world)
        let sx = try node(20_480, 24_576, in: &world)
        let west = try world.buildTrackEdge(from: wx, to: x)
        let east = try world.buildTrackEdge(from: x, to: ex)
        let north = try world.buildTrackEdge(from: nx, to: x)
        let south = try world.buildTrackEdge(from: x, to: sx)
        XCTAssertEqual(world.transitions(after: forward(west)), [forward(east)])
        XCTAssertEqual(world.transitions(after: forward(north)), [forward(south)])
        try world.purchaseTrain(named: "Across")
        try world.purchaseTrain(named: "Down")
        try world.placeTrain(TrainID(rawValue: 4), at: .onEdge(forward(west), offset: 4_096))
        try world.placeTrain(TrainID(rawValue: 5), at: .onEdge(forward(north), offset: 4_096))
        XCTAssertEqual(world.occupancyConflicts(), [TrackConflict(resource: .node(x), trains: [TrainID(rawValue: 4), TrainID(rawValue: 5)])])
    }

    func testARampOverATunnelIsCheckedWhereTheyCross() throws {
        var world = try makeWorld()
        // A tunnel north–south at −512; a ramp from the ground up to 512
        // crosses it 6144 along, at 512 × 6144 / 12800 = 245.76 → 246.
        let n = try node(8_192, 1_024, -512, in: &world)
        let s = try node(8_192, 13_312, -512, in: &world)
        let tunnel = try world.buildTrackEdge(from: n, to: s, structure: .tunnel)
        let a = try node(2_048, 4_096, in: &world)
        let b = try node(14_848, 4_096, 512, in: &world)
        let ramp = try world.buildTrackEdge(from: a, to: b, structure: .elevated)
        XCTAssertEqual(world.trackGeometry(of: ramp)?.height(at: 6_144), 246, "758 above the tunnel")
        // A second tunnel at −200 crosses the ramp 7168 along, where it is at
        // 512 × 7168 / 12800 = 286.72 → 287: only 487 above.
        let n2 = try node(9_216, 1_024, -200, in: &world)
        let s2 = try node(9_216, 13_312, -200, in: &world)
        refused(.trackConflict(ramp), in: world) { _ = try $0.buildTrackEdge(from: n2, to: s2, structure: .tunnel) }
        // At −300 it is 587 below: clear, and it never meets the first tunnel.
        let n3 = try node(9_216, 1_024, -300, in: &world)
        let s3 = try node(9_216, 13_312, -300, in: &world)
        XCTAssertNoThrow(try world.buildTrackEdge(from: n3, to: s3, structure: .tunnel))
        XCTAssertEqual(world.trackEdge(tunnel)?.structure, .tunnel)
    }

    func testEdgesMeetingAtANodeMayTouchOnlyNearIt() throws {
        var world = try makeWorld()
        // Two straight edges between the same two nodes 4096 apart lie on
        // one line beyond the 1024 next to each node: refused.
        let a = try node(2_048, 2_048, in: &world)
        let b = try node(6_144, 2_048, in: &world)
        let ab = try world.buildTrackEdge(from: a, to: b)
        refused(.trackConflict(ab), in: world) { _ = try $0.buildTrackEdge(from: a, to: b) }
        // 2048 apart, every point is within 1024 of a node they share: the
        // stretch a turnout and its clearance take.
        let c = try node(2_048, 3_072, in: &world)
        let d = try node(4_096, 3_072, in: &world)
        _ = try world.buildTrackEdge(from: c, to: d)
        XCTAssertNoThrow(try world.buildTrackEdge(from: c, to: d))

        // A branch that leaves the points tangent to the straight, touching
        // it at first when sampled, is fine; one that swings back across the
        // straight far from the points is not.
        let p = try node(2_048, 16_384, in: &world)
        let q = try node(10_240, 16_384, in: &world)
        let straight = try world.buildTrackEdge(from: p, to: q)
        let r = try node(10_240, 18_432, in: &world)
        XCTAssertNoThrow(try world.buildTrackEdge(from: p, to: r, curve: .cubic(PlanPoint(x: 4_096, y: 16_384), PlanPoint(x: 8_192, y: 18_432))))
        let t = try node(10_240, 19_456, in: &world)
        refused(.trackConflict(straight), in: world) {
            _ = try $0.buildTrackEdge(from: p, to: t, curve: .cubic(PlanPoint(x: 4_096, y: 16_384), PlanPoint(x: 6_144, y: 12_288)))
        }
        // An edge ending on another edge without a node there meets it.
        let u = try node(6_144, 16_384, in: &world)
        let v = try node(6_144, 14_336, in: &world)
        refused(.trackConflict(straight), in: world) { _ = try $0.buildTrackEdge(from: v, to: u) }
    }

    // MARK: - Tunnels and trains in 3D

    /// A level approach S (2048 → 6144 along y = 12288), a tunnel T falling
    /// 512 over 12800 from its portal Q, and a level tunnel V beyond.
    private func makeTunnel() throws -> (GameWorld, s: TrackEdgeID, t: TrackEdgeID, v: TrackEdgeID, portal: TrackNodeID) {
        var world = try makeWorld()
        let start = try node(2_048, 12_288, in: &world)
        let portal = try node(6_144, 12_288, in: &world)
        let deep = try node(18_944, 12_288, -512, in: &world)
        let end = try node(26_112, 12_288, -512, in: &world)
        let s = try world.buildTrackEdge(from: start, to: portal)
        let t = try world.buildTrackEdge(from: portal, to: deep, structure: .tunnel)
        let v = try world.buildTrackEdge(from: deep, to: end, structure: .tunnel)
        return (world, s, t, v, portal)
    }

    func testATrainRunsThroughATunnelPortalHalfUnderground() throws {
        let (tunnelWorld, s, t, v, portal) = try makeTunnel()
        var world = tunnelWorld
        XCTAssertTrue(world.isTunnelPortal(portal))
        XCTAssertFalse(world.isTunnelPortal(.node(3)), "tunnel on both sides")
        XCTAssertFalse(world.isTunnelPortal(.node(1)))
        XCTAssertEqual(world.transitions(after: forward(s)), [forward(t)], "a portal is an ordinary node")
        try world.purchaseTrain(named: "Mole")
        try world.setTrainCars(first, to: 3)
        // Head 1024 into the tunnel, at −512 × 1024 / 12800 = −40.96 → −41;
        // its body back over the portal and 1024 of the approach.
        try world.placeTrain(first, at: .onEdge(forward(t), offset: 1_024))
        XCTAssertEqual(world.train(id: first)?.trailEdges, [s])
        // The approach (4096) is 4 spans; the tunnel (12800) 13, with
        // boundaries at ⌊k × 12800 ÷ 13⌋: 984, 1969, 2953, 3938 and on. The
        // body covers 3072 to 4096 of the approach, touching 3072.
        XCTAssertEqual(world.occupiedResources(of: first), [
            .node(portal), span(s, 2_048, 3_072), span(s, 3_072, 4_096), span(t, 0, 984), span(t, 984, 1_969),
        ])
        XCTAssertEqual(world.bodyPath(of: first), [
            WorldCoordinate(x: 7_168, y: 12_288, z: -41), WorldCoordinate(x: 6_144, y: 12_288), WorldCoordinate(x: 5_120, y: 12_288),
        ])
        XCTAssertEqual(world.location(of: world.train(id: first)!.position!)?.grade, TrackGrade(rise: -1, run: 25))
        XCTAssertEqual(world.route(from: world.train(id: first)!.position!, to: .node(4)), [forward(v)])

        // It runs on at 1000 a minute: 3024 along after two minutes (at
        // −512 × 3024 / 12800 = −120.96 → −121), its body wholly in the
        // tunnel.
        try world.setTrainContinuation(first, along: [forward(v)])
        try world.setTrainMovementRate(first, to: 1_000)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(forward(t), offset: 3_024))
        XCTAssertEqual(world.train(id: first)?.trailEdges, [])
        XCTAssertEqual(world.bodyPath(of: first).first, WorldCoordinate(x: 9_168, y: 12_288, z: -121))
        XCTAssertEqual(world.occupiedResources(of: first), [span(t, 0, 984), span(t, 984, 1_969), span(t, 1_969, 2_953), span(t, 2_953, 3_938)], "976 to 3024, wholly underground")

        // Turning round on the slope: the head goes to where the tail was,
        // now facing up toward the portal; twice restores it.
        let before = try XCTUnwrap(world.train(id: first))
        try world.setTrainContinuation(first, along: [])
        try world.reverseTrain(first)
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(backward(t), offset: 12_800 - 3_024 + 2_048))
        XCTAssertEqual(world.location(of: world.train(id: first)!.position!)?.grade, TrackGrade(rise: 1, run: 25))
        try world.reverseTrain(first)
        XCTAssertEqual(world.train(id: first)?.position, before.position)
        XCTAssertEqual(world.train(id: first)?.trailEdges, before.trailEdges)
    }

    func testALongTrainStandsHalfOnARampAndTurnsRoundOnIt() throws {
        var world = try makeWorld()
        // A level approach, then the eased ramp of 16384 up to 512.
        let o = try node(0, 20_480, in: &world)
        let a = try node(2_048, 20_480, in: &world)
        let b = try node(18_432, 20_480, 512, in: &world)
        let approach = try world.buildTrackEdge(from: o, to: a)
        let ramp = try world.buildTrackEdge(from: a, to: b, profile: TrackProfile(startTransition: 2_048, endTransition: 2_048), structure: .elevated)
        try world.purchaseTrain(named: "Climber")
        try world.setTrainCars(first, to: 3)
        try world.placeTrain(first, at: .onEdge(forward(ramp), offset: 1_024))
        XCTAssertEqual(world.bodyPath(of: first), [
            WorldCoordinate(x: 3_072, y: 20_480, z: 9), WorldCoordinate(x: 2_048, y: 20_480), WorldCoordinate(x: 1_024, y: 20_480),
        ])
        XCTAssertEqual(world.location(of: world.train(id: first)!.position!)?.grade, TrackGrade(rise: 1, run: 56))
        // 1024 to 2048 of the approach and 0 to 1024 of the ramp, spans of
        // 1024 each, touching the boundaries at 1024 on both.
        XCTAssertEqual(world.occupiedResources(of: first), [
            .node(a), span(approach, 0, 1_024), span(approach, 1_024, 2_048), span(ramp, 0, 1_024), span(ramp, 1_024, 2_048),
        ])
        // Turned round, its head is 1024 along the approach going west, and
        // its body lies back up the ramp.
        try world.reverseTrain(first)
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(backward(approach), offset: 1_024))
        XCTAssertEqual(world.train(id: first)?.trailEdges, [ramp])
        XCTAssertEqual(world.bodyPath(of: first), [
            WorldCoordinate(x: 1_024, y: 20_480), WorldCoordinate(x: 2_048, y: 20_480), WorldCoordinate(x: 3_072, y: 20_480, z: 9),
        ])
        try world.reverseTrain(first)
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(forward(ramp), offset: 1_024))
        XCTAssertEqual(world.train(id: first)?.trailEdges, [approach])
    }

    // MARK: - Platforms at several levels

    /// Station "Hub" on tile (1, 1) and "Annex" on (3, 1); a level surface
    /// edge, a level viaduct at 512, a level tunnel at −512 (each 8192
    /// long) and a ramp.
    private func makeStations() throws -> (GameWorld, surface: TrackEdgeID, viaduct: TrackEdgeID, tunnel: TrackEdgeID, ramp: TrackEdgeID) {
        var world = try makeWorld()
        try world.buildStation(named: "Hub", at: GridPosition(x: 1, y: 1))
        try world.buildStation(named: "Annex", at: GridPosition(x: 3, y: 1))
        let nodes = try [
            (2_048, 20_480, 0), (10_240, 20_480, 0), (2_048, 22_528, 512), (10_240, 22_528, 512),
            (2_048, 24_576, -512), (10_240, 24_576, -512), (23_040, 20_480, 512),
        ].map { try node($0.0, $0.1, $0.2, in: &world) }
        let surface = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        let viaduct = try world.buildTrackEdge(from: nodes[2], to: nodes[3], structure: .elevated)
        let tunnel = try world.buildTrackEdge(from: nodes[4], to: nodes[5], structure: .tunnel)
        let ramp = try world.buildTrackEdge(from: nodes[1], to: nodes[6], structure: .elevated)
        return (world, surface, viaduct, tunnel, ramp)
    }

    func testAStationHasPlatformsOnSeveralLevels() throws {
        let (stationWorld, surface, viaduct, tunnel, ramp) = try makeStations()
        var world = stationWorld
        let hub = StationID(rawValue: 1)
        let annex = StationID(rawValue: 2)
        try world.addTrackPlatform(hub, on: tunnel, from: 2_048, to: 6_144)
        try world.addTrackPlatform(hub, on: surface, from: 1_024, to: 5_120)
        try world.addTrackPlatform(hub, on: viaduct, from: 1_024, to: 5_120)
        // Kept by the railway network, in order along the track.
        XCTAssertEqual(world.trackPlatforms(of: hub), [
            TrackPlatform(station: hub, edge: surface, start: 1_024, end: 5_120), TrackPlatform(station: hub, edge: viaduct, start: 1_024, end: 5_120),
            TrackPlatform(station: hub, edge: tunnel, start: 2_048, end: 6_144),
        ])
        XCTAssertEqual(world.network.platforms, world.trackPlatforms(of: hub))
        XCTAssertEqual(world.trackPlatforms(of: annex), [])
        // Touching the end of another platform is fine; overlapping is not.
        try world.addTrackPlatform(annex, on: surface, from: 5_120, to: 7_168)
        refused(.invalidPlatform, in: world) { try $0.addTrackPlatform(annex, on: surface, from: 5_000, to: 5_200) }
        refused(.invalidPlatform, in: world) { try $0.addTrackPlatform(annex, on: viaduct, from: 0, to: 1_025) }
        // Within the edge, a stretch of positive length, level.
        refused(.invalidPlatform, in: world) { try $0.addTrackPlatform(annex, on: viaduct, from: 7_000, to: 8_193) }
        refused(.invalidPlatform, in: world) { try $0.addTrackPlatform(annex, on: viaduct, from: -1, to: 500) }
        refused(.invalidPlatform, in: world) { try $0.addTrackPlatform(annex, on: viaduct, from: 6_000, to: 6_000) }
        refused(.invalidPlatform, in: world) { try $0.addTrackPlatform(annex, on: ramp, from: 0, to: 1_024) }
        // The order of refusals.
        refused(.unknownStation(StationID(rawValue: 9)), in: world) { try $0.addTrackPlatform(StationID(rawValue: 9), on: .edge(99), from: 0, to: -1) }
        refused(.unknownTrackEdge(.edge(99)), in: world) { try $0.addTrackPlatform(annex, on: .edge(99), from: 0, to: -1) }
        let link = TrackEdgeID.link(GridPosition(x: 0, y: 0), GridPosition(x: 1, y: 0))
        refused(.unknownTrackEdge(link), in: world) { try $0.addTrackPlatform(annex, on: link, from: 0, to: 100) }
        // An edge with a platform stays until the platform goes.
        refused(.trackEdgeHasPlatform(surface), in: world) { try $0.removeTrackEdge(surface) }

        // Each platform's level comes from its edge.
        let levels = world.railwaySnapshot().platforms.filter { $0.platform.station == hub }.map { ($0.height, $0.structure) }
        XCTAssertEqual(levels.map(\.0), [0, 512, -512])
        XCTAssertEqual(levels.map(\.1), [.surface, .elevated, .tunnel])
        XCTAssertEqual(world.railwaySnapshot().platforms.first?.points, [WorldCoordinate(x: 3_072, y: 20_480), WorldCoordinate(x: 7_168, y: 20_480)])

        // A whole train along the tunnel platform, either way.
        try world.purchaseTrain(named: "Deep")
        try world.setTrainCars(first, to: 2)
        try world.placeTrain(first, at: .onEdge(forward(tunnel), offset: 4_096))
        XCTAssertEqual(world.trackPlatformsAlongWholeTrain(first), [TrackPlatform(station: hub, edge: tunnel, start: 2_048, end: 6_144)])
        try world.unplaceTrain(first)
        try world.placeTrain(first, at: .onEdge(backward(tunnel), offset: 3_072))
        XCTAssertEqual(world.trackPlatformsAlongWholeTrain(first).map(\.station), [hub], "from 5120 back to 6144: the far end, exactly")
        try world.unplaceTrain(first)
        try world.placeTrain(first, at: .onEdge(backward(tunnel), offset: 3_071))
        XCTAssertEqual(world.trackPlatformsAlongWholeTrain(first), [], "its tail is 1 past the platform")
        XCTAssertEqual(world.stationsBesideWholeTrain(first), [], "the grid's platforms are the grid's")

        // Removing platforms.
        refused(.invalidPlatform, in: world) { try $0.removeTrackPlatform(hub, on: surface, from: 1_025) }
        refused(.unknownStation(StationID(rawValue: 9)), in: world) { try $0.removeTrackPlatform(StationID(rawValue: 9), on: surface, from: 1_024) }
        try world.removeTrackPlatform(hub, on: surface, from: 1_024)
        try world.removeTrackPlatform(annex, on: surface, from: 5_120)
        XCTAssertNoThrow(try world.removeTrackEdge(surface))
    }

    func testPlatformEndsCutTheEdgesSpans() throws {
        let (stationWorld, _, _, tunnel, _) = try makeStations()
        var world = stationWorld
        let hub = StationID(rawValue: 1)
        // The tunnel (8192) is 8 spans of 1024; a platform from 2500 to 6000
        // cuts it there too.
        try world.addTrackPlatform(hub, on: tunnel, from: 2_500, to: 6_000)
        XCTAssertEqual(world.trackSpans(of: tunnel).map(\.end), [1_024, 2_048, 2_500, 3_072, 4_096, 5_120, 6_000, 6_144, 7_168, 8_192])
        // A train of two cars (1024) from 4876 to 5900, wholly along the
        // platform, holds only spans within it.
        try world.purchaseTrain(named: "Deep")
        try world.setTrainCars(first, to: 2)
        try world.placeTrain(first, at: .onEdge(forward(tunnel), offset: 5_900))
        XCTAssertEqual(world.trackPlatformsAlongWholeTrain(first), [TrackPlatform(station: hub, edge: tunnel, start: 2_500, end: 6_000)])
        XCTAssertEqual(world.occupiedResources(of: first), [span(tunnel, 4_096, 5_120), span(tunnel, 5_120, 6_000)])
        // Without the platform the edge is in equal parts again, and the
        // same train holds 5120 to 6144.
        try world.removeTrackPlatform(hub, on: tunnel, from: 2_500)
        XCTAssertEqual(world.trackSpans(of: tunnel).map(\.end), [1_024, 2_048, 3_072, 4_096, 5_120, 6_144, 7_168, 8_192])
        XCTAssertEqual(world.occupiedResources(of: first), [span(tunnel, 4_096, 5_120), span(tunnel, 5_120, 6_144)])
    }

    // MARK: - Saves

    func testThreeDimensionalWorldsSurviveASaveExactly() throws {
        let (stationWorld, surface, viaduct, tunnel, _) = try makeStations()
        var world = stationWorld
        try world.addTrackPlatform(StationID(rawValue: 1), on: tunnel, from: 2_048, to: 6_144)
        let low = try node(2_048, 30_720, in: &world)
        let high = try node(18_432, 30_720, 512, in: &world)
        let eased = try world.buildTrackEdge(from: low, to: high, profile: TrackProfile(startTransition: 2_048, endTransition: 1_024), structure: .bridge)
        try world.purchaseTrain(named: "A")
        try world.setTrainCars(first, to: 3)
        try world.placeTrain(first, at: .onEdge(forward(eased), offset: 3_000))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(world)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try encoder.encode(loaded), data)
        XCTAssertEqual(loaded.railwaySnapshot(), world.railwaySnapshot())

        // New keys only where used: a profile with transitions, a structure
        // that is not surface, a station with platforms.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let edges = try XCTUnwrap((object["network"] as? [String: Any])?["edges"] as? [[String: Any]])
        XCTAssertNil(edges[surface.number - 1]["structure"])
        XCTAssertNil(edges[surface.number - 1]["profile"])
        XCTAssertEqual(edges[viaduct.number - 1]["structure"] as? String, "elevated")
        let profile = try XCTUnwrap(edges[eased.number - 1]["profile"] as? [String: Any])
        XCTAssertEqual(profile["startTransition"] as? Int, 2_048)
        XCTAssertEqual(profile["endTransition"] as? Int, 1_024)
        // Platforms are the railway network's, not the stations'.
        let platforms = try XCTUnwrap((object["network"] as? [String: Any])?["platforms"] as? [[String: Any]])
        XCTAssertEqual(platforms.count, 1)
        XCTAssertEqual(platforms[0]["station"] as? Int, 1)
        let stations = try XCTUnwrap(object["stations"] as? [[String: Any]])
        XCTAssertTrue(stations.allSatisfy { $0["trackPlatforms"] == nil && $0["platforms"] == nil })

        // A Stage S3 save (no heights, profiles or structures) reads as
        // level surface track, and is written back unchanged.
        var flat = try makeWorld()
        let p = try node(1_024, 1_024, in: &flat)
        let q = try node(5_120, 1_024, in: &flat)
        _ = try flat.buildTrackEdge(from: p, to: q, curve: .cubic(PlanPoint(x: 2_048, y: 2_048), PlanPoint(x: 4_096, y: 0)))
        let flatData = try encoder.encode(flat)
        let s3 = String(decoding: flatData, as: UTF8.self)
        XCTAssertFalse(s3.contains("profile") || s3.contains("structure") || s3.contains("platforms"))
        XCTAssertEqual(try encoder.encode(JSONDecoder().decode(GameWorld.self, from: flatData)), flatData)
    }

    func testMalformedThreeDimensionalSavesAreRefusedNotRepaired() throws {
        let (stationWorld, _, _, tunnel, _) = try makeStations()
        var world = stationWorld
        try world.addTrackPlatform(StationID(rawValue: 1), on: tunnel, from: 2_048, to: 6_144)
        // A viaduct (nodes 8 and 9, edge 5) over a surface line (nodes 10
        // and 11, edge 6).
        let top = try node(16_384, 2_048, 512, in: &world)
        let bottom = try node(16_384, 10_240, 512, in: &world)
        let over = try world.buildTrackEdge(from: top, to: bottom, structure: .elevated)
        let west = try node(12_288, 6_144, in: &world)
        let east = try node(20_480, 6_144, in: &world)
        _ = try world.buildTrackEdge(from: west, to: east)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let good = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(world)) as? [String: Any])
        XCTAssertNoThrow(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: good)))
        func refused(_ change: (inout [String: Any]) -> Void, _ reason: String, file: StaticString = #filePath, line: UInt = #line) {
            var object = good
            change(&object)
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return XCTFail("not JSON", file: file, line: line) }
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: data), reason, file: file, line: line)
        }
        func network(_ key: String, _ index: Int, _ field: String, _ value: Any) -> (inout [String: Any]) -> Void {
            { object in
                var network = object["network"] as! [String: Any]
                var list = network[key] as! [[String: Any]]
                list[index][field] = value
                network[key] = list
                object["network"] = network
            }
        }
        func platforms(_ value: Any) -> (inout [String: Any]) -> Void {
            { object in
                var network = object["network"] as! [String: Any]
                network["platforms"] = value
                object["network"] = network
            }
        }
        let platform: [String: Any] = ["station": 1, "edge": tunnel.number, "start": 2_048, "end": 6_144]
        refused(network("nodes", 0, "z", 4_097), "beyond the heights track may have")
        refused(network("edges", 0, "structure", "floating"), "an unknown structure")
        refused(network("edges", 0, "structure", NSNull()), "an explicit null structure")
        refused(network("edges", 0, "profile", NSNull()), "an explicit null profile")
        refused(network("edges", 0, "profile", ["startTransition": 1, "endTransition": 0]), "a vertical curve on a level edge")
        refused(network("edges", 3, "profile", ["startTransition": -1, "endTransition": 0]), "a negative transition")
        refused(network("edges", 3, "profile", ["startTransition": 12_800, "endTransition": 1]), "transitions longer than the edge")
        refused(network("nodes", 8, "z", 4_000), "too steep")
        refused(network("edges", 2, "structure", "surface"), "a tunnel's heights on the surface")
        refused(network("edges", 1, "structure", "tunnel"), "a viaduct's heights underground")
        refused(network("edges", over.number - 1, "structure", "tunnel"), "the viaduct as a tunnel above ground")
        refused({ object in
            // The line raised onto a viaduct of its own at 256: only 256
            // under the other.
            network("nodes", 9, "z", 256)(&object)
            network("nodes", 10, "z", 256)(&object)
            network("edges", 5, "structure", "elevated")(&object)
        }, "two viaducts crossing 256 apart")
        refused(platforms(NSNull()), "explicit null platforms")
        refused(platforms([["station": 1, "edge": tunnel.number, "start": 2_048, "end": 9_000]]), "a platform beyond its edge")
        refused(platforms([["station": 1, "edge": 4, "start": 0, "end": 1_000]]), "a platform on a ramp")
        refused(platforms([["station": 1, "edge": 99, "start": 0, "end": 1_000]]), "a platform on an unknown edge")
        refused(platforms([["station": 1, "edge": 0, "start": 0, "end": 1_000]]), "edge 0")
        refused(platforms([["station": 9, "edge": tunnel.number, "start": 2_048, "end": 6_144]]), "a platform of an unknown station")
        refused(platforms([["edge": tunnel.number, "start": 2_048, "end": 6_144]]), "a platform of no station")
        refused(platforms([platform, platform]), "the same platform twice")
        refused(platforms([["station": 1, "edge": tunnel.number, "start": 3_000, "end": 4_000], platform]), "overlapping, and out of order")
        refused(platforms([platform, ["station": 2, "edge": tunnel.number, "start": 6_000, "end": 7_000]]), "another station's platform overlapping")
    }

    // MARK: - The renderer snapshot

    func testTheSnapshotHoldsEverythingARendererNeeds() throws {
        let (tunnelWorld, s, t, _, portal) = try makeTunnel()
        var world = tunnelWorld
        try world.buildStation(named: "Pit", at: GridPosition(x: 0, y: 0))
        try world.addTrackPlatform(StationID(rawValue: 1), on: .edge(3), from: 1_024, to: 3_072)
        try world.purchaseTrain(named: "Mole")
        try world.setTrainCars(first, to: 3)
        try world.placeTrain(first, at: .onEdge(forward(t), offset: 1_024))
        try world.purchaseTrain(named: "Waiting")
        let snapshot = world.railwaySnapshot()
        XCTAssertEqual(snapshot.nodes.map(\.id), [.node(1), .node(2), .node(3), .node(4)])
        XCTAssertEqual(snapshot.nodes.filter(\.isTunnelPortal).map(\.id), [portal])
        XCTAssertEqual(snapshot.edges.map(\.edge.id), [s, t, .edge(3)])
        XCTAssertEqual(snapshot.edges.map(\.edge.structure), [.surface, .tunnel, .tunnel])
        XCTAssertEqual(snapshot.edges[1].segments, [TrackProfileSegment(kind: .down, start: 0, end: 12_800)])
        XCTAssertEqual(snapshot.edges[1].steepestGrade, TrackGrade(rise: -1, run: 25))
        XCTAssertEqual(snapshot.edges[1].geometry.points.map(\.z), [0, -512])
        XCTAssertEqual(snapshot.platforms.map(\.height), [-512])
        XCTAssertEqual(snapshot.platforms.first?.points, [WorldCoordinate(x: 19_968, y: 12_288, z: -512), WorldCoordinate(x: 22_016, y: 12_288, z: -512)])
        XCTAssertEqual(snapshot.trains.map(\.id), [first], "an unplaced train is left out")
        XCTAssertEqual(snapshot.trains.first?.head, TrackLocation(
            position: WorldCoordinate(x: 7_168, y: 12_288, z: -41), direction: PlanVector(dx: 12_800, dy: 0), grade: TrackGrade(rise: -1, run: 25)
        ))
        XCTAssertEqual(snapshot.trains.first?.body, world.bodyPath(of: first))
        // The grid is still there for renderers, one link at a time.
        try world.buildTrack(at: GridPosition(x: 5, y: 5), connections: [.east])
        try world.buildTrack(at: GridPosition(x: 6, y: 5), connections: [.west])
        let link = TrackEdgeID.link(between: GridPosition(x: 5, y: 5), and: GridPosition(x: 6, y: 5))
        XCTAssertEqual(world.trackAlignment(of: link)?.edge.structure, .surface)
        XCTAssertEqual(world.trackAlignment(of: link)?.segments, [TrackProfileSegment(kind: .level, start: 0, end: 1_024)])
        XCTAssertNil(world.trackAlignment(of: .edge(99)))
        // Deterministic: the same commands give the same snapshot.
        XCTAssertEqual(try makeTunnel().0.railwaySnapshot(), try makeTunnel().0.railwaySnapshot())
    }
}
