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
            // Across its own road, kerb to kerb, clear of the crossing
            // road and its pavements (secondary 8 m + 3 m each side,
            // primary 9 m + 3 m).
            XCTAssertEqual(crosswalk.width, alongX ? 9 : 8)
            let crossing = alongX ? 4.0 + 3 : 4.5 + 3
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
        // The main road shows green both ways, the other red.
        for signal in markings.signals {
            XCTAssertEqual(signal.go, abs(signal.along.x) > 0.9)
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
        // One road in two ways meeting end to end: no junction.
        XCTAssertTrue(Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0)]), road(.primary, [(0, 0), (200, 0)])]).marks.isEmpty)
        // A lane (no centre line) joining a main road: none either.
        XCTAssertTrue(Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0), (200, 0)]), road(.minor, [(0, 0), (0, 200)])]).marks.isEmpty)
        // A T junction of two main roads: three arms.
        let tee = Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0), (200, 0)]), road(.tertiary, [(0, 0), (0, 200)])])
        XCTAssertEqual(tee.marks.filter { $0.kind == .crosswalk }.count, 3)
        XCTAssertEqual(tee.signals.count, 3)
        // The same road twice (two tiles of the base map): the same paint.
        let twice = Map3DRoadMarkings(crossroads + crossroads)
        XCTAssertEqual(twice.marks.count, Map3DRoadMarkings(crossroads).marks.count)
        // An arm too short for its crossing and stop line gets none.
        let short = Map3DRoadMarkings([road(.primary, [(-200, 0), (0, 0), (200, 0)]), road(.secondary, [(0, 0), (0, 14)])])
        XCTAssertEqual(short.marks.filter { $0.kind == .crosswalk }.count, 2)
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
        XCTAssertEqual(crosswalk.map(\.u).max(), 10, "9 m of primary road: ten bars")
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
        for prop in [Map3DProp.signalGo, .signalStop, .busStop, .vending] {
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
