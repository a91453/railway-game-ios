import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 342: the buildings between the eye and the player's trains
/// are seen through (``Map3DSeeThrough``).
final class Map3DSeeThroughTests: XCTestCase {
    /// A car on the rails at the middle, the eye south of it and up.
    let car = Map3DPoint(0, Map3DScene.railLift, 0)
    let eye = Map3DPoint(0, 90, 100)

    func seeThrough(cars: [Map3DPoint]? = nil) -> Map3DSeeThrough {
        let camera = Map3DCamera(target: car, distance: 134, viewport: (402, 874))
        return Map3DSeeThrough(eye: camera.eye, cars: cars ?? [car], matrix: camera.viewProjection)
    }

    func testABuildingInFrontOfTheCarIsSeenThroughAndNothingElse() {
        let see = seeThrough()
        let eye = see.eye
        let middle = car + Map3DPoint(0, Map3DSeeThrough.bodyMiddle, 0)
        // On the line from the eye, halfway: seen through.
        let between = eye + (middle - eye) * 0.5
        XCTAssertEqual(see.opacity(at: between), Map3DSeeThrough.opacity)
        // Well off the line: as it is.
        XCTAssertEqual(see.opacity(at: between + Map3DPoint(60, 0, 0)), 1)
        // Behind the car, and beside it: as they are.
        XCTAssertEqual(see.opacity(at: middle + (middle - eye) * 0.2), 1)
        XCTAssertEqual(see.opacity(at: middle + Map3DPoint(6, 0, 0)), 1)
        // The ground and the road round the car, under its clearance.
        XCTAssertEqual(see.opacity(at: Map3DPoint(0, 0.36, 10)), 1)
        // At the rim, between.
        let rim = see.opacity(at: between + Map3DPoint(Map3DSeeThrough.radius * 0.5 * 0.85, 0, 0))
        XCTAssertGreaterThan(rim, Map3DSeeThrough.opacity)
        XCTAssertLessThan(rim, 1)
    }

    func testOnlyChunksTheConesCrossAreDrawnSeeThrough() {
        let see = seeThrough()
        // A block of towers between the eye and the car.
        XCTAssertTrue(see.cuts(minimum: Map3DPoint(-20, 0, 30), maximum: Map3DPoint(20, 40, 50)))
        // Behind the car, off to the side, or low under the rails.
        XCTAssertFalse(see.cuts(minimum: Map3DPoint(-20, 0, -300), maximum: Map3DPoint(20, 40, -200)))
        XCTAssertFalse(see.cuts(minimum: Map3DPoint(200, 0, 30), maximum: Map3DPoint(260, 40, 50)))
        XCTAssertFalse(see.cuts(minimum: Map3DPoint(-20, 0, 30), maximum: Map3DPoint(20, 0.4, 50)))
        // No car: nothing.
        XCTAssertFalse(seeThrough(cars: []).cuts(minimum: Map3DPoint(-20, 0, 30), maximum: Map3DPoint(20, 40, 50)))
    }

    func testTheCarsNearestTheMiddleOfTheViewAndInReachAreChosen() {
        let far = car + Map3DPoint(0, 0, -2_000)
        let aside = car + Map3DPoint(10, 0, 0)
        let many = (0..<30).map { car + Map3DPoint(Float($0) - 15, 0, 0) }
        XCTAssertEqual(seeThrough(cars: [aside, far, car]).cars, [car, aside], "the middle first; none out of reach")
        XCTAssertEqual(seeThrough(cars: many).cars.count, Map3DSeeThrough.most)
        XCTAssertEqual(seeThrough(cars: many).floats.count, Map3DSeeThrough.most * 4 + 8)
    }

    // MARK: - The measurement in the decision

    /// How often a building hides the player's train on the real-world
    /// Taipei map, and how often the see-through shows it: a car at every
    /// 100 m of a 10 km line across the city, seen by the map's camera at
    /// 120 m and 280 m from four sides and by the follow camera from
    /// behind and from above behind. A car is hidden when the line from
    /// the eye to its body's middle meets a triangle of the city (the
    /// near and close meshes) over its rails. Only on request:
    /// `MAP3D_FRAME_REPORT=1`.
    func testTheOcclusionReport() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let baseMap = Map3DFrameCostReportTests.baseMap
        let world = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!)
        let tiles = try BaseMapTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let empty = Map3DScene(world: world, baseMap: tiles, cityTiles: [])
        let across = Int64(5_000 * WorldCoordinate.unitsPerMetre)
        let middle = (x: Int64(empty.originX), y: Int64(empty.originY))
        let line = try LineBuilder.line(through: [PlanPoint(x: middle.x - across, y: middle.y - across / 2),
                                                  PlanPoint(x: middle.x, y: middle.y),
                                                  PlanPoint(x: middle.x + across, y: middle.y + across / 2)], in: world)
        let temples = try RealTemples(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_temples.json")))
        let scene = Map3DScene(world: line, baseMap: tiles, cityTiles: CityTileArea.areas(in: baseMap.appendingPathComponent("city")),
                               lineBands: Map3DLineBands(world: line, palette: .standard), temples: temples)
        // The rails every 100 m, and the way they run.
        var cars: [(rail: Map3DPoint, forward: Map3DPoint)] = []
        for alignment in line.railwaySnapshot().edges {
            let points = alignment.geometry.points.map { scene.point($0) + Map3DPoint(0, Map3DScene.railLift, 0) }
            var left: Float = 0
            for (a, b) in zip(points, points.dropFirst()) {
                let length = (b - a).length
                guard length > 0 else { continue }
                var at = left
                while at < length {
                    cars.append((a + (b - a) * (at / length), Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized ?? Map3DPoint(0, 0, -1)))
                    at += 100
                }
                left = at - length
            }
        }
        print("cars: \(cars.count) along the line")
        var cameras: [(name: String, make: (Map3DPoint, Map3DPoint) -> Map3DCamera)] = []
        for distance: Float in [120, 280] {
            for quarter in 0..<4 {
                cameras.append(("map \(Int(distance)) m, heading \(quarter * 90)°", { rail, _ in
                    Map3DCamera(target: rail, distance: distance, heading: Float(quarter) * .pi / 2, viewport: (402, 874))
                }))
            }
        }
        for view in [Map3DFollow.View.back, .aboveBack] {
            cameras.append(("follow, \(view)", { rail, forward in
                let head = Map3DTrains.Head(train: TrainID(rawValue: 1), point: rail + Map3DPoint(0, Map3DTrains.carHeight + Map3DTrains.headClearance, 0),
                                            forward: forward)
                return Map3DFollow(train: head.train, view: view).camera(following: head, from: Map3DCamera(viewport: (402, 874)), elapsed: 0,
                                                                          turnsAtOnce: true)
            }))
        }
        for (name, make) in cameras {
            var hidden = 0, tall = 0, shown = 0, flagged = 0
            for car in cars {
                let camera = make(car.rail, car.forward)
                let eye = camera.eye
                let middle = car.rail + Map3DPoint(0, Map3DSeeThrough.bodyMiddle, 0)
                let see = Map3DSeeThrough(eye: eye, cars: [car.rail], matrix: camera.viewProjection)
                var hits: [(point: Map3DPoint, chunk: Int)] = []
                for (index, chunk) in scene.chunks.enumerated()
                where Map3DSeeThrough.segment(from: eye, to: middle, meets: chunk.minimum, chunk.maximum) {
                    for (mesh, first) in [(chunk.mesh, chunk.baseIndexCount), (chunk.close, 0)] {
                        Self.hits(of: eye, to: middle, in: mesh, from: first, over: car.rail.y + Map3DSeeThrough.clearance) {
                            hits.append(($0, index))
                        }
                    }
                }
                guard !hits.isEmpty else { continue }
                hidden += 1
                if hits.contains(where: { $0.point.y > car.rail.y + 7 }) { tall += 1 }
                if hits.allSatisfy({ see.opacity(at: $0.point) <= Map3DSeeThrough.opacity + 0.01 }) { shown += 1 }
                if hits.allSatisfy({ see.cuts(minimum: scene.chunks[$0.chunk].minimum, maximum: scene.chunks[$0.chunk].maximum) }) { flagged += 1 }
            }
            func share(_ n: Int) -> String { String(format: "%.1f%%", Double(n) * 100 / Double(cars.count)) }
            print("\(name): hidden \(share(hidden)) (by something over 7 m \(share(tall))); seen through \(shown) of \(hidden), in chunks drawn see-through \(flagged) of \(hidden)")
        }
    }

    /// Calls `found` with where the segment from `a` to `b` (up to
    /// ``Map3DSeeThrough/beside`` short of `b`) meets each triangle of
    /// `mesh` from index `first` on, over the height `over`.
    static func hits(of a: Map3DPoint, to b: Map3DPoint, in mesh: Map3DMesh, from first: Int, over: Float, found: (Map3DPoint) -> Void) {
        let d = b - a, length = d.length
        let end = (length - Map3DSeeThrough.beside) / length
        var index = first
        while index + 2 < mesh.indices.count {
            let p0 = mesh.vertices[Int(mesh.indices[index])], p1 = mesh.vertices[Int(mesh.indices[index + 1])], p2 = mesh.vertices[Int(mesh.indices[index + 2])]
            index += 3
            let v0 = Map3DPoint(p0.x, p0.y, p0.z), v1 = Map3DPoint(p1.x, p1.y, p1.z), v2 = Map3DPoint(p2.x, p2.y, p2.z)
            guard max(v0.y, v1.y, v2.y) > over else { continue }
            let e1 = v1 - v0, e2 = v2 - v0
            let p = d.cross(e2)
            let det = e1.dot(p)
            guard abs(det) > 1e-9 else { continue }
            let s = a - v0
            let u = s.dot(p) / det
            guard u >= 0, u <= 1 else { continue }
            let q = s.cross(e1)
            let v = d.dot(q) / det
            guard v >= 0, u + v <= 1 else { continue }
            let t = e2.dot(q) / det
            guard t > 0, t < end else { continue }
            let hit = a + d * t
            if hit.y > over { found(hit) }
        }
    }
}
