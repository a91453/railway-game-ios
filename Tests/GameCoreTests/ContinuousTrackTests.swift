import Foundation
@testable import GameCore
import XCTest

/// Stage S3 (ARCHITECTURE decision 29): the continuous track network, with
/// expected values worked out by hand from the rules.
final class ContinuousTrackTests: XCTestCase {
    private let first = TrainID(rawValue: 1)
    private let second = TrainID(rawValue: 2)

    /// A 16 × 16 map (16384 world units a side) running at 1×, with a large
    /// balance and track at 100 a tile.
    private func makeWorld() throws -> GameWorld {
        try GameWorld(
            width: 16, height: 16, economy: GameEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500)),
            clock: GameClock(speed: .normal)
        )
    }

    private func node(_ x: Int64, _ y: Int64, in world: inout GameWorld) throws -> TrackNodeID {
        try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
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

    // MARK: - Geometry

    func testAStraightEdgeRunsAtAnyHeadingWithAnExactIntegerLength() throws {
        var world = try makeWorld()
        let a = try node(512, 512, in: &world)
        let b = try node(3_584, 4_608, in: &world)
        let c = try node(1_024, 8_192, in: &world)
        let d = try node(2_048, 9_216, in: &world)
        // 3072 east and 4096 south: 5120 exactly.
        let ab = try world.buildTrackEdge(from: a, to: b)
        XCTAssertEqual(ab, .edge(1))
        XCTAssertEqual(world.trackEdge(ab)?.length, 5_120)
        // 45 degrees: √(2 × 1024²) = 1448.15..., rounded to 1448.
        let cd = try world.buildTrackEdge(from: c, to: d)
        XCTAssertEqual(world.trackEdge(cd)?.length, 1_448)
        // Five tiles of track, then two (1448 rounds up to two tiles).
        XCTAssertEqual(world.economy.balance, Money(1_000_000 - 500 - 200))

        let geometry = try XCTUnwrap(world.trackGeometry(of: ab))
        XCTAssertEqual(geometry.points, [WorldCoordinate(x: 512, y: 512), WorldCoordinate(x: 3_584, y: 4_608)])
        XCTAssertEqual(geometry.distances, [0, 5_120])
        // A fifth of the way: 614.4 east and 819.2 south, rounded.
        XCTAssertEqual(geometry.location(at: 1_024), TrackLocation(position: WorldCoordinate(x: 1_126, y: 1_331), direction: PlanVector(dx: 3_072, dy: 4_096)))
        XCTAssertEqual(geometry.location(at: 5_120).position, WorldCoordinate(x: 3_584, y: 4_608))
        XCTAssertEqual(geometry.location(at: 1_024, going: .backward).position, WorldCoordinate(x: 2_970, y: 3_789), "measured from the to end")
        XCTAssertEqual(geometry.location(at: 0, going: .backward).direction, PlanVector(dx: -3_072, dy: -4_096))
    }

    /// The curve (0, 0), (128, 0), (256, 128), (256, 256), moved to
    /// (8192, 8192): its control polygon is 128 + 181 + 128 = 437 units, so
    /// it is sampled at eighths (8 × 64 ≥ 437). The samples, from
    /// (8−i)³·p0 + 3(8−i)²i·c1 + 3(8−i)i²·c2 + i³·p3 over 512, rounded
    /// halves up: (0, 0), (48, 6) from (47.75, 5.75), (94, 22), (137, 47)
    /// from (137.25, 47.25), (176, 80), (209, 119) from (208.75, 118.75),
    /// (234, 162), (250, 208) from (250.25, 208.25), (256, 256). The pieces:
    /// √2340 → 48, √2372 → 49, √2474 → 50, √2610 → 51, then the same
    /// backwards: 396 in all.
    func testACurveIsSampledAndMeasuredByTheFixedIntegerRules() throws {
        var world = try makeWorld()
        let a = try node(8_192, 8_192, in: &world)
        let b = try node(8_448, 8_448, in: &world)
        let curve = TrackCurve.cubic(PlanPoint(x: 8_320, y: 8_192), PlanPoint(x: 8_448, y: 8_320))
        let edge = try world.buildTrackEdge(from: a, to: b, curve: curve)
        let geometry = try XCTUnwrap(world.trackGeometry(of: edge))
        let offsets: [(Int64, Int64)] = [(0, 0), (48, 6), (94, 22), (137, 47), (176, 80), (209, 119), (234, 162), (250, 208), (256, 256)]
        XCTAssertEqual(geometry.points, offsets.map { WorldCoordinate(x: 8_192 + $0.0, y: 8_192 + $0.1) })
        XCTAssertEqual(geometry.distances, [0, 48, 97, 147, 198, 249, 299, 348, 396])
        XCTAssertEqual(world.trackEdge(edge)?.length, 396)
        XCTAssertEqual(geometry.startDirection, PlanVector(dx: 128, dy: 0), "leaves its from node toward the first control point")
        XCTAssertEqual(geometry.endDirection, PlanVector(dx: 0, dy: -128), "leaves its to node toward the second")
        // At a sample, the way of the piece after it; halfway along the
        // first piece, half of (48, 6).
        XCTAssertEqual(geometry.location(at: 48), TrackLocation(position: WorldCoordinate(x: 8_240, y: 8_198), direction: PlanVector(dx: 46, dy: 16)))
        XCTAssertEqual(geometry.location(at: 24).position, WorldCoordinate(x: 8_216, y: 8_195))
        XCTAssertEqual(geometry.location(at: 396), TrackLocation(position: WorldCoordinate(x: 8_448, y: 8_448), direction: PlanVector(dx: 6, dy: 48)))
        // Only the ends and the curve are saved; the rest is worked out
        // again, the same, every time.
        XCTAssertEqual(TrackGeometry(from: WorldCoordinate(x: 8_192, y: 8_192), to: WorldCoordinate(x: 8_448, y: 8_448), curve: curve), geometry)
    }

    /// Control points evenly spaced along a line make a curve that moves
    /// uniformly: 3072 units of polygon need 64 samples (64 × 64 ≥ 3072),
    /// each exactly 48 further on.
    func testEvenlySpacedControlPointsSampleEvenly() throws {
        let geometry = try XCTUnwrap(TrackGeometry(
            from: WorldCoordinate(x: 512, y: 512), to: WorldCoordinate(x: 3_584, y: 512),
            curve: .cubic(PlanPoint(x: 1_536, y: 512), PlanPoint(x: 2_560, y: 512))
        ))
        XCTAssertEqual(geometry.points.count, 65)
        XCTAssertEqual(geometry.points.map(\.x), (0...64).map { 512 + 48 * Int64($0) })
        XCTAssertEqual(geometry.length, 3_072)
    }

    func testAnSCurveBendsBothWaysInOneEdge() throws {
        // Leaves east, arrives heading east again, one row of tiles south.
        let geometry = try XCTUnwrap(TrackGeometry(
            from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 2_048, y: 1_024),
            curve: .cubic(PlanPoint(x: 1_024, y: 0), PlanPoint(x: 1_024, y: 1_024))
        ))
        XCTAssertEqual(geometry.points.first, WorldCoordinate(x: 0, y: 0))
        XCTAssertEqual(geometry.points.last, WorldCoordinate(x: 2_048, y: 1_024))
        let turns = zip(geometry.points, geometry.points.dropFirst()).map { $1.y - $0.y }
        XCTAssertTrue(turns.allSatisfy { $0 >= 0 }, "always heading south-east or east")
        XCTAssertGreaterThan(geometry.length, 2_289, "longer than the chord √(2048² + 1024²) = 2289.7")
        XCTAssertEqual(geometry.startDirection, PlanVector(dx: 1_024, dy: 0))
        XCTAssertEqual(geometry.endDirection, PlanVector(dx: -1_024, dy: 0))
    }

    func testInvalidGeometryIsRefused() throws {
        let p = WorldCoordinate(x: 0, y: 0)
        let q = WorldCoordinate(x: 1_024, y: 0)
        XCTAssertNil(TrackGeometry(from: p, to: p, curve: .straight), "no length")
        // Stage S4: ends at different heights make a slope; ends at one place
        // in plan make no edge, whatever their heights.
        XCTAssertEqual(TrackGeometry(from: p, to: WorldCoordinate(x: 1_024, y: 0, z: 64), curve: .straight)?.length, 1_024)
        XCTAssertNil(TrackGeometry(from: p, to: WorldCoordinate(x: 0, y: 0, z: 512), curve: .straight), "straight up")
        XCTAssertNil(TrackGeometry(from: p, to: q, curve: .cubic(PlanPoint(x: 0, y: 0), PlanPoint(x: 512, y: 0))), "leaves in no direction")
        XCTAssertNil(TrackGeometry(from: p, to: q, curve: .cubic(PlanPoint(x: 512, y: 0), PlanPoint(x: 1_024, y: 0))), "arrives from no direction")
        // Handles pointing back make the line double back: a cusp.
        XCTAssertNil(TrackGeometry(from: p, to: q, curve: .cubic(PlanPoint(x: 2_048, y: 0), PlanPoint(x: -1_024, y: 0))))
        // Beyond the limit, nothing is worked out.
        let far = WorldCoordinate.limit + 1
        XCTAssertNil(TrackGeometry(from: p, to: WorldCoordinate(x: far, y: 0), curve: .straight))
        XCTAssertNil(TrackGeometry(from: p, to: q, curve: .cubic(PlanPoint(x: far, y: 0), PlanPoint(x: 512, y: 1))))
        // At the limit, the largest values still do not overflow.
        let corner = TrackGeometry(
            from: WorldCoordinate(x: -WorldCoordinate.limit, y: -WorldCoordinate.limit),
            to: WorldCoordinate(x: WorldCoordinate.limit, y: WorldCoordinate.limit),
            curve: .cubic(PlanPoint(x: WorldCoordinate.limit, y: -WorldCoordinate.limit), PlanPoint(x: -WorldCoordinate.limit, y: WorldCoordinate.limit))
        )
        XCTAssertNotNil(corner)
        XCTAssertEqual(TrackGeometry(from: WorldCoordinate(x: -WorldCoordinate.limit, y: 0), to: WorldCoordinate(x: WorldCoordinate.limit, y: 0), curve: .straight)?.length, 1 << 30)
    }

    func testIntegerSquareRootsAreExact() {
        XCTAssertEqual(FixedPoint.squareRoot(0), 0)
        XCTAssertEqual(FixedPoint.squareRoot(99), 9)
        XCTAssertEqual(FixedPoint.squareRoot(100), 10)
        XCTAssertEqual(FixedPoint.squareRoot(Int64.max), 3_037_000_499)
        XCTAssertEqual(FixedPoint.roundedSquareRoot(2_340), 48)
        XCTAssertEqual(FixedPoint.roundedSquareRoot(2_372), 49)
        XCTAssertEqual(FixedPoint.roundedSquareRoot(90), 9, "√90 = 9.49")
        XCTAssertEqual(FixedPoint.roundedSquareRoot(91), 10, "√91 = 9.54")
        XCTAssertEqual(FixedPoint.roundedDivision(-5, by: 2), -2, "halves round up")
        XCTAssertEqual(FixedPoint.roundedDivision(5, by: 2), 3)
        XCTAssertEqual(FixedPoint.roundedDivision(-7, by: 2), -3)
        XCTAssertEqual(FixedPoint.roundedShift(-3, by: 1), -1)
    }

    // MARK: - Construction

    func testNodesAndEdgesAreRefusedInOrderAndChangeNothing() throws {
        var world = try makeWorld()
        let a = try node(512, 512, in: &world)
        let b = try node(2_560, 512, in: &world)
        let before = world
        func refused(_ expected: GameError, _ body: (inout GameWorld) throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
            var copy = world
            do {
                try body(&copy)
                XCTFail("expected \(expected)", file: file, line: line)
            } catch {
                XCTAssertEqual(error as? GameError, expected, file: file, line: line)
                XCTAssertEqual(copy, before, "a refused command changes nothing", file: file, line: line)
            }
        }
        refused(.invalidTrackGeometry) { _ = try $0.buildTrackNode(at: WorldCoordinate(x: 512, y: 512)) }
        refused(.invalidTrackGeometry) { _ = try $0.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 0)) }
        refused(.invalidTrackGeometry) { _ = try $0.buildTrackNode(at: WorldCoordinate(x: -1, y: 0)) }
        // Stage S4: 4096 above or below the ground at most.
        refused(.invalidTrackGeometry) { _ = try $0.buildTrackNode(at: WorldCoordinate(x: 0, y: 0, z: 4_097)) }
        refused(.invalidTrackGeometry) { _ = try $0.buildTrackNode(at: WorldCoordinate(x: 0, y: 0, z: -4_097)) }
        refused(.unknownTrackNode(.node(9))) { _ = try $0.buildTrackEdge(from: .node(9), to: .node(8)) }
        refused(.unknownTrackNode(.node(8))) { _ = try $0.buildTrackEdge(from: a, to: .node(8)) }
        refused(.unknownTrackNode(.tile(GridPosition(x: 0, y: 0)))) { _ = try $0.buildTrackEdge(from: a, to: .tile(GridPosition(x: 0, y: 0))) }
        refused(.invalidTrackGeometry) { _ = try $0.buildTrackEdge(from: a, to: a) }
        refused(.invalidTrackGeometry) { _ = try $0.buildTrackEdge(from: a, to: b, curve: .cubic(PlanPoint(x: 1_024, y: -1), PlanPoint(x: 2_048, y: 512))) }
        refused(.unknownTrackEdge(.edge(1))) { try $0.removeTrackEdge(.edge(1)) }
        refused(.unknownTrackEdge(.link(GridPosition(x: 0, y: 0), GridPosition(x: 1, y: 0)))) { try $0.removeTrackEdge(.link(GridPosition(x: 0, y: 0), GridPosition(x: 1, y: 0))) }
        refused(.unknownTrackNode(.node(3))) { try $0.removeTrackNode(.node(3)) }

        var poor = try GameWorld(width: 16, height: 16, economy: GameEconomy(balance: 150, costs: ConstructionCosts(track: 100, station: 1, train: 1)))
        let c = try node(512, 512, in: &poor)
        let d = try node(2_560, 512, in: &poor)
        XCTAssertThrowsError(try poor.buildTrackEdge(from: c, to: d)) { error in
            XCTAssertEqual(error as? GameError, .insufficientFunds(required: 200, available: 150), "2048 units: two tiles")
        }
        // A price that does not fit in Money is more than any balance.
        var rich = try GameWorld(width: 16, height: 16, economy: GameEconomy(balance: Money(.max), costs: ConstructionCosts(track: Money(.max / 2), station: 1, train: 1)))
        let e = try node(512, 512, in: &rich)
        let f = try node(4_608, 512, in: &rich)
        XCTAssertThrowsError(try rich.buildTrackEdge(from: e, to: f)) { error in
            XCTAssertEqual(error as? GameError, .insufficientFunds(required: Money(.max), available: Money(.max)))
        }

        let edge = try world.buildTrackEdge(from: a, to: b)
        XCTAssertThrowsError(try world.removeTrackNode(a)) { XCTAssertEqual($0 as? GameError, .trackNodeInUse(a)) }
        try world.removeTrackEdge(edge)
        try world.removeTrackNode(a)
        XCTAssertNil(world.network.node(a))
        // Numbers are never handed out again.
        XCTAssertEqual(try node(512, 512, in: &world), .node(3))
        XCTAssertEqual(try world.buildTrackEdge(from: .node(3), to: b), .edge(2))
    }

    // MARK: - Topology: only a shared node joins

    func testEdgesThatCrossInPlanWithoutANodeNeverMeet() throws {
        var world = try makeWorld()
        // An X: west–east and north–south, crossing at (4096, 4096). Since
        // Stage S4 two tracks may only cross that way one over the other
        // (decision 30): at one height it is refused.
        let n = try node(4_096, 2_048, in: &world)
        let s = try node(4_096, 6_144, in: &world)
        let ns = try world.buildTrackEdge(from: n, to: s)
        let lowWest = try node(2_048, 4_096, in: &world)
        let lowEast = try node(6_144, 4_096, in: &world)
        XCTAssertThrowsError(try world.buildTrackEdge(from: lowWest, to: lowEast)) { XCTAssertEqual($0 as? GameError, .trackConflict(ns)) }
        let w = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 4_096, z: 512))
        let e = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 4_096, z: 512))
        let we = try world.buildTrackEdge(from: w, to: e, structure: .elevated)
        XCTAssertEqual(world.transitions(after: forward(we)), [])
        XCTAssertEqual(world.transitions(after: forward(ns)), [])
        try world.purchaseTrain(named: "A")
        try world.purchaseTrain(named: "B")
        try world.placeTrain(first, at: .onEdge(forward(we), offset: 2_048))
        try world.placeTrain(second, at: .onEdge(forward(ns), offset: 2_048))
        XCTAssertNil(world.route(from: .onEdge(forward(we), offset: 2_048), to: s), "no way from one to the other")
        // Each stands on the boundary between the second and third of its
        // edge's four spans (4096 long: a span per 1024), so holds both.
        XCTAssertEqual(world.occupiedResources(of: first), [span(we, 1_024, 2_048), span(we, 2_048, 3_072)])
        XCTAssertEqual(world.occupiedResources(of: second), [span(ns, 1_024, 2_048), span(ns, 2_048, 3_072)])
        XCTAssertEqual(world.occupancyConflicts(), [], "both stand at the crossing point, but share no track")
    }

    func testAnodeSharedByTwoStraightLinesIsALevelCrossing() throws {
        var world = try makeWorld()
        let x = try node(4_096, 4_096, in: &world)
        let w = try node(2_048, 4_096, in: &world)
        let e = try node(6_144, 4_096, in: &world)
        let n = try node(4_096, 3_072, in: &world)
        let s = try node(4_096, 5_120, in: &world)
        let wx = try world.buildTrackEdge(from: w, to: x)
        let xe = try world.buildTrackEdge(from: x, to: e)
        let nx = try world.buildTrackEdge(from: n, to: x)
        let xs = try world.buildTrackEdge(from: x, to: s)
        // Only straight on: west to east, north to south, and back.
        XCTAssertEqual(world.transitions(after: forward(wx)), [forward(xe)])
        XCTAssertEqual(world.transitions(after: forward(nx)), [forward(xs)])
        XCTAssertEqual(world.transitions(after: backward(xe)), [backward(wx)])
        XCTAssertEqual(world.transitions(after: backward(xs)), [backward(nx)])
        let centre = try XCTUnwrap(world.network.node(x))
        XCTAssertEqual(centre.ends.map(\.edge), [wx, xe, nx, xs])
        XCTAssertEqual(centre.end(of: wx)?.exits, [xe])
        XCTAssertNil(world.route(from: .onEdge(forward(wx), offset: 100), to: s), "no turning at a crossing")
        // Two trains at the crossing share it, as on the grid.
        try world.purchaseTrain(named: "A")
        try world.purchaseTrain(named: "B")
        try world.placeTrain(first, at: .onEdge(forward(wx), offset: 2_048))
        try world.placeTrain(second, at: .onEdge(forward(nx), offset: 1_024))
        XCTAssertEqual(world.occupiedResources(of: first), [.node(x)])
        XCTAssertEqual(world.occupancyConflicts(), [TrackConflict(resource: .node(x), trains: [first, second])])
    }

    func testATurnoutJoinsItsStemToEachBranchAndNeverBranchToBranch() throws {
        var world = try makeWorld()
        let s = try node(2_048, 6_144, in: &world)
        let t = try node(4_096, 6_144, in: &world)
        let u = try node(6_144, 6_144, in: &world)
        let v = try node(6_144, 7_168, in: &world)
        let stem = try world.buildTrackEdge(from: s, to: t)
        let straight = try world.buildTrackEdge(from: t, to: u)
        // Leaves the points heading east, then curves south-east to arrive
        // at V heading east again.
        let diverging = try world.buildTrackEdge(from: t, to: v, curve: .cubic(PlanPoint(x: 4_608, y: 6_144), PlanPoint(x: 5_632, y: 7_168)))
        XCTAssertEqual(world.transitions(after: forward(stem)), [forward(straight), forward(diverging)])
        XCTAssertEqual(world.transitions(after: backward(straight)), [backward(stem)])
        XCTAssertEqual(world.transitions(after: backward(diverging)), [backward(stem)])
        let start = TrainPosition.onEdge(forward(stem), offset: 0)
        XCTAssertEqual(world.route(from: start, to: v), [forward(diverging)])
        XCTAssertEqual(world.route(from: start, to: u), [forward(straight)])
        XCTAssertNil(world.route(from: .onEdge(backward(straight), offset: 10), to: v), "branch to branch needs a reversal")
    }

    func testEdgesMeetingAtAnAngleJoinNothing() throws {
        var world = try makeWorld()
        let a = try node(1_024, 1_024, in: &world)
        let b = try node(3_072, 1_024, in: &world)
        let c = try node(3_072, 3_072, in: &world)
        let d = try node(5_120, 1_152, in: &world)
        let e = try node(5_120, 1_280, in: &world)
        let ab = try world.buildTrackEdge(from: a, to: b)
        let bc = try world.buildTrackEdge(from: b, to: c)
        XCTAssertEqual(world.transitions(after: forward(ab)), [], "a right angle")
        // 2048 east and 128 south: a slope of 1 in 16 joins, exactly at the
        // tolerance; 256 south (1 in 8) does not.
        let bd = try world.buildTrackEdge(from: b, to: d)
        let be = try world.buildTrackEdge(from: b, to: e)
        XCTAssertEqual(world.transitions(after: forward(ab)), [forward(bd)])
        XCTAssertEqual(world.transitions(after: backward(bd)), [backward(ab)])
        XCTAssertEqual(world.transitions(after: backward(be)), [])
        XCTAssertEqual(world.transitions(after: backward(bc)), [])
    }

    func testParallelEdgesAreDistinctAndTheShorterOrLowerIsTaken() throws {
        var world = try makeWorld()
        let a = try node(1_024, 4_096, in: &world)
        let b = try node(3_072, 4_096, in: &world)
        let c = try node(5_120, 4_096, in: &world)
        let d = try node(7_168, 4_096, in: &world)
        let ab = try world.buildTrackEdge(from: a, to: b)
        // Two ways from B to C: a bow to the north, then the straight.
        let bow = try world.buildTrackEdge(from: b, to: c, curve: .cubic(PlanPoint(x: 3_584, y: 4_096), PlanPoint(x: 4_608, y: 4_096 - 1)))
        _ = bow
        let straight = try world.buildTrackEdge(from: b, to: c)
        let cd = try world.buildTrackEdge(from: c, to: d)
        let bowLength = try XCTUnwrap(world.trackEdge(bow)?.length)
        XCTAssertGreaterThanOrEqual(bowLength, 2_048)
        let start = TrainPosition.onEdge(forward(ab), offset: 0)
        let route = try XCTUnwrap(world.route(from: start, to: d))
        XCTAssertEqual(route.last, forward(cd))
        if bowLength > 2_048 {
            XCTAssertEqual(route, [forward(straight), forward(cd)], "the shorter way")
        } else {
            XCTAssertEqual(route, [forward(bow), forward(cd)], "equal lengths: the lower edge")
        }
        // Two exactly equal ways: the lower numbered edge.
        var twin = try makeWorld()
        let p = try node(1_024, 1_024, in: &twin)
        let q = try node(3_072, 1_024, in: &twin)
        let r = try node(5_120, 1_024, in: &twin)
        let pq = try twin.buildTrackEdge(from: p, to: q)
        let low = try twin.buildTrackEdge(from: q, to: r, curve: .cubic(PlanPoint(x: 3_584, y: 1_024), PlanPoint(x: 4_608, y: 1_024)))
        _ = try twin.buildTrackEdge(from: q, to: r)
        XCTAssertEqual(twin.trackEdge(low)?.length, 2_048)
        XCTAssertEqual(twin.route(from: .onEdge(forward(pq), offset: 5), to: r), [forward(low)])
    }

    // MARK: - Trains on the network

    /// A straight line west to east: A–B 1024, B–C 2560, C–D 512, and a
    /// spur from D north, at a right angle, that no train can take.
    private func makeLine() throws -> (world: GameWorld, edges: [TrackEdgeID], nodes: [TrackNodeID]) {
        var world = try makeWorld()
        let a = try node(512, 1_536, in: &world)
        let b = try node(1_536, 1_536, in: &world)
        let c = try node(4_096, 1_536, in: &world)
        let d = try node(4_608, 1_536, in: &world)
        let n = try node(4_608, 512, in: &world)
        let ab = try world.buildTrackEdge(from: a, to: b)
        let bc = try world.buildTrackEdge(from: b, to: c)
        let cd = try world.buildTrackEdge(from: c, to: d)
        let dn = try world.buildTrackEdge(from: d, to: n)
        try world.purchaseTrain(named: "A")
        try world.purchaseTrain(named: "B")
        return (world, [ab, bc, cd, dn], [a, b, c, d, n])
    }

    func testATrainRunsAlongEdgesOfTheirOwnLengths() throws {
        var (world, edges, nodes) = try makeLine()
        let (ab, bc, cd, dn) = (edges[0], edges[1], edges[2], edges[3])
        try world.placeTrain(first, at: .onEdge(forward(ab), offset: 0))
        XCTAssertEqual(world.route(from: .onEdge(forward(ab), offset: 0), to: nodes[3]), [forward(bc), forward(cd)])
        try world.setTrainContinuation(first, along: [forward(bc), forward(cd)])
        try world.setTrainMovementRate(first, to: 1_500)
        try world.advance(ticks: 1)
        // 1024 to B, then 476 into B–C.
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(forward(bc), offset: 476))
        XCTAssertEqual(world.train(id: first)?.movement.cursor, 1)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(forward(bc), offset: 1_976))
        try world.advance(ticks: 1)
        // 584 to C, all 512 of C–D; 404 left over, dropped at D.
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(forward(cd), offset: 512))
        XCTAssertEqual(world.train(id: first)?.movement, TrainMovement(rate: 1_500, continuation: [], cursor: 0))
        // The spur leaves D at a right angle: no continuation onto it.
        XCTAssertThrowsError(try world.setTrainContinuation(first, along: [forward(dn)])) {
            XCTAssertEqual($0 as? GameError, .invalidContinuation)
        }
        XCTAssertNil(world.route(from: .onEdge(forward(cd), offset: 512), to: nodes[4]))
        XCTAssertThrowsError(try world.setTrainContinuation(first, to: [GridPosition(x: 0, y: 0)])) {
            XCTAssertEqual($0 as? GameError, .invalidContinuation, "a train on the network follows edges")
        }
        XCTAssertEqual(world.location(of: world.train(id: first)!.position!)?.position, WorldCoordinate(x: 4_608, y: 1_536))
    }

    func testATrainWaitsWhereAnEdgeAheadWasRemovedAndStopsAtTheExactEnd() throws {
        var (world, edges, _) = try makeLine()
        let (ab, bc, cd) = (edges[0], edges[1], edges[2])
        try world.placeTrain(first, at: .onEdge(forward(ab), offset: 24))
        try world.setTrainContinuation(first, along: [forward(bc), forward(cd)])
        try world.removeTrackEdge(cd)
        try world.setTrainMovementRate(first, to: 1_000)
        try world.advance(ticks: 1)
        // Exactly at B: the next edge is not even looked at.
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(forward(ab), offset: 1_024))
        XCTAssertEqual(world.train(id: first)?.movement.cursor, 0)
        try world.advance(ticks: 3)
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(forward(bc), offset: 2_560), "waits at C for the removed edge")
        XCTAssertEqual(world.train(id: first)?.movement.edges, [bc, cd])
        XCTAssertEqual(world.train(id: first)?.movement.cursor, 1)
    }

    func testALongTrainsBodyFollowsItsHeadAcrossEdges() throws {
        var (world, edges, nodes) = try makeLine()
        let (ab, bc, cd) = (edges[0], edges[1], edges[2])
        try world.setTrainCars(first, to: 3)
        // 2048 long: 1500 on B–C, and 548 more back along A–B.
        try world.placeTrain(first, at: .onEdge(forward(bc), offset: 1_500))
        XCTAssertEqual(world.train(id: first)?.trailEdges, [ab])
        // B–C (2560) is three spans: 0–853, 853–1706, 1706–2560; the train
        // covers 0–1500 of it and 476–1024 of A–B, one span.
        XCTAssertEqual(world.trackSpans(of: bc).map(\.end), [853, 1_706, 2_560])
        XCTAssertEqual(world.occupiedResources(of: first), [.node(nodes[1]), span(ab, 0, 1_024), span(bc, 0, 853), span(bc, 853, 1_706)])
        XCTAssertEqual(world.bodyPath(of: first), [WorldCoordinate(x: 3_036, y: 1_536), WorldCoordinate(x: 1_536, y: 1_536), WorldCoordinate(x: 988, y: 1_536)])
        XCTAssertThrowsError(try world.removeTrackEdge(ab)) { XCTAssertEqual($0 as? GameError, .trackEdgeInUse(ab), "the body is on it") }

        try world.setTrainContinuation(first, along: [forward(cd)])
        try world.setTrainMovementRate(first, to: 1_000)
        try world.advance(ticks: 1)
        // 1060 to C then 512 would be too far: at 2500 on B–C, the body now
        // on B–C alone (2500 ≥ 2048).
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(forward(bc), offset: 2_500))
        XCTAssertEqual(world.train(id: first)?.trailEdges, [])
        XCTAssertEqual(world.occupiedResources(of: first), [span(bc, 0, 853), span(bc, 853, 1_706), span(bc, 1_706, 2_560)], "452 to 2500")
        try world.advance(ticks: 1)
        // 60 to C, then 512 of C–D; the body reaches back 1536 onto B–C.
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(forward(cd), offset: 512))
        XCTAssertEqual(world.train(id: first)?.trailEdges, [bc])
        XCTAssertEqual(world.occupiedResources(of: first), [
            .node(nodes[2]), .node(nodes[3]), span(bc, 853, 1_706), span(bc, 1_706, 2_560), span(cd, 0, 512),
        ], "1024 to 2560 of B–C, all of C–D")
        try world.removeTrackEdge(ab)
    }

    func testTurningRoundTwiceRestoresATrainExactly() throws {
        var (world, edges, _) = try makeLine()
        let (ab, bc) = (edges[0], edges[1])
        try world.setTrainCars(first, to: 3)
        try world.placeTrain(first, at: .onEdge(forward(bc), offset: 1_500))
        let placed = world
        try world.reverseTrain(first)
        // The tail was 548 back from B on A–B: the head goes there, facing
        // west; the body runs back over B to where the head was.
        XCTAssertEqual(world.train(id: first)?.position, .onEdge(backward(ab), offset: 548))
        XCTAssertEqual(world.train(id: first)?.trailEdges, [bc])
        try world.reverseTrain(first)
        XCTAssertEqual(world, placed)

        // A train of one car turns on the spot, at a node too.
        try world.placeTrain(second, at: .onEdge(forward(ab), offset: 1_024))
        let one = world
        try world.reverseTrain(second)
        XCTAssertEqual(world.train(id: second)?.position, .onEdge(backward(ab), offset: 0), "at B, facing into A–B")
        XCTAssertEqual(world.occupiedResources(of: second), [.node(.node(2))])
        try world.reverseTrain(second)
        XCTAssertEqual(world, one)

        // The body on the head's own edge: 2048 back from 2500 on B–C.
        var short = placed
        try short.unplaceTrain(first)
        try short.placeTrain(first, at: .onEdge(forward(bc), offset: 2_500))
        let before = short
        try short.reverseTrain(first)
        XCTAssertEqual(short.train(id: first)?.position, .onEdge(backward(bc), offset: 2_108), "2560 − 2500 + 2048")
        XCTAssertEqual(short.train(id: first)?.trailEdges, [])
        try short.reverseTrain(first)
        XCTAssertEqual(short, before)
    }

    func testPlacementOnTheNetworkFollowsTheCanonicalForm() throws {
        var (world, edges, _) = try makeLine()
        let (ab, bc) = (edges[0], edges[1])
        try world.setTrainCars(first, to: 2)
        XCTAssertThrowsError(try world.placeTrain(first, at: .onEdge(forward(bc), offset: 0))) {
            XCTAssertEqual($0 as? GameError, .invalidTrainPosition, "a body stands at the end of the edge it came along")
        }
        XCTAssertThrowsError(try world.placeTrain(first, at: .onEdge(forward(ab), offset: 1_000))) {
            XCTAssertEqual($0 as? GameError, .invalidTrainPosition, "1024 behind needed, the track ends at A")
        }
        XCTAssertThrowsError(try world.placeTrain(first, at: .onEdge(forward(ab), offset: 1_025))) {
            XCTAssertEqual($0 as? GameError, .invalidTrainPosition, "beyond the edge")
        }
        XCTAssertThrowsError(try world.placeTrain(first, at: .onEdge(forward(.edge(9)), offset: 1))) {
            XCTAssertEqual($0 as? GameError, .invalidTrainPosition)
        }
        try world.placeTrain(first, at: .onEdge(forward(ab), offset: 1_024))
        XCTAssertEqual(world.train(id: first)?.trailEdges, [])
        try world.placeTrain(second, at: .onEdge(forward(ab), offset: 0))
        XCTAssertEqual(world.occupiedResources(of: second), [.node(.node(1))])
    }

    func testLengthIsPhysicalNotACountOfEdgesOrTiles() throws {
        // Seven short edges of 300: a train of three cars (2048) covers
        // parts of eight edges wherever it stands.
        var world = try makeWorld()
        var nodes: [TrackNodeID] = []
        for k in 0..<9 {
            nodes.append(try node(512 + 300 * Int64(k), 512, in: &world))
        }
        var edges: [TrackEdgeID] = []
        for k in 0..<8 {
            edges.append(try world.buildTrackEdge(from: nodes[k], to: nodes[k + 1]))
        }
        try world.purchaseTrain(named: "A")
        try world.setTrainCars(first, to: 3)
        try world.placeTrain(first, at: .onEdge(forward(edges[7]), offset: 200))
        // 200 + 6 × 300 = 2000 < 2048, then the seventh edge back reaches it.
        XCTAssertEqual(world.train(id: first)?.trailEdges, [edges[6], edges[5], edges[4], edges[3], edges[2], edges[1], edges[0]])
        XCTAssertEqual(world.occupiedResources(of: first).count, 8 + 7, "eight edges and the seven nodes between")
    }

    // MARK: - Saves

    private func roundTrip(_ world: GameWorld) throws -> GameWorld {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try JSONDecoder().decode(GameWorld.self, from: encoder.encode(world))
    }

    private func json(_ world: GameWorld) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
    }

    func testTheNetworkAndItsTrainsSurviveASaveExactly() throws {
        var (world, edges, _) = try makeLine()
        try world.setTrainCars(first, to: 3)
        try world.placeTrain(first, at: .onEdge(forward(edges[1]), offset: 1_500))
        try world.setTrainContinuation(first, along: [forward(edges[2])])
        try world.setTrainMovementRate(first, to: 10)
        try world.advance(ticks: 1)
        let curveEnd = try node(8_448, 8_448, in: &world)
        let curveStart = try node(8_192, 8_192, in: &world)
        try world.buildTrackEdge(from: curveStart, to: curveEnd, curve: .cubic(PlanPoint(x: 8_320, y: 8_192), PlanPoint(x: 8_448, y: 8_320)))
        XCTAssertEqual(try roundTrip(world), world)
        let object = try json(world)
        let network = try XCTUnwrap(object["network"] as? [String: Any])
        XCTAssertEqual(network["nextNodeID"] as? Int, 8)
        XCTAssertEqual(network["nextEdgeID"] as? Int, 6)
        let savedEdges = try XCTUnwrap(network["edges"] as? [[String: Any]])
        XCTAssertNil(savedEdges[0]["length"], "lengths are worked out, not saved")
        let trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
        XCTAssertEqual(trains[0]["trailEdges"] as? [Int], [1])
        let position = try XCTUnwrap(trains[0]["position"] as? [String: Any])
        XCTAssertNotNil(position["onEdge"])
    }

    func testGridOnlySavesAreUnchangedAndOldSavesRead() throws {
        var world = try makeWorld()
        try world.buildTrack(at: GridPosition(x: 1, y: 1), connections: [.east, .west])
        try world.purchaseTrain(named: "A")
        try world.placeTrain(first, at: .atNode(GridPosition(x: 1, y: 1), heading: .east))
        let object = try json(world)
        XCTAssertNil(object["network"], "no network key while the network was never used")
        let train = try XCTUnwrap((object["trains"] as? [[String: Any]])?.first)
        XCTAssertNil(train["trailEdges"])
        XCTAssertEqual(try roundTrip(world), world)
        // A network that was used and emptied again is saved, so its
        // numbers are never handed out twice.
        let a = try node(512, 512, in: &world)
        try world.removeTrackNode(a)
        XCTAssertNotNil(try json(world)["network"])
        XCTAssertEqual(try roundTrip(world).network, world.network)
    }

    func testMalformedNetworkSavesAreRefusedNotRepaired() throws {
        var (world, edges, _) = try makeLine()
        try world.setTrainCars(first, to: 3)
        try world.placeTrain(first, at: .onEdge(forward(edges[1]), offset: 1_500))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let good = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(world)) as? [String: Any])
        func refused(_ change: (inout [String: Any]) -> Void, _ reason: String, file: StaticString = #filePath, line: UInt = #line) {
            var object = good
            change(&object)
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return XCTFail("not JSON", file: file, line: line) }
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: data), reason, file: file, line: line)
        }
        func network(_ change: @escaping (inout [String: Any]) -> Void) -> (inout [String: Any]) -> Void {
            { object in
                var network = object["network"] as! [String: Any]
                change(&network)
                object["network"] = network
            }
        }
        func node(_ index: Int, _ key: String, _ value: Any) -> (inout [String: Any]) -> Void {
            network { network in
                var nodes = network["nodes"] as! [[String: Any]]
                nodes[index][key] = value
                network["nodes"] = nodes
            }
        }
        func edge(_ index: Int, _ key: String, _ value: Any) -> (inout [String: Any]) -> Void {
            network { network in
                var edges = network["edges"] as! [[String: Any]]
                edges[index][key] = value
                network["edges"] = edges
            }
        }
        func train(_ key: String, _ value: Any) -> (inout [String: Any]) -> Void {
            { object in
                var trains = object["trains"] as! [[String: Any]]
                trains[0][key] = value
                object["trains"] = trains
            }
        }
        refused({ $0["network"] = NSNull() }, "an explicit null network")
        refused(node(0, "x", 16_384), "off the map")
        refused(node(0, "z", 4_097), "beyond the heights track may have (Stage S4)")
        refused(node(0, "x", Int64(1) << 40), "beyond the limit")
        refused(node(1, "x", 512), "two nodes at one point")
        refused(node(1, "id", 1), "IDs not ascending")
        refused(network { $0["nextNodeID"] = 3 }, "an ID not below the next one")
        refused(edge(0, "to", 1), "an edge from a node to itself")
        refused(edge(0, "from", 99), "an unknown node")
        refused(edge(0, "curve", ["cubic": ["control1": ["x": 512, "y": 1_536], "control2": ["x": 1_000, "y": 1_536]]]), "a handle on its end")
        refused(edge(0, "curve", ["cubic": ["control1": ["x": 900, "y": 1_536], "control2": ["x": -1, "y": 1_536]]]), "off the map")
        refused(edge(0, "curve", ["straight": [:], "cubic": [:]]), "two curves")
        refused(edge(0, "curve", NSNull()), "no curve")
        refused(train("trailEdges", [2]), "the wrong body")
        refused(train("trailEdges", []), "a body that does not reach the tail")
        refused(train("trailEdges", NSNull()), "an explicit null body")
        refused(train("position", ["onEdge": ["edge": 2, "direction": "forward", "offset": 0]]), "a body at offset 0")
        refused(train("position", ["onEdge": ["edge": 2, "direction": "forward", "offset": 2_561]]), "beyond the edge")
        refused(train("position", ["onEdge": ["edge": 2, "direction": "sideways", "offset": 5]]), "no such direction")
        refused(train("position", ["onEdge": ["edge": 0, "direction": "forward", "offset": 5]]), "edge 0")
        refused(train("trail", [["x": 0, "y": 0]]), "a grid trail on the network")
        refused(train("movement", ["rate": 1, "continuation": [], "cursor": 0, "edges": [3, 3]]), "straight back along the same edge")
        refused(train("movement", ["rate": 1, "continuation": [], "cursor": 0, "edges": [99]]), "an edge never built")
        refused(train("movement", ["rate": 1, "continuation": [["x": 1, "y": 1]], "cursor": 0]), "a grid continuation on the network")
        refused(train("movement", ["rate": 1, "continuation": [], "cursor": 0, "edges": NSNull()]), "explicit null edges")
    }

    // MARK: - Renderer queries

    func testRendererQueriesGiveTheCentreLinesAndTrainsInWorldCoordinates() throws {
        var world = try makeWorld()
        let a = try node(8_192, 8_192, in: &world)
        let b = try node(8_448, 8_448, in: &world)
        let c = try node(8_448, 10_496, in: &world)
        let curve = try world.buildTrackEdge(from: a, to: b, curve: .cubic(PlanPoint(x: 8_320, y: 8_192), PlanPoint(x: 8_448, y: 8_320)))
        let south = try world.buildTrackEdge(from: b, to: c)
        XCTAssertEqual(world.transitions(after: forward(curve)), [forward(south)], "the curve arrives heading south")
        try world.purchaseTrain(named: "A")
        try world.setTrainCars(first, to: 2)
        try world.placeTrain(first, at: .onEdge(forward(south), offset: 700))
        XCTAssertEqual(world.train(id: first)?.trailEdges, [curve])
        XCTAssertEqual(world.location(of: world.train(id: first)!.position!), TrackLocation(position: WorldCoordinate(x: 8_448, y: 9_148), direction: PlanVector(dx: 0, dy: 2_048)))
        // 700 back to B, then 324 of the curve's 396: back past the samples
        // at 348 and 299 (from B: 48 and 97) to 72 along it from A.
        let path = world.bodyPath(of: first)
        XCTAssertEqual(path.first, WorldCoordinate(x: 8_448, y: 9_148))
        XCTAssertEqual(path[1], WorldCoordinate(x: 8_448, y: 8_448))
        XCTAssertEqual(Array(path[2...]), [
            WorldCoordinate(x: 8_442, y: 8_400), WorldCoordinate(x: 8_426, y: 8_354), WorldCoordinate(x: 8_401, y: 8_311),
            WorldCoordinate(x: 8_368, y: 8_272), WorldCoordinate(x: 8_329, y: 8_239), WorldCoordinate(x: 8_286, y: 8_214),
            try XCTUnwrap(world.trackGeometry(of: curve)?.location(at: 72).position),
        ])
        XCTAssertEqual(world.bodyPath(of: second), [])
        XCTAssertNil(world.location(of: .onEdge(forward(.edge(9)), offset: 0)))
    }

    // MARK: - Cost

    /// What the geometry costs, printed for the record rather than asserted
    /// (timings depend on the machine): sampling happens when an edge is
    /// built or loaded, a point lookup is a binary search, and a step of
    /// movement reads only lengths.
    func testGeometryCostIsPaidOnceAndLookupsAreCheap() throws {
        let clock = ContinuousClock()
        var sampled = 0
        let sampling = clock.measure {
            for k in 0..<500 {
                let geometry = TrackGeometry(
                    from: WorldCoordinate(x: 0, y: Int64(k)), to: WorldCoordinate(x: 65_536, y: 65_536),
                    curve: .cubic(PlanPoint(x: 40_000, y: Int64(k)), PlanPoint(x: 65_536, y: 20_000))
                )
                sampled += geometry?.points.count ?? 0
            }
        }
        XCTAssertEqual(sampled, 500 * 1_025, "long curves are sampled into 1024 pieces")
        let geometry = try XCTUnwrap(TrackGeometry(
            from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 65_536, y: 65_536),
            curve: .cubic(PlanPoint(x: 40_000, y: 0), PlanPoint(x: 65_536, y: 20_000))
        ))
        var checksum: Int64 = 0
        let lookups = clock.measure {
            for k in 0..<100_000 {
                checksum &+= geometry.location(at: Int64(k) * 7 % geometry.length).position.x
            }
        }
        XCTAssertNotEqual(checksum, 0)

        // Forty trains of three cars chasing round a loop of four curves.
        var world = try makeWorld()
        let r: Int64 = 3_072
        let h: Int64 = r * 5_523 / 10_000
        let (cx, cy): (Int64, Int64) = (8_192, 8_192)
        let top = try node(cx, cy - r, in: &world)
        let right = try node(cx + r, cy, in: &world)
        let bottom = try node(cx, cy + r, in: &world)
        let left = try node(cx - r, cy, in: &world)
        let loop = [
            try world.buildTrackEdge(from: top, to: right, curve: .cubic(PlanPoint(x: cx + h, y: cy - r), PlanPoint(x: cx + r, y: cy - h))),
            try world.buildTrackEdge(from: right, to: bottom, curve: .cubic(PlanPoint(x: cx + r, y: cy + h), PlanPoint(x: cx + h, y: cy + r))),
            try world.buildTrackEdge(from: bottom, to: left, curve: .cubic(PlanPoint(x: cx - h, y: cy + r), PlanPoint(x: cx - r, y: cy + h))),
            try world.buildTrackEdge(from: left, to: top, curve: .cubic(PlanPoint(x: cx - r, y: cy - h), PlanPoint(x: cx - h, y: cy - r))),
        ]
        let lap = (1...4).map { forward(loop[$0 % 4]) }
        for k in 1...40 {
            try world.purchaseTrain(named: "T\(k)")
            let id = TrainID(rawValue: k)
            try world.setTrainCars(id, to: 3)
            try world.placeTrain(id, at: .onEdge(forward(loop[0]), offset: 2_048 + Int64(k)))
            try world.setTrainContinuation(id, along: Array(repeating: lap, count: 30).flatMap { $0 })
            try world.setTrainMovementRate(id, to: 900)
        }
        let movement = try clock.measure {
            try world.advance(ticks: 500)
        }
        XCTAssertEqual(world.trains.count { !$0.trailEdges.isEmpty || $0.cars == 3 }, 40)
        XCTAssertTrue(world.trains.allSatisfy { NetworkInvariants.trainViolations(of: $0, in: world).isEmpty })
        print("[timing] 500 long curves sampled in \(sampling); 100000 point lookups in \(lookups); 40 trains × 500 minutes on curves in \(movement)")
    }
}
