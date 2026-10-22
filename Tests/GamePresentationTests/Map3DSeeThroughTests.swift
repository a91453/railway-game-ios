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

    func testOnlyChunksWhoseCityStandsInAConeAreDrawnSeeThrough() {
        let see = seeThrough()
        // The chunk at the middle, with a 40 m tower in the square
        // between the eye (south) and the car, or behind the car, or
        // only low things (under the clearance).
        func tops(_ square: (column: Int, row: Int)?, height: Float = 40) -> [Float] {
            var tops = [Float](repeating: -.infinity, count: Map3DSeeThrough.cells * Map3DSeeThrough.cells)
            if let square { tops[square.row * Map3DSeeThrough.cells + square.column] = height }
            return tops
        }
        XCTAssertTrue(see.cuts(column: 0, row: 0, tops: tops((0, 0))), "the square south east of the car, under the line from the eye")
        XCTAssertFalse(see.cuts(column: 0, row: -1, tops: tops((0, 6))), "north of the car, behind it")
        XCTAssertFalse(see.cuts(column: 0, row: 0, tops: tops((5, 1))), "well to the side")
        XCTAssertFalse(see.cuts(column: 0, row: 0, tops: tops((0, 0), height: 1)), "low, under the clearance")
        XCTAssertFalse(see.cuts(column: 0, row: 0, tops: tops(nil)), "no city")
        XCTAssertFalse(seeThrough(cars: []).cuts(column: 0, row: 0, tops: tops((0, 0))), "no car")
    }

    func testAChunksCityTopsAreItsTallestThings() {
        var mesh = Map3DMesh()
        mesh.addBox(base: Map3DPoint(100, 0, 100), forward: Map3DPoint(1, 0, 0), length: 10, width: 10, height: 30, top: 0xFFFFFF, side: 0xFFFFFF)
        let tops = Map3DSeeThrough.tops(column: 0, row: 0, of: [(mesh, 0)])
        XCTAssertEqual(tops[1 * Map3DSeeThrough.cells + 1], 30, accuracy: 0.01)
        XCTAssertEqual(tops.filter { $0 > 0 }.count, 1)
        XCTAssertTrue(Map3DSeeThrough.tops(column: 0, row: 0, of: [(mesh, mesh.indices.count)]).allSatisfy { $0 == -.infinity }, "from the city's first index")
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
    /// maps of Taipei, Kaohsiung and Taichung, and how often the
    /// see-through shows it: a car at every 50 m of a 10 km line across
    /// the city, seen by the map's camera at
    /// 120 m and 280 m from four sides and by the follow camera from
    /// behind and from above behind. A car is hidden when the line from
    /// the eye to its body's middle meets a triangle of the city (the
    /// near mesh: buildings, stations, temples, parks) over its rails. Only on request:
    /// `MAP3D_FRAME_REPORT=1`.
    func testTheOcclusionReport() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let baseMap = Map3DFrameCostReportTests.baseMap
        let tiles = try BaseMapTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let temples = try RealTemples(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_temples.json")))
        // Taipei Station (no real buildings), and Kaohsiung and Taichung
        // Stations, among their real buildings (decision 239).
        for (place, latitude, longitude) in [("Taipei", 25.0478, 121.5170), ("Kaohsiung", 22.6394, 120.3025), ("Taichung", 24.1372, 120.6869)] {
            try report(place, anchor: GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)!, tiles: tiles, temples: temples)
        }
    }

    func report(_ place: String, anchor: GeoAnchor, tiles: BaseMapTiles, temples: RealTemples) throws {
        let baseMap = Map3DFrameCostReportTests.baseMap
        let world = GameWorld.newGame(anchor: anchor)
        let empty = Map3DScene(world: world, baseMap: tiles, cityTiles: [])
        let across = Int64(5_000 * WorldCoordinate.unitsPerMetre)
        let middle = (x: Int64(empty.originX), y: Int64(empty.originY))
        let line = try LineBuilder.line(through: [PlanPoint(x: middle.x - across, y: middle.y - across / 2),
                                                  PlanPoint(x: middle.x, y: middle.y),
                                                  PlanPoint(x: middle.x + across, y: middle.y + across / 2)], in: world)
        let scene = Map3DScene(world: line, baseMap: tiles, cityTiles: CityTileArea.areas(in: baseMap.appendingPathComponent("city")),
                               lineBands: Map3DLineBands(world: line, palette: .standard), temples: temples)
        // The rails every 50 m, and the way they run.
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
                    at += 50
                }
                left = at - length
            }
        }
        print("\(place): \(cars.count) cars along the line")
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
            var hidden = 0, tall = 0, shown = 0, flagged = 0, drawnSeeThrough = 0
            for car in cars {
                let camera = make(car.rail, car.forward)
                let eye = camera.eye
                let middle = car.rail + Map3DPoint(0, Map3DSeeThrough.bodyMiddle, 0)
                let see = Map3DSeeThrough(eye: eye, cars: [car.rail], matrix: camera.viewProjection)
                drawnSeeThrough += scene.chunks.filter { see.cuts(column: $0.column, row: $0.row, tops: $0.cityTops) }.count
                var hits: [(point: Map3DPoint, chunk: Int)] = []
                for (index, chunk) in scene.chunks.enumerated()
                where Map3DSeeThrough.segment(from: eye, to: middle, meets: chunk.minimum, chunk.maximum) {
                    Self.hits(of: eye, to: middle, in: chunk.mesh, from: chunk.baseIndexCount, over: car.rail.y + Map3DSeeThrough.clearance) {
                        hits.append(($0, index))
                    }
                }
                guard !hits.isEmpty else { continue }
                hidden += 1
                if hits.contains(where: { $0.point.y > car.rail.y + 7 }) { tall += 1 }
                if hits.allSatisfy({ see.opacity(at: $0.point) <= Map3DSeeThrough.opacity + 0.01 }) { shown += 1 }
                if hits.allSatisfy({
                    see.cuts(column: scene.chunks[$0.chunk].column, row: scene.chunks[$0.chunk].row, tops: scene.chunks[$0.chunk].cityTops)
                }) { flagged += 1 }
            }
            func share(_ n: Int) -> String { String(format: "%.1f%%", Double(n) * 100 / Double(cars.count)) }
            print("  \(name): hidden \(share(hidden)) (by something over 7 m \(share(tall))); seen through \(shown) of \(hidden), in chunks drawn see-through \(flagged) of \(hidden); chunks drawn see-through a view \(String(format: "%.2f", Double(drawnSeeThrough) / Double(cars.count)))")
        }
        // The line in view while the camera looks at the city beside it
        // (as far beside as the top of the view reaches past what it looks
        // at), every 500 m along, from both sides: every car of the line
        // in view and within reach.
        for (distance, beside) in [(120, 50), (280, 90)] as [(Float, Float)] {
            var inView = 0, hidden = 0, tall = 0, shown = 0, chosen = 0
            for (index, car) in cars.enumerated() where index % 10 == 0 {
                for side: Float in [-1, 1] {
                    let across = Map3DPoint(-car.forward.z, 0, car.forward.x) * (beside * side)
                    let camera = Map3DCamera(target: Map3DPoint(car.rail.x + across.x, 0, car.rail.z + across.z), distance: distance,
                                             heading: Map3DFollow.heading(of: across * -1), viewport: (402, 874))
                    let eye = camera.eye, matrix = camera.viewProjection
                    let seen = cars.map(\.rail).filter { rail in
                        guard (rail - eye).length <= Map3DTrains.modelReach, let clip = matrix.project(rail + Map3DPoint(0, Map3DSeeThrough.bodyMiddle, 0))
                        else { return false }
                        return clip.z >= 0 && clip.z <= 1 && abs(clip.x) <= 1 && abs(clip.y) <= 1
                    }
                    let see = Map3DSeeThrough(eye: eye, cars: seen, matrix: matrix)
                    for rail in seen {
                        inView += 1
                        let answer = Self.hidden(rail, from: eye, in: scene, seen: see)
                        guard answer.hidden else { continue }
                        hidden += 1
                        if answer.tall { tall += 1 }
                        if see.cars.contains(rail) { chosen += 1 }
                        if answer.shown { shown += 1 }
                    }
                }
            }
            func share(_ n: Int) -> String { String(format: "%.1f%%", Double(n) * 100 / Double(max(inView, 1))) }
            print("  beside the line, \(Int(distance)) m: \(inView) cars in view, hidden \(share(hidden)) (over 7 m \(share(tall))); among the chosen \(chosen), seen through \(shown) of \(hidden)")
        }
    }

    /// Whether the city of `scene` hides `rail`'s car from `eye`, and
    /// whether `see` shows it through every building in the way.
    static func hidden(_ rail: Map3DPoint, from eye: Map3DPoint, in scene: Map3DScene, seen see: Map3DSeeThrough) -> (hidden: Bool, tall: Bool, shown: Bool) {
        let middle = rail + Map3DPoint(0, Map3DSeeThrough.bodyMiddle, 0)
        var hits: [(point: Map3DPoint, chunk: Int)] = []
        for (index, chunk) in scene.chunks.enumerated() where Map3DSeeThrough.segment(from: eye, to: middle, meets: chunk.minimum, chunk.maximum) {
            Self.hits(of: eye, to: middle, in: chunk.mesh, from: chunk.baseIndexCount, over: rail.y + Map3DSeeThrough.clearance) { hits.append(($0, index)) }
        }
        let shown = hits.allSatisfy {
            see.opacity(at: $0.point) <= Map3DSeeThrough.opacity + 0.01
                && see.cuts(column: scene.chunks[$0.chunk].column, row: scene.chunks[$0.chunk].row, tops: scene.chunks[$0.chunk].cityTops)
        }
        return (!hits.isEmpty, hits.contains { $0.point.y > rail.y + 7 }, shown)
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
