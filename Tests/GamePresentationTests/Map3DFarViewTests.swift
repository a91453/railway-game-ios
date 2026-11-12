import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 709: what the 3D map draws seen from its farthest.
final class Map3DFarViewTests: XCTestCase {
    static let resources = Map3DRealTrainsTests.resources

    /// What the app builds a whole-Taiwan game's 3D map from: every file
    /// it passes (``Map3DChunkSource`` in the app).
    struct Source {
        let world: GameWorld
        let snapshot: RailwaySnapshot
        let skyline: CitySkyline
        let tiles: BaseMapTiles
        let city: [CityTileArea]
        let footprints: FootprintTiles
        let heights: HeightGrid
        let bands: Map3DLineBands
        let temples: RealTemples
        let noBuild: RealNoBuildLand?
        let frame: RealWorldFrame

        init() throws {
            var world = GameWorld.newWholeTaiwanGame()
            frame = try XCTUnwrap(RealWorldFrame(world: world))
            world.setAirports(AirportCatalog.airports(in: frame, bounds: world.bounds))
            self.world = world
            snapshot = world.railwaySnapshot()
            skyline = CitySkyline(world: world)
            let base = resources.appendingPathComponent("BaseMap")
            tiles = try BaseMapTiles(data: Data(contentsOf: base.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
            city = CityTileArea.areas(in: base.appendingPathComponent("city"))
            footprints = try FootprintTiles(data: Data(contentsOf: base.appendingPathComponent("taiwan_buildings.pmtiles"), options: .alwaysMapped))
            heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
            bands = Map3DLineBands(world: world, palette: .standard)
            temples = try RealTemples(data: Data(contentsOf: base.appendingPathComponent("taiwan_temples.json")))
            var land = try? RealNoBuildLand(data: RealWorldDataLoadTests.file("taiwan_no_build", "json"))
            land?.airfields = try RealAirfields(data: Data(contentsOf: base.appendingPathComponent("taiwan_airfields.json")))
            noBuild = land
        }

        func scene(latitude: Double, longitude: Double) -> Map3DScene {
            let at = frame.worldPosition(latitude: latitude, longitude: longitude)
            return Map3DScene(world: world, snapshot: snapshot, skyline: skyline, focus: (at.x, at.y), baseMap: tiles, cityTiles: city,
                              footprints: footprints, heights: heights, lineBands: bands, railways: Map3DRealTrainsTests.railways,
                              temples: temples, noBuild: noBuild)
        }

        func chunks(_ keys: [Map3DStreaming.Key], of grid: Map3DStreaming, scene: Map3DScene, detail: Map3DPoint) -> [Map3DScene.Chunk] {
            Map3DScene.chunks(keys, of: grid, world: world, snapshot: snapshot, skyline: skyline, baseMap: tiles, cityTiles: city,
                              footprints: footprints, heights: heights, lineBands: bands, railways: Map3DRealTrainsTests.railways,
                              temples: temples, noBuild: noBuild, trackCover: scene.trackCover, detail: detail)
        }
    }

    /// The chunks the app holds (``Map3DChunkStreamer`` in the app): the
    /// scene's, and those its window (decision 358) builds and lets go as
    /// the camera's target moves.
    struct Held {
        let source: Source
        let scene: Map3DScene
        var window: Map3DStreaming.Window
        var chunks: [Map3DStreaming.Key: Map3DScene.Chunk]
        var seconds = 0.0

        init(_ source: Source, latitude: Double, longitude: Double) {
            self.source = source
            scene = source.scene(latitude: latitude, longitude: longitude)
            window = Map3DStreaming.Window(scene: scene, map: WorldRegion(bounds: source.world.bounds))
            chunks = Dictionary(uniqueKeysWithValues: scene.chunks.map { (Map3DStreaming.Key(column: $0.column, row: $0.row), $0) })
        }

        /// The target at `target` for `time` seconds, every block the
        /// window asks for built at once.
        mutating func hold(_ target: Map3DPoint, for time: Double = 0) {
            let end = seconds + time
            var idle = 0
            while seconds <= end || idle < 2 {
                let (drop, build) = window.step(target: target, at: seconds)
                for key in drop { chunks[key] = nil }
                if !build.isEmpty {
                    for chunk in source.chunks(build, of: window.grid, scene: scene, detail: window.buildingAround) {
                        chunks[Map3DStreaming.Key(column: chunk.column, row: chunk.row)] = chunk
                    }
                    _ = window.finished(build, generation: window.generation)
                    idle = 0
                } else {
                    idle += 1
                }
                seconds += Map3DStreaming.interval
            }
        }
    }

    /// Everything the farthest view can hold round (`latitude`,
    /// `longitude`), as the window builds it far from where the camera
    /// looks (simplified, decision 368): the ground a phone on its side
    /// sees from ``Map3DCamera/farthest``, and a chunk round it. More than
    /// any game holds at once (the window keeps some 4 km round the
    /// camera and the strip ahead of its motion, the scene up to 12 km
    /// across), so no game draws more from there.
    static func farthest(_ source: Source, latitude: Double, longitude: Double) -> (scene: Map3DScene, camera: Map3DCamera) {
        let camera = Map3DCamera(target: .zero, distance: Map3DCamera.farthest, viewport: (874, 402))
        let wide = Double(camera.metresPerPoint * 874 / 2 + Map3DScene.chunkSize), tall = Double(camera.metresPerPoint * 402 / 2 + Map3DScene.chunkSize)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let at = source.frame.worldPosition(latitude: latitude, longitude: longitude)
        let origin = (x: at.x.rounded(), y: at.y.rounded())
        let region = WorldRegion(minX: origin.x - wide * metre, minY: origin.y - tall * metre, maxX: origin.x + wide * metre, maxY: origin.y + tall * metre)
        let scene = Map3DScene(world: source.world, snapshot: source.snapshot, skyline: source.skyline, frame: (region, origin.x, origin.y),
                               baseMap: source.tiles, cityTiles: source.city, footprints: source.footprints, heights: source.heights,
                               lineBands: source.bands, railways: Map3DRealTrainsTests.railways, temples: source.temples,
                               noBuild: source.noBuild, detail: Map3DPoint(1e7, 0, 1e7))
        return (scene, camera)
    }

    /// What the Metal view draws of `scene`'s chunks, all simplified, from
    /// `distance` straight over its middle: everything (`level` 0, as
    /// before decision 709) or what the distance leaves.
    static func frame(_ scene: Map3DScene, distance: Float, level: Int? = nil) -> (chunks: Int, triangles: Int, drawCalls: Int, parts: [Int]) {
        let camera = Map3DCamera(target: .zero, distance: distance, viewport: (874, 402))
        let matrix = camera.viewProjection
        let level = level ?? Map3DFarDetail.level(distance: distance)
        var frame = (chunks: 0, triangles: 0, drawCalls: 0, parts: [0, 0, 0, 0])
        for chunk in scene.chunks where Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: matrix) {
            let drawn = chunk.farFrame(at: level)
            frame.chunks += 1
            frame.triangles += drawn.triangles
            frame.drawCalls += drawn.drawCalls
            frame.parts[0] += chunk.baseIndexCount(at: level) / 3
            frame.parts[1] += chunk.farIndexCount(at: level) / 3
            frame.parts[2] += chunk.farBoxes.prefix(chunk.farBoxCount(at: level)).reduce(0) { $0 + $1.triangleCount }
            frame.parts[3] += chunk.shadowIndexCount(at: level) / 3
        }
        return frame
    }

    /// The distances the far view is measured from: where it begins to
    /// leave things out, to the farthest.
    static let distances: [Float] = [2_000, 3_000, 4_000, 5_000, 6_000, 8_000, 10_000, Map3DCamera.farthest]

    /// Decision 709: the densest city on the map, with everything the
    /// farthest view can hold built, stays within the far view's budget
    /// from every distance. Before, the same scene drew 4.16 million
    /// triangles from 12 km.
    func testTheFarthestViewOfTaipeiIsWithinBudget() throws {
        let source = try Source()
        let scene = Self.farthest(source, latitude: 25.0478, longitude: 121.5170).scene
        XCTAssertGreaterThan(Self.frame(scene, distance: Map3DCamera.farthest, level: 0).triangles, 3_000_000, "the scene is Taipei's, whole")
        for distance in Self.distances {
            let frame = Self.frame(scene, distance: distance)
            XCTAssertLessThanOrEqual(frame.triangles, Map3DFarDetail.budget, "from \(Int(distance)) m: \(frame.chunks) chunks")
        }
        // Nothing is left out where chunks are drawn in full.
        XCTAssertEqual(Map3DFarDetail.level(distance: Map3DCamera.detailDistance * 1.14), 0)
        // The ground, the main roads and the track are drawn from everywhere.
        let ground = scene.chunks.filter { $0.baseIndexCount(at: Map3DFarDetail.always) > 0 }.count
        XCTAssertGreaterThan(ground * 10, scene.chunks.count * 9, "\(ground) of \(scene.chunks.count) chunks")
    }

    /// The classes and levels: 1.41 times the size a class, nothing left
    /// out up to where chunks are drawn in full, more the farther.
    func testLevelsRiseWithTheDistance() {
        XCTAssertEqual(Map3DFarDetail.rank(size: 0.3), 0)
        XCTAssertEqual(Map3DFarDetail.rank(size: 1), 0)
        XCTAssertEqual(Map3DFarDetail.rank(size: 2), 2)
        XCTAssertEqual(Map3DFarDetail.rank(size: 31.9), 9)
        XCTAssertEqual(Map3DFarDetail.rank(size: 32), 10)
        XCTAssertEqual(Map3DFarDetail.rank(size: 10_000), Map3DFarDetail.always)
        XCTAssertEqual(Map3DFarDetail.rank(size: .infinity), Map3DFarDetail.always)
        XCTAssertEqual(Map3DFarDetail.level(distance: Map3DCamera.nearest), 0)
        XCTAssertEqual(Map3DFarDetail.level(distance: Map3DFarDetail.from), 0)
        var last = 0
        for distance in stride(from: Float(0), through: Map3DCamera.farthest, by: 50) {
            let level = Map3DFarDetail.level(distance: distance)
            XCTAssertGreaterThanOrEqual(level, last)
            XCTAssertLessThanOrEqual(level - last, 4, "no more than a few classes at once, at \(distance) m")
            // What a level draws is no smaller than the distance's smallest.
            if level > 0 { XCTAssertGreaterThanOrEqual(Map3DFarDetail.sizes[level] * 1.001, Map3DFarDetail.smallest(distance: distance)) }
            last = level
        }
        // Held at a step: a level changes only once the camera is 3 % past.
        let step = Map3DFarDetail.sizes[9] / Map3DFarDetail.slope + Map3DFarDetail.from
        XCTAssertEqual(Map3DFarDetail.level(distance: step / 1.001), 9)
        XCTAssertEqual(Map3DFarDetail.level(distance: step * 1.001), 10)
        XCTAssertEqual(Map3DFarDetail.level(distance: step * 1.001, was: 9), 9)
        XCTAssertEqual(Map3DFarDetail.level(distance: step / 1.001, was: 10), 10)
        XCTAssertEqual(Map3DFarDetail.level(distance: step * 1.04, was: 9), 10)
        XCTAssertEqual(Map3DFarDetail.level(distance: step / 1.04, was: 10), 9)
        XCTAssertEqual(Map3DFarDetail.level(distance: Map3DCamera.detailDistance * 1.14, was: 6), 0, "nothing left out where chunks are drawn in full")
        XCTAssertEqual(Map3DFarDetail.level(distance: Map3DCamera.farthest, was: 0), last)
        XCTAssertEqual(last, 11, "from the farthest, things from 45 m")
        XCTAssertLessThan(last, Map3DFarDetail.always)
        // The main roads are always drawn; the lesser ones go in their order.
        XCTAssertEqual(Map3DFarDetail.rank(size: Map3DFarDetail.size(of: .primary)), Map3DFarDetail.always)
        let kinds: [Map3DBaseMap.RoadKind] = [.service, .minor, .tertiary, .secondary]
        XCTAssertEqual(kinds.map { Map3DFarDetail.rank(size: Map3DFarDetail.size(of: $0)) }.sorted(), kinds.map { Map3DFarDetail.rank(size: Map3DFarDetail.size(of: $0)) })
        XCTAssertGreaterThan(Map3DFarDetail.rank(size: Map3DFarDetail.size(of: .secondary)), last, "the secondary roads are drawn from the farthest")
    }

    /// A mesh's parts in the order of their size: the same triangles,
    /// what is in no part first, then the largest; each level a prefix.
    func testPartsAreOrderedLargestFirst() {
        var mesh = Map3DMesh()
        func quad(_ x: Float) {
            mesh.addQuad(Map3DPoint(x, 0, 0), Map3DPoint(x, 0, 1), Map3DPoint(x + 1, 0, 1), Map3DPoint(x + 1, 0, 0), color: 0xFF00_0000)
        }
        for x in 0..<5 { quad(Float(x)) }
        let before = mesh.indices
        func triangles(_ indices: some Sequence<UInt32>) -> [[UInt32]] {
            let all = Array(indices)
            return stride(from: 0, to: all.count, by: 3).map { Array(all[$0..<$0 + 3]) }
        }
        // Quad 0 is in no part; 1 is small, 2 large, 3 always, 4 middling.
        let parts = [Map3DFarDetail.Part(first: 6, count: 6, rank: 2), Map3DFarDetail.Part(first: 12, count: 6, rank: 9),
                     Map3DFarDetail.Part(first: 18, count: 6, rank: Map3DFarDetail.always), Map3DFarDetail.Part(first: 24, count: 6, rank: 5)]
        let steps = Map3DFarDetail.order(&mesh, parts: parts).indices
        XCTAssertEqual(Set(triangles(mesh.indices)), Set(triangles(before)))
        XCTAssertEqual(Array(mesh.indices[0..<6]), Array(before[0..<6]))
        XCTAssertEqual(Array(mesh.indices[6..<12]), Array(before[18..<24]))
        XCTAssertEqual(Array(mesh.indices[12..<18]), Array(before[12..<18]))
        XCTAssertEqual(Array(mesh.indices[18..<24]), Array(before[24..<30]))
        XCTAssertEqual(Array(mesh.indices[24..<30]), Array(before[6..<12]))
        XCTAssertEqual(steps.count(at: 0, of: 30), 30)
        XCTAssertEqual(steps.count(at: 2, of: 30), 30)
        XCTAssertEqual(steps.count(at: 3, of: 30), 24)
        XCTAssertEqual(steps.count(at: 5, of: 30), 24)
        XCTAssertEqual(steps.count(at: 6, of: 30), 18)
        XCTAssertEqual(steps.count(at: 10, of: 30), 12)
        XCTAssertEqual(steps.count(at: Map3DFarDetail.always, of: 30), 12)
        // Parts that do not fit the mesh move nothing.
        var other = mesh
        XCTAssertTrue(Map3DFarDetail.order(&other, parts: [Map3DFarDetail.Part(first: 24, count: 12, rank: 3)]).indices.isEmpty)
        XCTAssertEqual(other.indices, mesh.indices)
        XCTAssertEqual(Map3DFarDetail.Steps().count(at: 9, of: 30), 30)
        // From `from` on only: what comes before stays.
        var base = Map3DMesh()
        mesh = base
        for x in 0..<3 { quad(Float(x)) }
        base = mesh
        let tail = Map3DFarDetail.order(&mesh, parts: [Map3DFarDetail.Part(first: 6, count: 6, rank: 1)], from: 6).indices
        XCTAssertEqual(Array(mesh.indices[0..<6]), Array(base.indices[0..<6]))
        XCTAssertEqual(Array(mesh.indices[6..<12]), Array(base.indices[12..<18]))
        XCTAssertEqual(tail.count(at: 2, of: 18), 12)
    }

    func testTheFarthestViewsLayers() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let source = try Source()
        for (name, latitude, longitude) in [("Taipei Station", 25.0478, 121.5170), ("Nangang", 25.0522, 121.6067),
                                            ("Taoyuan Airport", 25.0777, 121.2328), ("Kaohsiung Station", 22.6394, 120.3021)] {
            let start = Date()
            let scene = Self.farthest(source, latitude: latitude, longitude: longitude).scene
            print("\(name): \(scene.chunks.count) chunks, built in \(Int(Date().timeIntervalSince(start))) s")
            for distance in Self.distances {
                let before = Self.frame(scene, distance: distance, level: 0), after = Self.frame(scene, distance: distance)
                print("  \(Int(distance)) m, level \(Map3DFarDetail.level(distance: distance)) (from \(String(format: "%.1f", Map3DFarDetail.smallest(distance: distance))) m): \(after.chunks) chunks, \(before.triangles) → \(after.triangles) triangles (base \(before.parts[0]) → \(after.parts[0]), far \(before.parts[1]) → \(after.parts[1]), boxes \(before.parts[2]) → \(after.parts[2]), shadows \(before.parts[3]) → \(after.parts[3])), \(before.drawCalls) → \(after.drawCalls) draws")
            }
            print("  by level from 12 km: " + (0..<Map3DFarDetail.ranks).map { "\($0): \(Self.frame(scene, distance: Map3DCamera.farthest, level: $0).triangles)" }.joined(separator: ", "))
            let all = scene.layers.reduce(0) { $0 + $1.base + $1.far + $1.boxes + $1.shadows }
            print("  layer: base, far, boxes, shadows (share of the \(all) drawn from afar)")
            for layer in scene.layers.sorted(by: { $0.base + $0.far + $0.boxes + $0.shadows > $1.base + $1.far + $1.boxes + $1.shadows }) {
                let sum = layer.base + layer.far + layer.boxes + layer.shadows
                guard sum > 0 else { continue }
                print("  \(layer.layer): \(layer.base), \(layer.far), \(layer.boxes), \(layer.shadows) (\(String(format: "%.1f", Double(sum) * 100 / Double(max(all, 1)))) %)")
            }
        }
    }

    func testTheFarthestViewReport() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let source = try Source()
        for (name, latitude, longitude) in [("Nangang", 25.0522, 121.6067), ("Taipei Station", 25.0478, 121.5170)] {
            var held = Held(source, latitude: latitude, longitude: longitude)
            print("\(name): the scene \(held.chunks.count) chunks")
            held.hold(.zero)
            report("\(name), settled", held)
            // A drag east and back, 400 m a second for 5 s each way.
            for step in 0..<40 { held.hold(Map3DPoint(Float(step < 20 ? step : 40 - step) * 100, 0, 0), for: 0.25) }
            held.hold(.zero)
            report("\(name), after a drag of 2 km and back", held)
        }
    }

    private func report(_ name: String, _ held: Held) {
        print("\(name): \(held.chunks.count) chunks held, \(held.chunks.values.filter(\.coarse).count) coarse")
        for viewport in [(402, 874), (874, 402)] as [(Float, Float)] {
            for distance in [12_000, 8_000, 5_000, 3_000, 1_600, 1_000] as [Float] {
                let camera = Map3DCamera(target: .zero, distance: distance, viewport: viewport)
                let matrix = camera.viewProjection
                var chunks = 0, base = 0, full = 0, far = 0, boxes = 0, shadows = 0, draws = 0
                for chunk in held.chunks.values where Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: matrix) {
                    chunks += 1
                    let detailed = !chunk.coarse && camera.wantsDetail(minimum: chunk.minimum, maximum: chunk.maximum)
                    base += chunk.baseIndexCount / 3
                    draws += 1
                    if detailed {
                        full += chunk.mesh.triangleCount - chunk.baseIndexCount / 3
                    } else {
                        far += chunk.far.triangleCount
                        boxes += chunk.farBoxes.reduce(0) { $0 + $1.triangleCount }
                        draws += (chunk.far.isEmpty ? 0 : 1) + (chunk.farBoxes.isEmpty ? 0 : 1)
                    }
                    shadows += chunk.shadows.triangleCount
                    draws += chunk.shadows.isEmpty ? 0 : 1
                }
                print("  \(Int(viewport.0))×\(Int(viewport.1)) \(Int(distance)) m: \(chunks) chunks, \(base + full + far + boxes + shadows) triangles (base \(base), full city \(full), far \(far), boxes \(boxes), shadows \(shadows)), \(draws) draws")
            }
        }
    }
}
