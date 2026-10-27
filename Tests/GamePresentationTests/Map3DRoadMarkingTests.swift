import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 355: the paint at the 3D map's junctions (zebra
/// crossings, stop lines, lane arrows), the centre lines stopping at the
/// crossings, and the signals, bus stops and vending machines.
final class Map3DRoadMarkingTests: XCTestCase {
    private typealias Builder = Map3DScene.Builder
    private typealias Point = Map3DBaseMap.Point

    private let everywhere = Map3DBaseMap.Bounds(minX: -10_000, minZ: -10_000, maxX: 10_000, maxZ: 10_000)

    private func road(_ kind: Map3DBaseMap.RoadKind, _ points: [(Double, Double)]) -> Map3DBaseMap.Road {
        Map3DBaseMap.Road(kind: kind, isRamp: false, points: points.map { Point(x: $0.0, z: $0.1) }, bounds: everywhere)
    }

    /// A primary road along x and a secondary along z crossing at the
    /// origin, each 400 m long: four arms.
    private var crossroads: [Map3DBaseMap.Road] {
        [road(.primary, [(-200, 0), (0, 0), (200, 0)]), road(.secondary, [(0, -200), (0, 0), (0, 200)])]
    }

    private func builder() -> Builder {
        Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000), world: GameWorld.newGame())
    }

    func testACrossroadsIsPaintedOnEveryArm() {
        let markings = Map3DRoadMarkings(crossroads)
        XCTAssertEqual(markings.junctions, [Point(x: 0, z: 0)])
        let crosswalks = markings.marks.filter { $0.kind == .crosswalk }, stops = markings.marks.filter { $0.kind == .stopLine }
        XCTAssertEqual(crosswalks.count, 4)
        XCTAssertEqual(stops.count, 4)
        XCTAssertEqual(markings.signals.count, 4)
        for crosswalk in crosswalks {
            let distance = Map3DRoadMarkings.distance(crosswalk.centre, Point(x: 0, z: 0))
            let alongX = abs(crosswalk.along.x) > 0.9
            // Across its own road, kerb to kerb, 3 m back from the
            // crossing road's kerb (decision 447, the rules' 第 185 條;
            // secondary 8 m, primary 9 m).
            XCTAssertEqual(crosswalk.width, alongX ? 9 : 8)
            let crossing = alongX ? 4.0 : 4.5
            XCTAssertEqual(distance - crosswalk.length / 2, crossing + Map3DRoadMarkings.kerbGap, accuracy: 1e-9)
            // Read by the traffic going in.
            XCTAssertLessThan(Map3DRoadMarkings.dot(crosswalk.along, crosswalk.centre), 0)
        }
        for stop in stops {
            // Across the incoming half only: Taiwan keeps right, so the
            // right of the way in.
            let right = Point(x: -stop.along.z, z: stop.along.x)
            XCTAssertGreaterThan(Map3DRoadMarkings.dot(right, stop.centre), 0.5)
            let crosswalk = crosswalks.first { Map3DRoadMarkings.dot($0.along, stop.along) > 0.99 }!
            XCTAssertGreaterThan(Map3DRoadMarkings.dot(crosswalk.centre, stop.along) - Map3DRoadMarkings.dot(stop.centre, stop.along),
                                 Map3DRoadMarkings.crosswalkDepth / 2 + Map3DRoadMarkings.stopGap - 1e-9, "the stop line before the crossing")
        }
        // The main road's signals both ways, the other road's apart
        // (decision 429: in turn; before, green and red).
        for signal in markings.signals {
            XCTAssertEqual(signal.road, abs(signal.along.x) > 0.9 ? .main : .cross)
            // At the kerb on the right of the way in, off the road.
            let right = Point(x: -signal.along.z, z: signal.along.x)
            let half = abs(signal.along.x) > 0.9 ? 4.5 : 4.0
            XCTAssertGreaterThan(Map3DRoadMarkings.dot(right, signal.foot), half)
        }
        // One lane each way on these roads: a through arrow each.
        let arrows = markings.marks.filter { if case .arrow = $0.kind { return true } else { return false } }
        XCTAssertEqual(arrows.count, 4)
        XCTAssertTrue(arrows.allSatisfy { $0.kind == .arrow(left: false) })
    }

    /// Decision 429: which of a junction's signals face its main road, as
    /// the green ones did (the widest road and those nearly in line with
    /// it), and one group of the clock's for all its signals.
    func testEachJunctionsSignalsFaceItsMainRoadOrTheOther() {
        // A slanting secondary road (30° off the trunk) and a tertiary one
        // crossing them both: the trunk and what is in line with it main.
        let slant = (x: cos(Double.pi / 6) * 200, z: sin(Double.pi / 6) * 200)
        let roads = [road(.trunk, [(-200, 0), (0, 0), (200, 0)]), road(.secondary, [(0, 0), (slant.x, slant.z)]),
                     road(.tertiary, [(0, -200), (0, 0), (0, 200)])]
        let markings = Map3DRoadMarkings(roads)
        XCTAssertEqual(markings.signals.count, 5)
        for signal in markings.signals {
            // As decision 355's green: in line with the widest arm (|cos| ≥ 0.7).
            XCTAssertEqual(signal.road == .main, abs(signal.along.x) >= 0.7, "\(signal.along)")
        }
        XCTAssertEqual(markings.signals.filter { $0.road == .main }.count, 3)
        // A grid of crossroads: each junction's signals in one group, the
        // same as the junction's own, and the junctions not all alike.
        var grid: [Map3DBaseMap.Road] = []
        for line in 0..<5 {
            let at = Double(line) * 300
            grid.append(road(.primary, [(-300, at), (1_500, at)]))
            grid.append(road(.secondary, [(at, -300), (at, 1_500)]))
        }
        // Each road cut at the junctions, as the base map's tiles end.
        grid = grid.flatMap { road -> [Map3DBaseMap.Road] in
            let a = road.points[0], b = road.points[1], alongX = a.z == b.z
            return (0..<6).map { piece in
                let from = Double(piece) * 300 - 300, to = from + 300
                return self.road(road.kind, alongX ? [(from, a.z), (to, a.z)] : [(a.x, from), (a.x, to)])
            }
        }
        let crossings = Map3DRoadMarkings(grid)
        XCTAssertEqual(crossings.junctions.count, 25)
        var groups: [Int] = []
        for junction in crossings.junctions {
            let near = crossings.signals.filter { Map3DRoadMarkings.distance($0.foot, junction) < 40 }
            XCTAssertEqual(near.count, 4)
            XCTAssertEqual(Set(near.map(\.group)), [Map3DSignalTiming.group(at: junction)])
            groups.append(Map3DSignalTiming.group(at: junction))
        }
        XCTAssertGreaterThan(Set(groups).count, 1, "neighbours not all alike")
        // Where the scene's origin is does not move a junction's group.
        let moved = Map3DRoadMarkings(grid, origin: Point(x: 0, z: 0))
        XCTAssertEqual(moved.signals.map(\.group), crossings.signals.map(\.group))
        let east = Map3DRoadMarkings(grid.map { road in
            Map3DBaseMap.Road(kind: road.kind, isRamp: false, points: road.points.map { Point(x: $0.x - 1_000, z: $0.z + 500) }, bounds: everywhere)
        }, origin: Point(x: 1_000, z: -500))
        XCTAssertEqual(east.signals.map(\.group), crossings.signals.map(\.group))
    }

    func testAWideRoadHasTwoLanesOfArrows() {
        let markings = Map3DRoadMarkings([road(.trunk, [(-200, 0), (0, 0), (200, 0)]), road(.secondary, [(0, 0), (0, 200)])])
        let arrows = markings.marks.filter { if case .arrow = $0.kind { return abs($0.along.x) > 0.9 } else { return false } }
        // Two arms of the trunk road, two lanes each: the inner one
        // (nearer the centre line) through and left.
        XCTAssertEqual(arrows.count, 4)
        for arrow in arrows {
            let right = Point(x: -arrow.along.z, z: arrow.along.x)
            let out = Map3DRoadMarkings.dot(right, arrow.centre)
            XCTAssertEqual(arrow.kind == .arrow(left: true), out < 2.75, "\(arrow.centre)")
        }
    }

    func testOnlyRealJunctionsArePainted() {
        // One road in two ways meeting end to end: no junction (only the
        // kerb lines and a lane's walkway, decision 447).
        func junctionPaint(_ markings: Map3DRoadMarkings) -> [Map3DRoadMarkings.Mark] {
            markings.marks.filter {
                switch $0.kind {
                case .kerb, .walkway: false
                default: true
                }
            }
        }
        XCTAssertTrue(junctionPaint(Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0)]), road(.primary, [(0, 0), (200, 0)])])).isEmpty)
        // A lane (no centre line) joining a main road: none either.
        XCTAssertTrue(junctionPaint(Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0), (200, 0)]), road(.minor, [(0, 0), (0, 200)])])).isEmpty)
        // A T junction of two main roads: three arms.
        let tee = Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0), (200, 0)]), road(.tertiary, [(0, 0), (0, 200)])])
        XCTAssertEqual(tee.marks.filter { $0.kind == .crosswalk }.count, 3)
        XCTAssertEqual(tee.signals.count, 3)
        // The same road twice (two tiles of the base map): the same paint.
        let twice = Map3DRoadMarkings(crossroads + crossroads)
        XCTAssertEqual(junctionPaint(twice).count, junctionPaint(Map3DRoadMarkings(crossroads)).count)
        // An arm too short for its crossing and stop line gets none.
        let short = Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0), (200, 0)]), road(.secondary, [(0, 0), (0, 14)])])
        XCTAssertEqual(short.marks.filter { $0.kind == .crosswalk }.count, 2)
    }

    // MARK: Decision 447

    private func boxLines(_ markings: Map3DRoadMarkings, turn: Bool) -> [Map3DRoadMarkings.Mark] {
        markings.marks.filter { $0.kind == .scooterBox(turn: turn) }
    }

    /// Decision 447: the zebra's bars and the scooter box, by the rules'
    /// 第 185、174-2 條.
    func testTheCrossingAndTheScooterBoxFollowTheRules() {
        XCTAssertEqual(Map3DRoadMarkings.crosswalkPitch / 2, 0.4, "bars 40 cm")
        XCTAssertTrue((0.4...0.8).contains(Map3DRoadMarkings.crosswalkPitch / 2), "40–80 cm apart")
        XCTAssertTrue((3.0...5.0).contains(Map3DRoadMarkings.kerbGap))
        XCTAssertTrue((2.5...6.0).contains(Map3DRoadMarkings.scooterBoxDepth))
        let markings = Map3DRoadMarkings(crossroads)
        // Both roads 8 m or wider: a box on every arm, its front line and
        // two sides.
        let boxes = boxLines(markings, turn: false)
        XCTAssertEqual(boxes.count, 12)
        let crosswalks = markings.marks.filter { $0.kind == .crosswalk }, stops = markings.marks.filter { $0.kind == .stopLine }
        for stop in stops {
            let way = stop.along, crosswalk = crosswalks.first { Map3DRoadMarkings.dot($0.along, way) > 0.99 }!
            let mine = boxes.filter { Map3DRoadMarkings.dot($0.along, way) > 0.99 }
            XCTAssertEqual(mine.count, 3)
            // Between the crossing and the cars' stop line: the front line
            // 2 m behind the crossing, the box 3 m deep.
            let crossingBack = Map3DRoadMarkings.dot(crosswalk.centre, way) - crosswalk.length / 2
            let front = mine.first { $0.length == Map3DRoadMarkings.scooterBoxFront }!
            XCTAssertEqual(crossingBack - (Map3DRoadMarkings.dot(front.centre, way) + front.length / 2), Map3DRoadMarkings.stopGap, accuracy: 1e-9)
            XCTAssertEqual(Map3DRoadMarkings.dot(front.centre, way) + front.length / 2 - (Map3DRoadMarkings.dot(stop.centre, way) + stop.length / 2),
                           Map3DRoadMarkings.scooterBoxDepth, accuracy: 1e-9)
            // Over the incoming half, on the right of the way in.
            let right = Point(x: -way.z, z: way.x)
            for line in mine { XCTAssertGreaterThan(Map3DRoadMarkings.dot(right, line.centre), 0) }
        }
        // A tertiary road (7 m) has none: its stop line right behind the
        // crossing as before.
        let tee = Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0), (200, 0)]), road(.tertiary, [(0, 0), (0, 200)])])
        XCTAssertEqual(boxLines(tee, turn: false).count, 6, "the primary road's two arms only")
    }

    /// Decision 447: the two-stage turn box (第 191 條), in the corner:
    /// between the crossing road's kerb and the crossing, 0.5 m clear of
    /// it, by the kerb of the incoming half.
    func testTheTurnBoxWaitsInTheCornerBeforeTheCrossing() {
        let markings = Map3DRoadMarkings(crossroads)
        let lines = boxLines(markings, turn: true)
        XCTAssertEqual(lines.count, 16, "four lines on each of four arms")
        for line in lines {
            let way = line.along, right = Point(x: -way.z, z: way.x)
            let crosswalk = markings.marks.first { $0.kind == .crosswalk && Map3DRoadMarkings.dot($0.along, way) > 0.99 }!
            let near = Map3DRoadMarkings.dot(crosswalk.centre, way) + crosswalk.length / 2
            // Junction side of the crossing, clear of it by 0.5 m, outside
            // the crossing road (its half 4 or 4.5 m).
            let along = -Map3DRoadMarkings.dot(line.centre, way)
            XCTAssertLessThanOrEqual(along + line.length / 2, -near - Map3DRoadMarkings.turnBoxGap + 1e-9)
            XCTAssertGreaterThan(along - line.length / 2, 4.5 - 1e-9)
            XCTAssertGreaterThan(Map3DRoadMarkings.dot(right, line.centre), 0)
        }
    }

    /// Decision 447: the kerb lines (第 168、169 條): red along the trunk
    /// and primary roads, yellow along the others but red within 10 m of
    /// a junction; none across a side road's mouth or the junction's
    /// paint, none on a lane.
    func testKerbLinesAreRedOnMainRoadsAndNearJunctions() {
        func kerbs(_ markings: Map3DRoadMarkings) -> [Map3DRoadMarkings.Mark] {
            markings.marks.filter { if case .kerb = $0.kind { return true } else { return false } }
        }
        // (The lane meets the primary road at one of its points, as the
        // base map's roads meet.)
        let tee = Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0), (100, 0), (200, 0)]), road(.secondary, [(0, 0), (0, 200)]),
                                     road(.minor, [(100, 0), (100, -100)])])
        let lines = kerbs(tee)
        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            XCTAssertEqual(line.width, Map3DRoadMarkings.kerbWidth)
            let alongX = abs(line.along.x) > 0.9
            if alongX {
                // The primary road: red, 0.15 m in from either edge.
                XCTAssertEqual(line.kind, .kerb(red: true))
                XCTAssertEqual(abs(line.centre.z), 4.5 - Map3DRoadMarkings.kerbInset, accuracy: 1e-9)
                // Not across the secondary road's mouth (its north side)
                // nor the lane's (its south side).
                let from = line.centre.x - line.length / 2, to = line.centre.x + line.length / 2
                if line.centre.z > 0 { XCTAssertTrue(to <= -4 || from >= 4, "\(from)…\(to)") }
                if line.centre.z < 0 { XCTAssertTrue(to <= 97.5 || from >= 102.5, "\(from)…\(to)") }
            } else {
                // The secondary road: none before its junction's paint
                // ends, red for 10 m on, yellow on from there.
                let from = line.centre.z - line.length / 2, to = line.centre.z + line.length / 2
                let crosswalk = tee.marks.first { $0.kind == .crosswalk && abs($0.along.z) > 0.9 }!
                let paintEnds = crosswalk.centre.z + crosswalk.length / 2
                XCTAssertGreaterThanOrEqual(from, paintEnds - 1e-9)
                XCTAssertEqual(line.kind, .kerb(red: to <= paintEnds + Map3DRoadMarkings.redNearJunction + 1e-9), "\(from)…\(to)")
            }
        }
        XCTAssertTrue(lines.contains { $0.kind == .kerb(red: false) })
        // A lane alone, or a road on a bridge: none.
        XCTAssertTrue(kerbs(Map3DRoadMarkings([road(.minor, [(-200, 0), (200, 0)])])).isEmpty)
        let bridge = Map3DBaseMap.Road(kind: .primary, isRamp: false, points: [Point(x: -200, z: 0), Point(x: 200, z: 0)], bounds: everywhere,
                                       bridgeLevel: 1)
        XCTAssertTrue(kerbs(Map3DRoadMarkings([bridge])).isEmpty)
        // A road from two tiles: each tile's lines inside its own bounds.
        let west = Map3DBaseMap.Bounds(minX: -10_000, minZ: -10_000, maxX: 0, maxZ: 10_000)
        let east = Map3DBaseMap.Bounds(minX: 0, minZ: -10_000, maxX: 10_000, maxZ: 10_000)
        let points = [Point(x: -200, z: 0), Point(x: 200, z: 0)]
        let split = kerbs(Map3DRoadMarkings([Map3DBaseMap.Road(kind: .secondary, isRamp: false, points: points, bounds: west),
                                             Map3DBaseMap.Road(kind: .secondary, isRamp: false, points: points, bounds: east)]))
        XCTAssertEqual(split.reduce(0) { $0 + $1.length }, 2 * 400, accuracy: 1e-6)
    }

    /// Decision 447 (continued): the pedestrians' space by the road's
    /// class, and a lane's painted walkway on one side, the same from
    /// every tile, stopping at the mouths of the roads it meets.
    func testALaneHasAPaintedWalkwayOnOneSide() {
        XCTAssertEqual(Map3DRoadMarkings.walkway(road(.primary, [(0, 0), (1, 0)])), .pavement)
        XCTAssertEqual(Map3DRoadMarkings.walkway(road(.tertiary, [(0, 0), (1, 0)])), .pavement)
        XCTAssertEqual(Map3DRoadMarkings.walkway(road(.minor, [(0, 0), (1, 0)])), .painted)
        XCTAssertEqual(Map3DRoadMarkings.walkway(road(.service, [(0, 0), (1, 0)])), .shared)
        XCTAssertEqual(Map3DRoadMarkings.walkway(road(.motorway, [(0, 0), (1, 0)])), .none)
        XCTAssertEqual(Map3DRoadMarkings.walkway(Map3DBaseMap.Road(kind: .minor, isRamp: false, points: [Point(x: 0, z: 0), Point(x: 1, z: 0)],
                                                                   bounds: everywhere, bridgeLevel: 1)), .none)
        XCTAssertTrue((1.1...1.8).contains(Map3DRoadMarkings.walkwayBand))
        let lane = road(.minor, [(0, 0), (0, 200)])
        let markings = Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0), (200, 0)]), lane])
        let walkway = markings.marks.filter { if case .walkway = $0.kind { return true } else { return false } }
        XCTAssertEqual(walkway.filter { $0.kind == .walkway(line: false) }.count, 1)
        XCTAssertEqual(walkway.filter { $0.kind == .walkway(line: true) }.count, 2)
        let side = Map3DRoadMarkings.walkwaySide(lane, origin: Point(x: 0, z: 0))
        for mark in walkway {
            // Along the lane, on its one side, inside its 5 m.
            XCTAssertEqual(abs(mark.along.z), 1, accuracy: 1e-9)
            XCTAssertEqual((mark.centre.x > 0 ? 1.0 : -1.0), side * (mark.along.z > 0 ? -1 : 1))
            XCTAssertLessThanOrEqual(abs(mark.centre.x) + mark.width / 2, 2.5 + 1e-9)
            // Not across the primary road: from its kerb and a metre on.
            XCTAssertGreaterThanOrEqual(mark.centre.z - mark.length / 2, 4.5 + 1 - 1e-9)
        }
        // The same lane from another tile keeps its side; a service road
        // has none.
        XCTAssertEqual(Map3DRoadMarkings.walkwaySide(lane, origin: Point(x: 0, z: 0)), side)
        XCTAssertTrue(Map3DRoadMarkings([road(.service, [(0, 0), (0, 200)])]).marks.isEmpty)
    }

    /// Decision 447 (continued): Taipei's arcade, 3.64 m from the road's
    /// line (臺北市建築管理自治條例第 7 條).
    func testTheArcadeIsTaipeisDepth() {
        XCTAssertEqual(Builder.arcadeDepth, 3.64)
    }

    func testTheCentreLineStopsAtTheCrossing() {
        let roads = crossroads, markings = Map3DRoadMarkings(roads)
        let pieces = markings.centreLines(of: roads[0], number: 0)
        XCTAssertEqual(pieces.count, 2)
        let crosswalks = markings.marks.filter { $0.kind == .crosswalk && abs($0.along.x) > 0.9 }
        for piece in pieces {
            for point in piece {
                // Nowhere nearer the junction than the crossings' far edges.
                XCTAssertGreaterThanOrEqual(abs(point.x), crosswalks.map { abs($0.centre.x) + $0.length / 2 }.min()! - 1e-9)
            }
        }
        // The road's ends kept.
        XCTAssertEqual(Set(pieces.flatMap { [$0.first!.x, $0.last!.x] }.filter { abs($0) == 200 }), [-200, 200])
        // A road at no junction keeps its whole line.
        let alone = road(.primary, [(-200, 500), (200, 500)])
        XCTAssertEqual(Map3DRoadMarkings([alone]).centreLines(of: alone, number: 0).map(\.count), [2])
    }

    func testThePaintLiesOnTheRoadsWithItsLayers() {
        var builder = builder(), taken = Set<Map3DScene.ChunkKey>()
        builder.addRoads(crossroads, taking: &taken)
        let vertices = builder.nearMeshes.values.flatMap(\.vertices)
        let crosswalk = vertices.filter { $0.surface == .crosswalk }, arrows = vertices.filter { $0.surface == .laneArrows }
        XCTAssertFalse(crosswalk.isEmpty)
        XCTAssertFalse(arrows.isEmpty)
        let painted = crosswalk + arrows + vertices.filter { $0.color == Builder.paint }
        // At the centre lines' height over the drawn ground, facing up,
        // over every road (decision 241's order) and under the shadows.
        for vertex in painted {
            XCTAssertEqual(vertex.y - builder.drawnGround(x: vertex.x, z: vertex.z), Builder.centreLineLift, accuracy: 1e-3)
            XCTAssertGreaterThan(vertex.ny, 0.99)
        }
        XCTAssertGreaterThan(Builder.centreLineLift, Builder.lift(of: .motorway))
        XCTAssertLessThan(Builder.centreLineLift, Map3DShadow.lift)
        // The bars start and end at a gap's middle, whole bars between.
        XCTAssertEqual(crosswalk.map(\.u).min(), 0)
        XCTAssertEqual(crosswalk.map(\.u).max(), 11, "9 m of primary road: eleven bars 0.4 m wide, 0.4 m apart (decision 447)")
        // Arrows show one of the layer's two halves.
        XCTAssertTrue(arrows.allSatisfy { $0.u >= -1e-4 && $0.u <= 0.5 + 1e-4 })
        // None in the base mesh: near detail only.
        XCTAssertTrue(builder.meshes.values.flatMap(\.vertices).allSatisfy { $0.surface != .crosswalk && $0.surface != .laneArrows })
    }

    func testSignalsBusStopsAndVendingMachinesStandOnThePavement() throws {
        var builder = builder(), taken = Set<Map3DScene.ChunkKey>()
        let long = road(.primary, [(-2_000, 0), (0, 0), (2_000, 0)])
        builder.addRoads([long, road(.secondary, [(0, -400), (0, 0), (0, 400)])], taking: &taken)
        let instances = builder.props.values.flatMap { $0 }
        func count(_ prop: Map3DProp) -> Int { instances.filter { $0.model == Builder.propModels[prop] }.count }
        XCTAssertEqual(count(.signalGo) + count(.signalStop), 4)
        XCTAssertEqual(count(.signalGo), 2)
        // Decision 429: placed as they stand when the clock does not change
        // them (the main road green), each with its junction's group.
        XCTAssertEqual(count(.signalAmber), 0)
        let signals = instances.filter { [Builder.propModels[.signalGo], Builder.propModels[.signalStop]].contains($0.model) }
        XCTAssertEqual(Set(signals.map(\.group)), [Map3DSignalTiming.group(at: Point(x: 0, z: 0))])
        // Everything else in group 0, but the pedestrian signals (decision
        // 445), whose groups also say which road they walk beside.
        let walks = try XCTUnwrap(Builder.walkModels)
        XCTAssertTrue(instances.filter { !signals.map(\.transform).contains($0.transform) && !walks.places($0.model) }.allSatisfy { $0.group == 0 })
        // 4 km of primary road, a stop every 420 m, none at the junction.
        XCTAssertGreaterThanOrEqual(count(.busStop), 8)
        XCTAssertGreaterThan(count(.vending), 0)
        let furniture = Set([Map3DProp.tree, .lamp, .pole].compactMap { Builder.propModels[$0] })
        for stop in instances where stop.model == Builder.propModels[.busStop] {
            let x = stop.transform[12], z = stop.transform[14]
            // On the pavement beside the road (4.5 m half, 3 m pavement),
            // its open side toward the road (the model's +y).
            if abs(z) < 50 {
                XCTAssertEqual(abs(z), 4.5 + 3 - 1.05, accuracy: 1e-3)
                XCTAssertLessThan(stop.transform[6] * (z < 0 ? -1 : 1), 0, "faces the road")
            }
            // No tree or light inside it.
            for other in instances where furniture.contains(other.model) {
                let dx = other.transform[12] - x, dz = other.transform[14] - z
                XCTAssertGreaterThanOrEqual(dx * dx + dz * dz, 9 - 1e-3)
            }
            XCTAssertGreaterThan(Map3DRoadMarkings.distance(Point(x: Double(x), z: Double(z)), Point(x: 0, z: 0)), Builder.stopClearOfJunctions - 1)
        }
        // The same every time.
        var again = self.builder()
        taken = []
        again.addRoads([long, road(.secondary, [(0, -400), (0, 0), (0, 400)])], taking: &taken)
        func sorted(_ props: [Map3DScene.ChunkKey: [Map3DInstance]]) -> [[Float]] {
            props.values.flatMap { $0 }.map(\.transform).sorted { $0.lexicographicallyPrecedes($1) }
        }
        XCTAssertEqual(sorted(again.props), sorted(builder.props))
    }

    func testTheNewModelsAreSmall() throws {
        let pack = Map3DModelPack.standard
        var sizes: [String: Int] = [:]
        for prop in [Map3DProp.signalGo, .signalStop, .signalAmber, .busStop, .vending] {
            let model = try XCTUnwrap(pack.models.first { $0.name == prop.modelName })
            sizes[prop.rawValue] = model.triangleCount
            XCTAssertLessThanOrEqual(model.triangleCount, 300, prop.rawValue)
            // Standing on its foot.
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.01, prop.rawValue)
        }
        print("Decision 355 models' triangles:", sizes.sorted { $0.key < $1.key })
        // The signal's arm and head reach over the road (+y), its lit
        // light glowing.
        let signal = try XCTUnwrap(pack.models.first { $0.name == Map3DProp.signalGo.modelName })
        XCTAssertGreaterThan(signal.maximum.y, 3.5)
        XCTAssertTrue(signal.vertices.contains { $0.glows })
        // A bus stop's shelter shallow enough for a pavement, open toward
        // the road; the vending machine's body takes the instance colour.
        let stop = try XCTUnwrap(pack.models.first { $0.name == Map3DProp.busStop.modelName })
        XCTAssertLessThan(stop.maximum.y - stop.minimum.y, 2.2)
        let vending = try XCTUnwrap(pack.models.first { $0.name == Map3DProp.vending.modelName })
        XCTAssertTrue(vending.vertices.contains { $0.color >> 24 == 0 })
        XCTAssertGreaterThan(vending.maximum.y, 0.4, "its front toward the road")
        // The power-saving look leaves the small things out.
        XCTAssertEqual(Map3DProp.modelsLeftOut(.saving).count, 2)
        XCTAssertTrue(Map3DProp.modelsLeftOut(.automatic).isEmpty)
        XCTAssertTrue(Map3DProp.modelsLeftOut(.high).isEmpty)
    }
}

/// Decision 355's numbers on the real-world Taipei map
/// (``Map3DFrameCostReportTests/taipeiScene(bands:)``): the paint's
/// vertices and the new furniture a chunk. Only on request:
/// `MAP3D_FRAME_REPORT=1`.
final class Map3DRoadMarkingReportTests: XCTestCase {
    func testTheTaipeiCounts() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let scene = try Map3DFrameCostReportTests.taipeiScene()
        let pack = Map3DModelPack.standard
        let new = [Map3DProp.signalGo, .signalStop, .busStop, .vending].map { ($0, pack.index(of: $0.modelName)!) }
        var paint = 0, chunksWithPaint = 0, instances = [Map3DProp: Int](), models = 0, mostModels = 0
        for chunk in scene.chunks {
            let painted = chunk.mesh.vertices.filter { $0.surface == .crosswalk || $0.surface == .laneArrows }.count
            paint += painted
            if painted > 0 { chunksWithPaint += 1 }
            var here = 0
            for (prop, model) in new {
                let count = chunk.props.filter { $0.model == model }.count
                instances[prop, default: 0] += count
                if count > 0 { here += 1 }
            }
            models += here
            mostModels = max(mostModels, here)
        }
        let triangles = new.reduce(0) { $0 + pack.models[$1.1].triangleCount * instances[$1.0, default: 0] }
        print("chunks: \(scene.chunks.count), with crossing or arrow paint: \(chunksWithPaint), their vertices: \(paint) (\(paint / 4) quads at most)")
        print("instances: \(instances.sorted { $0.key.rawValue < $1.key.rawValue }), triangles all drawn: \(triangles)")
        print("new draw calls if every chunk were detailed: \(models), most in one chunk: \(mostModels)")
        // What one frame draws more, the chunks in full only.
        for distance in [800, 280] as [Float] {
            let camera = Map3DCamera(target: .zero, distance: distance, viewport: (402, 874))
            var detailed = 0, draws = 0, drawn = 0, saving = 0, vertices = 0
            for chunk in scene.chunks where Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: camera.viewProjection)
                && camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum, wasDetailed: false) {
                detailed += 1
                vertices += chunk.mesh.vertices.filter { $0.surface == .crosswalk || $0.surface == .laneArrows }.count
                for (prop, model) in new {
                    let count = chunk.props.filter { $0.model == model }.count
                    guard count > 0 else { continue }
                    draws += 1
                    drawn += pack.models[model].triangleCount * count
                    if !Map3DProp.leftOutWhenSaving.contains(prop) { saving += pack.models[model].triangleCount * count }
                }
            }
            print("\(distance) m: \(detailed) chunks in full, +\(draws) draw calls, +\(drawn) furniture triangles (Saving \(saving)), \(vertices) crossing and arrow vertices")
        }
        // Decision 429: the signals' draw calls, one a model (decision 355)
        // and one a model and junction group (Map3DPropRuns).
        let signalModels = Set([Map3DProp.signalGo, .signalStop].compactMap { pack.index(of: $0.modelName) })
        var byModel = 0, byGroup = 0, most = 0
        for chunk in scene.chunks {
            let runs = Map3DPropRuns(chunk.props)
            byModel += runs.shapes.filter { signalModels.contains($0.model) }.count
            let here = runs.runs.filter { signalModels.contains($0.model) }.count
            byGroup += here
            most = max(most, here)
        }
        print("signal draw calls if every chunk were detailed: \(byModel) by model, \(byGroup) by model and group, most in one chunk \(most)")
        for distance in [800, 280] as [Float] {
            let camera = Map3DCamera(target: .zero, distance: distance, viewport: (402, 874))
            var before = 0, after = 0
            for chunk in scene.chunks where Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: camera.viewProjection)
                && camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum, wasDetailed: false) {
                let runs = Map3DPropRuns(chunk.props)
                before += runs.shapes.filter { signalModels.contains($0.model) }.count
                after += runs.runs.filter { signalModels.contains($0.model) }.count
            }
            print("\(distance) m: signal draw calls \(before) → \(after)")
        }
        // Decision 445: the pedestrian signals, three instances each, drawn
        // only close up: their instances, and a frame's draw calls and
        // most triangles (the budget's).
        let walks = try XCTUnwrap(Map3DScene.Builder.walkModels)
        let heads = scene.chunks.reduce(0) { $0 + $1.props.filter { $0.model == walks.placed.head }.count }
        print("pedestrian signals: \(heads), a face and two digits each")
        for distance in [800, 280, 120] as [Float] {
            let camera = Map3DCamera(target: .zero, distance: distance, viewport: (402, 874))
            var close = 0, draws = 0, triangles = 0
            for chunk in scene.chunks where Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: camera.viewProjection)
                && camera.drawsClose(minimum: chunk.minimum, maximum: chunk.maximum, detailed: true, coarse: false) {
                close += 1
                let runs = Map3DPropRuns(chunk.props).runs
                draws += runs.filter { walks.places($0.model) }.count
                triangles += walks.triangles(runs, in: pack)
            }
            print("\(distance) m: \(close) chunks close up, pedestrian signal draw calls at most \(draws), triangles at most \(triangles)")
        }
        // Decision 447: the near meshes' triangles (where the crossings,
        // boxes and kerb lines are; no draw call of their own), the whole
        // scene and a frame's chunks in full.
        let near = scene.chunks.reduce(0) { $0 + $1.mesh.triangleCount - $1.baseIndexCount / 3 }
        print("near triangles, all chunks: \(near)")
        for distance in [800, 280, 120] as [Float] {
            let camera = Map3DCamera(target: .zero, distance: distance, viewport: (402, 874))
            var detailed = 0, triangles = 0
            for chunk in scene.chunks where Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: camera.viewProjection)
                && camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum, wasDetailed: false) {
                detailed += 1
                triangles += chunk.mesh.triangleCount - chunk.baseIndexCount / 3
            }
            print("\(distance) m: \(detailed) chunks in full, near triangles \(triangles)")
        }
    }
}
