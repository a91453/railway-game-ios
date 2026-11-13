import Foundation
import GameCore

// Decision 331: landmarks from the Codex model kits, where the real ones
// stand. On a real-world map, Taiwan's temples (``RealTemples``) as the
// civic kit's temples (#946's `Map3DCivicKit`, used as it is): a large one
// for the hundred religious events' temples and the listed monuments, a
// hall, gate and burner for the others, a side hall for a Tudigong shrine.
// Close up only; from farther, a low box hidden inside the hall. The kits
// are libraries: nothing in them changes.

extension Map3DScene.Builder {
    /// Close up, the most triangles a scene's temples may have, and a
    /// 512 m chunk's: past them, only the temples nearest the scene's
    /// middle.
    static let templeTriangles = 60_000
    static let templeChunkTriangles = 10_000

    /// A temple drawn: the model, its front +x and the middle of its
    /// ground at the origin; how long and wide that ground is; and the box
    /// drawn from farther, inside its main hall (its middle along x, its
    /// length, width and height).
    struct TempleModel: Sendable {
        let mesh: Map3DMesh
        let length: Float
        let width: Float
        let hall: (x: Float, length: Float, width: Float, height: Float)

        var triangles: Int { mesh.indices.count / 3 }
    }

    /// Each size's temple, from the civic kit.
    static let templeModels: [RealTemples.Size: TempleModel] = {
        func part(_ part: Map3DCivicKit.Part, _ x: Float, into builder: inout StationKitBuilder) {
            builder.add(Map3DCivicKit.model(for: part), at: Map3DPoint(x, 0.12, 0))
        }
        // The kit's temple square, 30 m by 32 m, its main hall at -6.
        var large = StationKitBuilder()
        large.add(Map3DCivicKit.model(for: .templePlaza), at: .zero)
        // A main hall, a burner and a gate on a smaller square.
        var temple = StationKitBuilder()
        temple.box(0, 0, 0, 22, 16, 0.12, Map3DPalette.plaza)
        part(.templeHall, -5, into: &temple)
        part(.incenseBurner, 2, into: &temple)
        part(.templeGate, 7, into: &temple)
        // A side hall and a burner.
        var small = StationKitBuilder()
        small.box(0, 0, 0, 12, 11, 0.12, Map3DPalette.plaza)
        part(.templeSideHall, -1.5, into: &small)
        part(.incenseBurner, 4.5, into: &small)
        // The halls' walls (the kit's `templeHall` and `templeSideHall`):
        // 1.6 m shorter and 1 m narrower than the hall, 0.7 m back, 3.4 m
        // tall on its 0.35 m platform on the square; the box a little
        // inside them.
        return [
            .large: TempleModel(mesh: large.mesh, length: 30, width: 32, hall: (-6.7, 8.2, 10.8, 3.3)),
            .temple: TempleModel(mesh: temple.mesh, length: 22, width: 16, hall: (-5.7, 8.2, 10.8, 3.3)),
            .small: TempleModel(mesh: small.mesh, length: 12, width: 11, hall: (-2.2, 5.2, 5.8, 3.3)),
        ]
    }()

    /// How high over a temple's foot its hall's walls begin: the square
    /// and the hall's platform.
    static let templeHallFloor: Float = 0.12 + 0.35

    /// The ways a temple may face, in turn: south, as temples face, then
    /// east, west and north.
    static let templeFacings = [Map3DPoint(0, 0, 1), Map3DPoint(1, 0, 0), Map3DPoint(-1, 0, 0), Map3DPoint(0, 0, -1)]

    /// The corners of the ground a temple `model` on `centre` facing
    /// `facing` takes, in ``isClear(_:facing:)``'s order.
    static func templeFootprint(_ model: TempleModel, centre: Map3DPoint, facing: Map3DPoint) -> [Map3DPoint] {
        let side = facing.cross(.up), back = centre - facing * (model.length / 2), out = centre + facing * (model.length / 2)
        let half = model.width / 2
        return [back - side * half, back + side * half, out + side * half, out - side * half]
    }

    /// Decision 331: `temples` in the scene, laid on the world by `frame`,
    /// nearest the scene's middle first, each the first way it faces
    /// clear of track, platforms and roads and on no cell in `cleared` or
    /// another's; within ``templeTriangles``, and ``templeChunkTriangles``
    /// a chunk. Returns the 64 m cells they stand on, which keep no city
    /// lot.
    mutating func addTemples(_ temples: RealTemples, frame: RealWorldFrame, clearOf cleared: Set<Map3DScene.ChunkKey>)
        -> Set<Map3DScene.ChunkKey> {
        let middle = (x: (region.minX + region.maxX) / 2, y: (region.minY + region.maxY) / 2)
        var near: [(distance: Double, place: (x: Double, y: Double), size: RealTemples.Size)] = []
        for temple in temples.temples {
            let place = frame.worldPosition(latitude: temple.latitude, longitude: temple.longitude)
            guard contains(x: place.x, y: place.y) else { continue }
            let dx = place.x - middle.x, dy = place.y - middle.y
            near.append(((dx * dx + dy * dy).squareRoot(), place, temple.size))
        }
        near.sort { ($0.distance, $1.size, $0.place.x, $0.place.y) < ($1.distance, $0.size, $1.place.x, $1.place.y) }
        var taken = Set<Map3DScene.ChunkKey>(), triangles = 0, chunkTriangles: [Map3DScene.ChunkKey: Int] = [:]
        for temple in near {
            guard let model = Self.templeModels[temple.size], triangles + model.triangles <= Self.templeTriangles else { continue }
            let centre = point(x: temple.place.x, y: temple.place.y, height: 0)
            let chunk = key(of: centre)
            guard chunkTriangles[chunk, default: 0] + model.triangles <= Self.templeChunkTriangles else { continue }
            for facing in Self.templeFacings {
                let footprint = Self.templeFootprint(model, centre: centre, facing: facing)
                let cells = cells(under: footprint)
                guard cleared.isDisjoint(with: cells), taken.isDisjoint(with: cells), !onPlacedGround(footprint), isClear(footprint, facing: facing)
                else { continue }
                let foot = Map3DPoint(centre.x, footprint.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0, centre.z)
                target = .close
                mesh(at: centre) { $0.append(model.mesh, at: foot, forward: facing) }
                let hall = foot + facing * model.hall.x + Map3DPoint(0, Self.templeHallFloor, 0)
                for level in [Target.near, .far] {
                    target = level
                    mesh(at: centre) { mesh in
                        mesh.addBox(base: hall, forward: facing, length: model.hall.length, width: model.hall.width, height: model.hall.height,
                                    top: Map3DPalette.templeRoof, side: Map3DPalette.templeWall)
                    }
                }
                target = .base
                taken.formUnion(cells)
                triangles += model.triangles
                chunkTriangles[chunk, default: 0] += model.triangles
                break
            }
        }
        return taken
    }

    /// The 64 m cells under the ground `footprint`'s corners span.
    func cells(under footprint: [Map3DPoint]) -> Set<Map3DScene.ChunkKey> {
        let keys = footprint.map { chunk(of: $0) }
        var cells = Set<Map3DScene.ChunkKey>()
        for row in keys.map(\.row).min()!...keys.map(\.row).max()! {
            for column in keys.map(\.column).min()!...keys.map(\.column).max()! { cells.insert(Map3DScene.ChunkKey(column: column, row: row)) }
        }
        return cells
    }

    /// The 64 m cells `mesh` (in the scene) stands over, or comes within
    /// `margin` metres of across the ground: each triangle against each
    /// cell its corners span. Where ``cells(under:)`` takes the whole
    /// rectangle round a shape, this leaves the ground between a long
    /// canopy's arms to the city.
    func cells(under mesh: Map3DMesh, margin: Float) -> Set<Map3DScene.ChunkKey> {
        let side = Float(Double(Land.cellLength) / Self.metre)
        var cells = Set<Map3DScene.ChunkKey>()
        for first in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let corners = (0..<3).map { mesh.vertices[Int(mesh.indices[first + $0])] }.map { (x: $0.x, z: $0.z) }
            let low = chunk(of: Map3DPoint(corners.map(\.x).min()! - margin, 0, corners.map(\.z).min()! - margin))
            let high = chunk(of: Map3DPoint(corners.map(\.x).max()! + margin, 0, corners.map(\.z).max()! + margin))
            for row in low.row...high.row {
                for column in low.column...high.column {
                    let key = Map3DScene.ChunkKey(column: column, row: row)
                    guard !cells.contains(key) else { continue }
                    // The cell's square in the scene, `margin` wider.
                    let west = Float((Double(column) * Double(Land.cellLength) - originX) / Self.metre) - margin
                    let north = Float((Double(row) * Double(Land.cellLength) - originY) / Self.metre) - margin
                    if Self.triangle(corners, reaches: (west, north, west + side + 2 * margin, north + side + 2 * margin)) { cells.insert(key) }
                }
            }
        }
        return cells
    }

    /// Whether the triangle `corners` (across the ground) and the square
    /// `box` overlap: no side of either parts them (the triangle's own
    /// span along x and z is the caller's).
    static func triangle(_ corners: [(x: Float, z: Float)], reaches box: (minX: Float, minZ: Float, maxX: Float, maxZ: Float)) -> Bool {
        guard corners.map(\.x).max()! >= box.minX, corners.map(\.x).min()! <= box.maxX,
              corners.map(\.z).max()! >= box.minZ, corners.map(\.z).min()! <= box.maxZ else { return false }
        let square = [(box.minX, box.minZ), (box.maxX, box.minZ), (box.maxX, box.maxZ), (box.minX, box.maxZ)]
        for index in 0..<3 {
            let a = corners[index], b = corners[(index + 1) % 3]
            // Across the edge: the triangle's span and the square's.
            let normal = (x: b.z - a.z, z: a.x - b.x)
            let own = corners.map { $0.x * normal.x + $0.z * normal.z }, other = square.map { $0.0 * normal.x + $0.1 * normal.z }
            if own.max()! < other.min()! || other.max()! < own.min()! { return false }
        }
        return true
    }
}
