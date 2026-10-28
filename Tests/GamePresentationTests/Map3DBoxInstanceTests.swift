import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 455: a box of the simplified city kept as an instance of one
/// box draws the same corners, colours, layers and texture places that
/// ``Map3DMesh/addBox(base:forward:length:width:height:top:side:topPaint:frontPaint:flankPaint:capped:)``
/// laid as vertices, and a scene built with them draws the same city.
final class Map3DBoxInstanceTests: XCTestCase {
    /// A small deterministic generator, so a failure names a box again.
    private struct Numbers {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func float(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * Float(next() >> 40) / Float(1 << 24)
        }
        mutating func pick<T>(_ items: [T]) -> T { items[Int(next() % UInt64(items.count))] }
    }

    private static let paints: [Map3DPaint?] = [
        nil,
        .tile(.roof, 4),
        .tile(.plaster, 3),
        Map3DPaint(.concrete, .tile(width: 2.5, height: 6)),
        .bays(.homeWindows, bay: 3.2, floors: 3),
        .bays(.flatWindows, bay: 3.6, floors: 12),
        .bays(.officeGlass, bay: 4, floors: 20).on(.mosaicTile),
        .bays(.shopfront, bay: 5, floors: 1).on(.brickTile),
    ]

    private func assertSame(_ laid: [Map3DVertex], _ drawn: [Map3DVertex], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(laid.count, drawn.count, label, file: file, line: line)
        for (a, b) in zip(laid, drawn) {
            XCTAssertEqual(a.position, b.position, label, file: file, line: line)
            XCTAssertEqual(a.nx, b.nx, accuracy: 1e-4, label, file: file, line: line)
            XCTAssertEqual(a.ny, b.ny, accuracy: 1e-4, label, file: file, line: line)
            XCTAssertEqual(a.nz, b.nz, accuracy: 1e-4, label, file: file, line: line)
            XCTAssertEqual(a.color, b.color, label, file: file, line: line)
            XCTAssertEqual(a.layer, b.layer, label, file: file, line: line)
            XCTAssertEqual(a.u, b.u, accuracy: 1e-3 * max(1, abs(a.u)), label, file: file, line: line)
            XCTAssertEqual(a.v, b.v, accuracy: 1e-3 * max(1, abs(a.v)), label, file: file, line: line)
        }
    }

    /// Thousands of boxes of every size, way and paint: each kept as an
    /// instance draws what `addBox` laid, vertex for vertex and triangle
    /// for triangle; the rest stay vertices, as before.
    func testAnInstanceDrawsWhatAddBoxLaid() {
        var numbers = Numbers(state: 455)
        var instanced = 0
        for index in 0..<4_000 {
            let base = Map3DPoint(numbers.float(-3_000, 3_000), numbers.float(-5, 80), numbers.float(-3_000, 3_000))
            let turn = numbers.pick([0, Float.pi / 2, numbers.float(0, 2 * Float.pi)])
            let forward = Map3DPoint(cos(turn), 0, sin(turn))
            let (length, width, height) = (numbers.float(2, 60), numbers.float(2, 40), numbers.float(2, 120))
            let top = UInt32(truncatingIfNeeded: numbers.next()) | 0xFF00_0000, side = UInt32(truncatingIfNeeded: numbers.next()) | 0xFF00_0000
            let topPaint = numbers.pick(Self.paints), frontPaint = numbers.pick(Self.paints), flankPaint = numbers.pick(Self.paints)
            let capped = numbers.next() % 4 != 0
            var laid = Map3DMesh(), collected = Map3DMesh()
            collected.collectsBoxes = true
            laid.addBox(base: base, forward: forward, length: length, width: width, height: height, top: top, side: side,
                        topPaint: topPaint, frontPaint: frontPaint, flankPaint: flankPaint, capped: capped)
            collected.addBox(base: base, forward: forward, length: length, width: width, height: height, top: top, side: side,
                             topPaint: topPaint, frontPaint: frontPaint, flankPaint: flankPaint, capped: capped)
            let label = "box \(index)"
            if let box = collected.boxes.first {
                instanced += 1
                XCTAssertEqual(collected.boxes.count, 1, label)
                XCTAssertTrue(collected.vertices.isEmpty, label)
                let drawn = Map3DBoxInstance.mesh([box])
                assertSame(laid.vertices, drawn.vertices, label)
                XCTAssertEqual(laid.indices, drawn.indices, label)
                XCTAssertEqual(laid.triangleCount, box.capped == 1 ? 10 : 8, label)
                // The shader's template: its corners and its triangles.
                let faces = box.capped == 1 ? 0..<5 : 1..<5
                XCTAssertEqual(drawn.indices.map { $0 + UInt32(faces.lowerBound * 4) }, faces.flatMap { face in
                    Map3DBoxInstance.indices[(face * 6)..<(face * 6 + 6)].map(UInt32.init)
                }, label)
                // Its bounds and top are those of the vertices.
                let up = laid.vertices.map(\.position)
                XCTAssertEqual(box.bounds.min.y, up.map(\.y).min(), label)
                XCTAssertEqual(box.bounds.max.y, up.map(\.y).max(), label)
                XCTAssertEqual(box.bounds.min.x, up.map(\.x).min(), label)
                XCTAssertEqual(box.bounds.max.z, up.map(\.z).max(), label)
            } else {
                XCTAssertEqual(collected.vertices, laid.vertices, label)
                XCTAssertEqual(collected.indices, laid.indices, label)
            }
        }
        XCTAssertGreaterThan(instanced, 3_000, "most boxes are instances")
    }

    /// A box the bays would number apart front and back cannot share one
    /// texture place, so stays vertices; so does a box laid on a slope.
    func testABoxThatCannotBeOneInstanceStaysVertices() {
        var mesh = Map3DMesh()
        mesh.collectsBoxes = true
        mesh.addBox(base: .zero, length: 10, width: 8, height: 6, top: 0xFF00_0000, side: 0xFF00_0000)
        XCTAssertEqual(mesh.boxes.count, 1)
        XCTAssertNil(Map3DBoxInstance(base: .zero, along: Map3DPoint(0.6, 0.8, 0), length: 10, width: 8, height: 6, top: 0, side: 0,
                                      topPaint: nil, frontPaint: nil, flankPaint: nil, capped: true))
        XCTAssertNil(Map3DBoxInstance(base: .zero, along: Map3DPoint(1, 0, 0), length: 10, width: 0, height: 6, top: 0, side: 0,
                                      topPaint: nil, frontPaint: nil, flankPaint: nil, capped: true))
    }

    /// Decision 455: afar, a real outline of four corners each within
    /// 0.2 m of the box round it is drawn as that box; any other stays
    /// its own shape.
    func testARealOutlineIsABoxOnlyWhenItIsARectangle() {
        let turn: Float = 0.47, along = Map3DPoint(cos(turn), 0, sin(turn)), across = Map3DPoint(-along.z, 0, along.x)
        let centre = Map3DPoint(120, 0, -45)
        func outline(_ corners: [(Float, Float)]) -> [Map3DPoint] { corners.map { centre + along * $0.0 + across * $0.1 } }
        func isRectangle(_ ring: [Map3DPoint]) -> Bool { Map3DScene.Builder.isRectangle(ring, Map3DScene.Builder.orientedBox(ring)) }
        XCTAssertTrue(isRectangle(outline([(-9, -4), (9, -4), (9, 4), (-9, 4)])))
        // The footprints' grid, some 0.135 m a step, a corner off by one.
        XCTAssertTrue(isRectangle(outline([(-9, -4), (9.12, -4), (9, 4.1), (-9, 4)])))
        XCTAssertFalse(isRectangle(outline([(-9, -4), (9, -4), (9.5, 4), (-9, 4)])), "a trapezium")
        XCTAssertFalse(isRectangle(outline([(-9, -4), (9, -4), (9, 4), (0, 4), (-9, 4)])), "five corners")
        XCTAssertFalse(isRectangle(outline([(-9, -4), (9, -4), (9, 0), (0, 4)])), "a corner cut off")
    }

    /// The same box from the same arguments, every time; and the layout
    /// the app's shader reads: 88 bytes, fourteen floats, five colours and
    /// six shorts in that order.
    func testTheLayoutTheShaderReads() throws {
        XCTAssertEqual(MemoryLayout<Map3DBoxInstance>.size, 88)
        XCTAssertEqual(MemoryLayout<Map3DBoxInstance>.stride, 88)
        XCTAssertEqual(MemoryLayout<Map3DBoxInstance>.alignment, 4)
        XCTAssertEqual(MemoryLayout<Map3DBoxInstance>.offset(of: \.x), 0)
        XCTAssertEqual(MemoryLayout<Map3DBoxInstance>.offset(of: \.flankV), 13 * 4)
        XCTAssertEqual(MemoryLayout<Map3DBoxInstance>.offset(of: \.topColor), 14 * 4)
        XCTAssertEqual(MemoryLayout<Map3DBoxInstance>.offset(of: \.leftColor), 18 * 4)
        XCTAssertEqual(MemoryLayout<Map3DBoxInstance>.offset(of: \.topLayer), 19 * 4)
        XCTAssertEqual(MemoryLayout<Map3DBoxInstance>.offset(of: \.capped), 19 * 4 + 5 * 2)
        XCTAssertEqual(Map3DBoxInstance.faceCorners.count, 20)
        XCTAssertEqual(Map3DBoxInstance.indices.count, 30)
        func make() -> Map3DBoxInstance? {
            Map3DBoxInstance(base: Map3DPoint(12.5, 3, -40), along: Map3DPoint(0, 0, -1), length: 14, width: 9, height: 31, top: 0xFF33_6699,
                             side: 0xFFCC_BBAA, topPaint: .tile(.roof, 4), frontPaint: .bays(.flatWindows, bay: 3.6, floors: 10),
                             flankPaint: .bays(.flatWindows, bay: 3.6, floors: 10), capped: true)
        }
        let box = try XCTUnwrap(make())
        XCTAssertEqual(box, make())
        XCTAssertEqual(box.frontU, 3) // its front 9 m wide in 3.6 m bays
        XCTAssertEqual(box.flankU, 4) // its flanks 14 m
        XCTAssertEqual(box.frontV, 10)
    }

    /// Decision 455: a scene round Taichung Station built with the city's
    /// boxes as instances draws the same simplified city, the same tops
    /// for decision 342's cones and the same bounds as one built with them
    /// as vertices; its full city is untouched, and the same place and
    /// seed give the same boxes. With the game's own lots (no city tiles),
    /// most of the simplified city is boxes; with the real buildings'
    /// shapes, those stay vertices.
    func testASceneWithInstancesDrawsTheSameCity() throws {
        let resources = Map3DRealTrainsTests.resources
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.1372, longitudeDegrees: 120.6869)))
        let at = try XCTUnwrap(RealWorldFrame(world: world)).worldPosition(latitude: 24.1372, longitude: 120.6869)
        let origin = (x: at.x.rounded(), y: at.y.rounded())
        let grid = Map3DStreaming(originX: origin.x, originY: origin.y, map: WorldRegion(bounds: world.bounds))
        let region = try XCTUnwrap(grid.region(of: [Map3DStreaming.Key(column: -1, row: -1), Map3DStreaming.Key(column: 0, row: 0)]))
        let tiles = try BaseMapTiles(data: Data(contentsOf: resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
        let city = CityTileArea.areas(in: resources.appendingPathComponent("BaseMap/city"))
        for (label, cityTiles, least) in [("lots", [CityTileArea](), 500), ("real buildings", city, 10)] {
            func scene(_ instancing: Bool) -> Map3DScene {
                Map3DScene(world: world, snapshot: nil, skyline: nil, frame: (region, origin.x, origin.y), baseMap: tiles, cityTiles: cityTiles,
                           heights: nil, lineBands: nil, railways: nil, temples: nil, instancingBoxes: instancing)
            }
            let vertices = scene(false), instances = scene(true), again = scene(true)
            XCTAssertEqual(vertices.chunks.count, instances.chunks.count, label)
            var boxes = 0, before = 0, after = 0
            for (old, new) in zip(vertices.chunks, instances.chunks) {
                let key = "\(label) \(new.column),\(new.row)"
                XCTAssertEqual(old.column, new.column)
                XCTAssertEqual(old.row, new.row)
                XCTAssertTrue(old.farBoxes.isEmpty, key)
                XCTAssertEqual(old.mesh.vertices, new.mesh.vertices, key)
                XCTAssertEqual(old.mesh.indices, new.mesh.indices, key)
                XCTAssertEqual(old.close.vertices, new.close.vertices, key)
                XCTAssertEqual(old.standIn.vertices, new.standIn.vertices, key)
                XCTAssertEqual(old.cityTops, new.cityTops, key)
                XCTAssertEqual(old.minimum, new.minimum, key)
                XCTAssertEqual(old.maximum, new.maximum, key)
                XCTAssertEqual(old.far.triangleCount, new.farTriangleCount, key)
                let (missing, extra) = Self.difference(Self.triangles(old.far), Self.triangles(new.farWithBoxes))
                XCTAssertTrue(missing.isEmpty && extra.isEmpty, "\(key): \(missing.count) triangles missing, e.g. \(missing.prefix(2)); \(extra.count) not laid, e.g. \(extra.prefix(2))")
                boxes += new.farBoxes.count
                before += old.far.vertices.count * 40 + old.far.indices.count * 4
                after += new.far.vertices.count * 40 + new.far.indices.count * 4 + new.farBoxes.count * MemoryLayout<Map3DBoxInstance>.stride
            }
            XCTAssertEqual(instances.chunks.map(\.farBoxes), again.chunks.map(\.farBoxes), label)
            XCTAssertGreaterThan(boxes, least, label)
            print("\(label): \(boxes) boxes, the simplified city \(before / 1_000) KB as vertices, \(after / 1_000) KB with instances")
            if cityTiles.isEmpty { XCTAssertLessThan(after * 3, before, "the simplified city in a third of the memory or less") }
        }
    }

    /// The triangles of `a` that `b` does not draw and those of `b` that
    /// `a` does not, alike where their corners, normals, colours and
    /// layers are and their texture places are within a ten-thousandth of
    /// a repeat or so (a box's back takes its front's, worked out apart).
    private static func difference(_ a: [Triangle], _ b: [Triangle]) -> (missing: [Triangle], extra: [Triangle]) {
        var left = Dictionary(grouping: a, by: \.corners), missing: [Triangle] = [], extra: [Triangle] = []
        for triangle in b {
            if let index = left[triangle.corners]?.firstIndex(where: { other in
                zip(other.places, triangle.places).allSatisfy { abs($0 - $1) <= 1e-3 * max(1, abs($0)) }
            }) {
                left[triangle.corners]?.remove(at: index)
            } else {
                extra.append(triangle)
            }
        }
        for (_, rest) in left { missing += rest }
        return (missing, extra)
    }

    struct Triangle {
        /// Each corner's place, normal, colour and layer, from the lowest.
        var corners: [String]
        /// Their texture places, `u` and `v` of each in the same order.
        var places: [Float]
    }

    /// A mesh's triangles, each from its lowest corner: the same drawing
    /// whatever order they were laid in.
    private static func triangles(_ mesh: Map3DMesh) -> [Triangle] {
        func text(_ vertex: Map3DVertex) -> String {
            // Rounded, normals more coarsely (worked out by a cross product
            // or given), and without a minus on zero.
            func r(_ value: Float, _ places: Float = 1_000) -> String { String(format: "%g", (value * places).rounded() / places + 0) }
            return [r(vertex.x), r(vertex.y), r(vertex.z), r(vertex.nx, 100), r(vertex.ny, 100), r(vertex.nz, 100),
                    String(vertex.color), r(vertex.layer)].joined(separator: " ")
        }
        var triangles: [Triangle] = []
        var index = 0
        while index + 2 < mesh.indices.count {
            let corners = mesh.indices[index..<(index + 3)].map { mesh.vertices[Int($0)] }
            let texts = corners.map(text)
            let first = texts.indices.min { texts[$0] < texts[$1] } ?? 0
            let order = (0..<3).map { (first + $0) % 3 }
            triangles.append(Triangle(corners: order.map { texts[$0] }, places: order.flatMap { [corners[$0].u, corners[$0].v] }))
            index += 3
        }
        return triangles
    }
}
