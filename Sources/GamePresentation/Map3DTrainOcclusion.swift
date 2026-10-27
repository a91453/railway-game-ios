import Foundation

/// Decision 439: how much each corner of a train model is shut in by the
/// rest of it, baked into its colour once, as the pack is made, so the
/// cars have their soft shade under the floor, round the bogies, by the
/// roof's equipment and at the gangways, and the drawing costs nothing
/// more (the shader reads the same colour it did).
///
/// The model is laid in cubes (``Grid``): a cube some face of the model
/// passes through counts 2, and so does a cube of the next car's end at a
/// gangway (a middle car's ends, ``isMiddle(_:)``); the cubes just under
/// the rail count 1, the ground the train stands on (it shuts in half as
/// much: it is lighter than a wall). A corner's shade is how many of them
/// a box held out from it along its face's normal holds, a small box and a
/// large one (``scales``), as walls' worth: the box over an open side
/// holds none; one under the floor holds the ground, the bogies and the
/// skirts. A summed table of the cubes answers each box in eight looks;
/// models alike to the bit (a reversed car's twin, a set's copy of a
/// recipe's car) are worked out once.
///
/// Soft and flat as the art style draws (art-style §1): at most
/// ``strength`` darker, a long face (``longEdge``) one shade, its lightest
/// corner's, so a car's side never turns into a gradient; a lamp lit at
/// night (``Map3DVertex/glowing``) and the line's colour (a vertex's
/// alpha) as they were. A far model (``isFar(_:)``) in cubes ``farCell``
/// across, the coarse shade it needs from there.
public enum Map3DTrainOcclusion {
    /// A near model's cube, in metres.
    static let nearCell: Float = 0.25
    /// A far model's.
    static let farCell: Float = 0.5
    /// The boxes' half sides, in metres: the small one for a bogie's frame
    /// or an air conditioner's side, the large one for the floor's
    /// underside and the gangway.
    static let scales: [Float] = [0.4, 0.8]
    /// The most a corner is darkened (its colour times 1 − this).
    static let strength: Float = 0.42
    /// How fast walls' worth turn into shade: k·w / (1 + k·w).
    static let falloff: Float = 1.3
    /// A face with an edge longer than this, in metres, takes one shade.
    static let longEdge: Float = 2.5
    /// The gap to the next car (``Map3DTrains/carGap``).
    static let gangway: Float = Map3DTrains.carGap

    /// Whether model `name` is a train's: not the street's furniture,
    /// people and road vehicles (``Map3DProp``, ``Map3DStreetModel``,
    /// ``Map3DLowFloorBus``).
    public static func isTrain(_ name: String) -> Bool {
        !name.hasPrefix("prop-") && !name.hasPrefix("life-")
    }

    /// Whether model `name` is a far model (decisions 408, 417, 420).
    static func isFar(_ name: String) -> Bool {
        name.contains("Far-") || name.hasSuffix("-far")
    }

    /// Whether model `name` is a car with a car before and behind it, by
    /// its name's role: neither a cab, a head or a tail, a locomotive, a
    /// one-car set nor a whole formation. A cab's own back end is left
    /// open, for a flat cab front cannot be told from a gangway by shape.
    static func isMiddle(_ name: String) -> Bool {
        let ends: Set<String> = ["cab", "head", "tail", "leading", "trailing", "rear", "single", "formation",
                                 "locomotive", "ed", "dm", "e1000", "e200", "steam", "duplex"]
        return !name.split(separator: "-").contains { ends.contains(String($0)) }
    }

    /// Every model of `models` with its shade baked in (``baked(_:)``):
    /// the models alike worked out once, the rest side by side on the
    /// device's cores (the same shade, whichever order they finish in).
    static func baked(_ models: [Map3DModelPack.Model]) -> [Map3DModelPack.Model] {
        var first: [Key: Int] = [:], unique: [Int] = []
        var slot = [Int](repeating: -1, count: models.count)
        for (index, model) in models.enumerated() where isTrain(model.name) && !model.vertices.isEmpty {
            let key = Key(model)
            if let known = first[key] {
                slot[index] = known
            } else {
                first[key] = unique.count
                slot[index] = unique.count
                unique.append(index)
            }
        }
        let results = UnsafeMutableBufferPointer<[Float]>.allocate(capacity: unique.count)
        results.initialize(repeating: [])
        defer { results.deallocate() }
        nonisolated(unsafe) let shared = results
        let order = unique
        DispatchQueue.concurrentPerform(iterations: order.count) { u in
            shared[u] = shades(of: models[order[u]])
        }
        return models.indices.map { slot[$0] < 0 ? models[$0] : applying(results[slot[$0]], to: models[$0]) }
    }

    /// Model `model` with its shade baked in, or as it was when it is not
    /// a train's.
    public static func baked(_ model: Map3DModelPack.Model) -> Map3DModelPack.Model {
        guard isTrain(model.name), !model.vertices.isEmpty else { return model }
        return applying(shades(of: model), to: model)
    }

    static func applying(_ shade: [Float], to model: Map3DModelPack.Model) -> Map3DModelPack.Model {
        var vertices = model.vertices
        for index in vertices.indices where !vertices[index].glows && shade[index] > 0 {
            vertices[index].color = Map3DColor.shaded(vertices[index].color, 1 - strength * shade[index])
        }
        return Map3DModelPack.Model(name: model.name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }

    /// What a model's shade hangs on: its corners and normals, and whether
    /// it is far and a middle car.
    struct Key: Hashable {
        let digest: UInt64
        let count: Int
        let far: Bool
        let middle: Bool

        init(_ model: Map3DModelPack.Model) {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            func mix(_ value: Float) { hash = (hash ^ UInt64(value.bitPattern)) &* 0x100_0000_01b3 }
            for v in model.vertices {
                mix(v.x); mix(v.y); mix(v.z); mix(v.nx); mix(v.ny); mix(v.nz)
            }
            digest = hash
            count = model.vertices.count
            far = Map3DTrainOcclusion.isFar(model.name)
            middle = Map3DTrainOcclusion.isMiddle(model.name)
        }
    }

    /// Each vertex's shade, 0 (open) to 1 (shut in).
    static func shades(of model: Map3DModelPack.Model) -> [Float] {
        let grid = Grid(model, cell: isFar(model.name) ? farCell : nearCell, neighbours: isMiddle(model.name))
        let vertices = model.vertices
        var shade = grid.shades(vertices)
        for start in stride(from: 0, to: vertices.count - 2, by: 3) {
            let corners = (0..<3).map { Map3DPoint(vertices[start + $0].x, vertices[start + $0].y, vertices[start + $0].z) }
            let longest = max((corners[0] - corners[1]).length, (corners[1] - corners[2]).length, (corners[2] - corners[0]).length)
            guard longest > longEdge else { continue }
            let lightest = min(shade[start], shade[start + 1], shade[start + 2])
            for k in 0..<3 { shade[start + k] = lightest }
        }
        return shade
    }

    /// The cubes round a model, as their summed table.
    struct Grid {
        let origin: Map3DPoint
        let cell: Float
        let nx: Int, ny: Int, nz: Int
        /// (nx + 1)(ny + 1)(nz + 1): the sum of the cubes below and before
        /// each corner.
        let sums: [Int32]

        init(_ model: Map3DModelPack.Model, cell: Float, neighbours: Bool) {
            // As far as a box reaches out from a corner.
            let reach = 2 * (Map3DTrainOcclusion.scales.max() ?? 1) + cell
            let lengthwise = reach + (neighbours ? Map3DTrainOcclusion.gangway : 0)
            // The ground's cubes are the lowest layer, under the rail.
            let origin = Map3DPoint(model.minimum.x - lengthwise, model.minimum.y - reach, min(model.minimum.z, 0) - cell)
            let nx = Int(((model.maximum.x + lengthwise - origin.x) / cell).rounded(.up))
            let ny = Int(((model.maximum.y + reach - origin.y) / cell).rounded(.up))
            let nz = Int(((model.maximum.z + reach - origin.z) / cell).rounded(.up))
            (self.origin, self.cell, self.nx, self.ny, self.nz) = (origin, cell, nx, ny, nz)
            var cubes = [Int32](repeating: 0, count: nx * ny * nz)
            cubes.withUnsafeMutableBufferPointer { cubes in
                func mark(_ x: Float, _ y: Float, _ z: Float) {
                    let i = Int((x - origin.x) / cell), j = Int((y - origin.y) / cell), k = Int((z - origin.z) / cell)
                    guard i >= 0, i < nx, j >= 0, j < ny, k >= 0, k < nz else { return }
                    cubes[(k * ny + j) * nx + i] = 2
                }
                // The ground: the layer under the rail.
                for index in 0..<(nx * ny) { cubes[index] = 1 }
                // Every face, in rows across it closer than a cube apart,
                // each row at points closer than a cube apart: as many
                // points as its area needs.
                let spacing = cell * 0.7
                model.vertices.withUnsafeBufferPointer { v in
                    for start in stride(from: 0, to: v.count - 2, by: 3) {
                        var p = Map3DPoint(v[start].x, v[start].y, v[start].z)
                        var q = Map3DPoint(v[start + 1].x, v[start + 1].y, v[start + 1].z)
                        var r = Map3DPoint(v[start + 2].x, v[start + 2].y, v[start + 2].z)
                        // p–q the longest edge, r the corner across it.
                        if (r - q).length > (q - p).length, (r - q).length >= (p - r).length { (p, r) = (r, p) }
                        else if (p - r).length > (q - p).length { (q, r) = (r, q) }
                        let base = (q - p).length
                        let height = base > 0 ? (q - p).cross(r - p).length / base : 0
                        let rows = max(1, Int((height / spacing).rounded(.up)))
                        for row in 0...rows {
                            let w = Float(row) / Float(rows)
                            let a = p + (r - p) * w, b = q + (r - q) * w
                            let points = max(1, Int(((b - a).length / spacing).rounded(.up)))
                            for point in 0...points {
                                let c = a + (b - a) * (Float(point) / Float(points))
                                mark(c.x, c.y, c.z)
                            }
                        }
                    }
                }
                // A middle car's neighbours: the next car's end, a gangway away.
                if neighbours {
                    for x in [model.maximum.x + Map3DTrainOcclusion.gangway, model.minimum.x - Map3DTrainOcclusion.gangway] {
                        var y = model.minimum.y
                        while y <= model.maximum.y {
                            var z = max(model.minimum.z, 0)
                            while z <= model.maximum.z {
                                mark(x, y, z)
                                z += cell * 0.7
                            }
                            y += cell * 0.7
                        }
                    }
                }
            }
            // The summed table.
            let sx = nx + 1, sy = ny + 1
            var sums = [Int32](repeating: 0, count: sx * sy * (nz + 1))
            sums.withUnsafeMutableBufferPointer { sums in
                cubes.withUnsafeBufferPointer { cubes in
                    for k in 0..<nz {
                        for j in 0..<ny {
                            var row: Int32 = 0
                            for i in 0..<nx {
                                row += cubes[(k * ny + j) * nx + i]
                                let here = ((k + 1) * sy + (j + 1)) * sx + (i + 1)
                                sums[here] = row + sums[here - sx] + sums[here - sx * sy] - sums[here - sx - sx * sy]
                            }
                        }
                    }
                }
            }
            self.sums = sums
        }

        /// Each vertex of `vertices`: the mean of the boxes' shades, a box
        /// ``scales`` half a side held out from it along its normal.
        func shades(_ vertices: [Map3DVertex]) -> [Float] {
            let sx = nx + 1, sy = ny + 1, plane = sx * sy
            let (nx, ny, nz, cell) = (nx, ny, nz, cell)
            let (ox, oy, oz) = (origin.x, origin.y, origin.z)
            let scales = Map3DTrainOcclusion.scales, falloff = Map3DTrainOcclusion.falloff
            var shade = [Float](repeating: 0, count: vertices.count)
            sums.withUnsafeBufferPointer { s in
                vertices.withUnsafeBufferPointer { v in
                    for index in 0..<v.count {
                        let vertex = v[index]
                        var total: Float = 0
                        for half in scales {
                            let out = half + cell * 0.75
                            let cx = vertex.x + vertex.nx * out, cy = vertex.y + vertex.ny * out, cz = vertex.z + vertex.nz * out
                            let i0 = min(max(Int(((cx - half - ox) / cell).rounded()), 0), nx)
                            let i1 = min(max(Int(((cx + half - ox) / cell).rounded()), 0), nx)
                            let j0 = min(max(Int(((cy - half - oy) / cell).rounded()), 0), ny)
                            let j1 = min(max(Int(((cy + half - oy) / cell).rounded()), 0), ny)
                            let k0 = min(max(Int(((cz - half - oz) / cell).rounded()), 0), nz)
                            let k1 = min(max(Int(((cz + half - oz) / cell).rounded()), 0), nz)
                            guard i1 > i0, j1 > j0, k1 > k0 else { continue }
                            let a0 = k0 * plane, a1 = k1 * plane, b0 = j0 * sx, b1 = j1 * sx
                            let sum = s[a1 + b1 + i1] - s[a1 + b1 + i0] - s[a1 + b0 + i1] - s[a0 + b1 + i1]
                                + s[a1 + b0 + i0] + s[a0 + b1 + i0] + s[a0 + b0 + i1] - s[a0 + b0 + i0]
                            let side = 2 * half / cell
                            // A wall across the box is side² cubes of 2.
                            let walls = falloff * Float(sum) / (2 * side * side)
                            total += walls / (1 + walls)
                        }
                        shade[index] = total / Float(scales.count)
                    }
                }
            }
            return shade
        }
    }
}
