import GameCore

// The native 3D map's geometry (ARCHITECTURE decision 229): plain arrays of
// vertices and triangles worked out from the world, which the app hands to
// Metal as they are. Nothing here draws or touches a GPU, so it runs and is
// tested on Linux; nothing is saved or written back.
//
// Space: metres, x east, y up, z south (the world's y), measured from an
// origin the scene picks (``Map3DScene/origin``) so a map 500 km wide keeps
// its precision in `Float`. Right-handed: x × y = z.

/// One corner of a triangle: where it is, which way its face looks, and its
/// colour. Laid out as Metal reads it: 28 bytes, three floats of position
/// at 0, three of normal at 12, and four bytes of colour (red first) at 24.
public struct Map3DVertex: Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var nx: Float
    public var ny: Float
    public var nz: Float
    /// Red in the low byte, then green, blue and alpha.
    public var color: UInt32

    public init(_ position: Map3DPoint, normal: Map3DPoint, color: UInt32) {
        x = position.x
        y = position.y
        z = position.z
        nx = normal.x
        ny = normal.y
        nz = normal.z
        self.color = color
    }

    public var position: Map3DPoint { Map3DPoint(x, y, z) }
}

/// A point or direction in the 3D map's space, in metres.
public struct Map3DPoint: Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Map3DPoint(0, 0, 0)
    public static let up = Map3DPoint(0, 1, 0)

    public static func + (a: Map3DPoint, b: Map3DPoint) -> Map3DPoint { Map3DPoint(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Map3DPoint, b: Map3DPoint) -> Map3DPoint { Map3DPoint(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Map3DPoint, s: Float) -> Map3DPoint { Map3DPoint(a.x * s, a.y * s, a.z * s) }
    public static prefix func - (a: Map3DPoint) -> Map3DPoint { Map3DPoint(-a.x, -a.y, -a.z) }

    public func dot(_ b: Map3DPoint) -> Float { x * b.x + y * b.y + z * b.z }

    public func cross(_ b: Map3DPoint) -> Map3DPoint {
        Map3DPoint(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }

    public var length: Float { dot(self).squareRoot() }

    /// The same direction one metre long, or `nil` for no direction.
    public var normalized: Map3DPoint? {
        let size = length
        return size > 0 && size.isFinite ? self * (1 / size) : nil
    }
}

/// A colour as the vertices carry it.
public enum Map3DColor {
    /// `0xRRGGBB`, opaque.
    public static func rgb(_ hex: UInt32) -> UInt32 {
        let red = (hex >> 16) & 0xFF, green = (hex >> 8) & 0xFF, blue = hex & 0xFF
        return red | green << 8 | blue << 16 | 0xFF << 24
    }

    public static func rgb(_ color: PopTravel.RGB) -> UInt32 {
        UInt32(color.red) | UInt32(color.green) << 8 | UInt32(color.blue) << 16 | 0xFF << 24
    }

    /// `color` with each channel times `factor` (0–1): a darker side.
    public static func shaded(_ color: UInt32, _ factor: Float) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let value = Float((color >> shift) & 0xFF) * min(max(factor, 0), 1)
            return UInt32(value.rounded()) << shift
        }
        return channel(0) | channel(8) | channel(16) | (color & 0xFF00_0000)
    }
}

/// Triangles in one buffer: what one draw call draws.
public struct Map3DMesh: Sendable {
    public private(set) var vertices: [Map3DVertex] = []
    /// Three to a triangle, counter-clockwise seen from outside.
    public private(set) var indices: [UInt32] = []

    public init() {}

    public var triangleCount: Int { indices.count / 3 }
    public var isEmpty: Bool { indices.isEmpty }

    /// The smallest box holding every vertex, or `nil` when empty.
    public var bounds: (min: Map3DPoint, max: Map3DPoint)? {
        guard let first = vertices.first else { return nil }
        var low = first.position, high = first.position
        for vertex in vertices {
            low = Map3DPoint(min(low.x, vertex.x), min(low.y, vertex.y), min(low.z, vertex.z))
            high = Map3DPoint(max(high.x, vertex.x), max(high.y, vertex.y), max(high.z, vertex.z))
        }
        return (low, high)
    }

    /// One triangle of the three vertices as they are, each keeping its own
    /// colour.
    public mutating func appendTriangle(_ corners: [Map3DVertex]) {
        precondition(corners.count == 3)
        let base = UInt32(vertices.count)
        vertices += corners
        indices += [base, base + 1, base + 2]
    }

    public mutating func append(_ other: Map3DMesh) {
        let base = UInt32(vertices.count)
        vertices += other.vertices
        indices += other.indices.map { $0 + base }
    }

    /// A flat four-cornered face, `a b c d` counter-clockwise seen from
    /// the side it faces.
    public mutating func addQuad(_ a: Map3DPoint, _ b: Map3DPoint, _ c: Map3DPoint, _ d: Map3DPoint, color: UInt32) {
        guard let normal = (b - a).cross(d - a).normalized ?? (c - b).cross(a - b).normalized else { return }
        let base = UInt32(vertices.count)
        for corner in [a, b, c, d] {
            vertices.append(Map3DVertex(corner, normal: normal, color: color))
        }
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
    }

    /// A box standing on `base` (the middle of its floor), `length` along
    /// `forward` (a level direction), `width` across it and `height` up;
    /// the top in `top`, the sides in `side` shaded by the way they face.
    /// No floor: nothing looks at it from below.
    public mutating func addBox(
        base: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, -1), length: Float, width: Float, height: Float,
        top: UInt32, side: UInt32
    ) {
        guard length > 0, width > 0, height > 0,
              let along = Map3DPoint(forward.x, 0, forward.z).normalized else { return }
        let across = Map3DPoint(-along.z, 0, along.x) // to the right of `along`, seen from above
        let f = along * (length / 2), r = across * (width / 2), h = Map3DPoint(0, height, 0)
        let corners = [base + f - r, base + f + r, base - f + r, base - f - r] // front left, front right, back right, back left
        let up = corners.map { $0 + h }
        addQuad(up[0], up[3], up[2], up[1], color: top)
        // Each side, counter-clockwise from outside: ground, ground, top, top.
        let sides: [(Int, Int, Float)] = [(1, 0, 0.92), (2, 1, 0.80), (3, 2, 0.70), (0, 3, 0.86)]
        for (from, to, shade) in sides {
            addQuad(corners[from], corners[to], up[to], up[from], color: Map3DColor.shaded(side, shade))
        }
    }

    /// A strip `width` wide following `line` at its heights plus `lift`,
    /// facing up: ballast, a rail, a deck. Its sides along the line hang
    /// `depth` down when `depth` is more than 0.
    public mutating func addRibbon(
        along line: [Map3DPoint], width: Float, offset: Float = 0, lift: Float = 0, depth: Float = 0, top: UInt32, side: UInt32? = nil
    ) {
        guard line.count > 1 else { return }
        let across = Self.acrossDirections(line)
        let half = width / 2
        let left = line.indices.map { line[$0] + across[$0] * (offset - half) + Map3DPoint(0, lift, 0) }
        let right = line.indices.map { line[$0] + across[$0] * (offset + half) + Map3DPoint(0, lift, 0) }
        for index in 0..<(line.count - 1) {
            addQuad(left[index], right[index], right[index + 1], left[index + 1], color: top)
            if depth > 0, let side {
                let drop = Map3DPoint(0, -depth, 0)
                addQuad(right[index + 1], right[index], right[index] + drop, right[index + 1] + drop, color: Map3DColor.shaded(side, 0.82))
                addQuad(left[index], left[index + 1], left[index + 1] + drop, left[index] + drop, color: Map3DColor.shaded(side, 0.72))
            }
        }
    }

    /// The level direction to the right of `line` at each point, averaged
    /// over the pieces on either side (a mitre, without lengthening it).
    static func acrossDirections(_ line: [Map3DPoint]) -> [Map3DPoint] {
        func level(_ a: Map3DPoint, _ b: Map3DPoint) -> Map3DPoint? {
            Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized
        }
        var pieces: [Map3DPoint?] = []
        for index in 0..<(line.count - 1) { pieces.append(level(line[index], line[index + 1])) }
        var fallback = pieces.compactMap { $0 }.first ?? Map3DPoint(0, 0, -1)
        return line.indices.map { index in
            let before = index > 0 ? pieces[index - 1] : nil, after = index < pieces.count ? pieces[index] : nil
            let direction = ((before ?? after ?? fallback) + (after ?? before ?? fallback)).normalized ?? fallback
            fallback = direction
            return Map3DPoint(-direction.z, 0, direction.x)
        }
    }
}

/// A 4 × 4 matrix in Metal's order: column by column.
public struct Map3DMatrix: Hashable, Sendable {
    public var columns: [Float]

    public init(columns: [Float]) {
        precondition(columns.count == 16)
        self.columns = columns
    }

    public static let identity = Map3DMatrix(columns: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

    public subscript(row: Int, column: Int) -> Float {
        get { columns[column * 4 + row] }
        set { columns[column * 4 + row] = newValue }
    }

    public static func * (a: Map3DMatrix, b: Map3DMatrix) -> Map3DMatrix {
        var result = [Float](repeating: 0, count: 16)
        for column in 0..<4 {
            for row in 0..<4 {
                var sum: Float = 0
                for k in 0..<4 { sum += a[row, k] * b[k, column] }
                result[column * 4 + row] = sum
            }
        }
        return Map3DMatrix(columns: result)
    }

    /// `point` taken through the matrix, divided by its w: in clip space,
    /// x and y from −1 to 1 across the view and depth from 0 to 1. `nil`
    /// behind the eye.
    public func project(_ point: Map3DPoint) -> Map3DPoint? {
        let v = [point.x, point.y, point.z, 1]
        var out = [Float](repeating: 0, count: 4)
        for row in 0..<4 {
            for k in 0..<4 { out[row] += self[row, k] * v[k] }
        }
        guard out[3] > 0 else { return nil }
        return Map3DPoint(out[0] / out[3], out[1] / out[3], out[2] / out[3])
    }
}

/// `Railway/` rail-3d's `randomAt` (`geo.js`): the same 32-bit hash of a
/// whole-number point and a salt, from 0 up to 1. Decoration chosen by it
/// stays where it is from frame to frame and game to game, unlike the
/// references' `Math.random()`.
public func map3DRandom(_ x: Int32, _ y: Int32, salt: Int32 = 0) -> Float {
    var h = x &* 374_761_393 ^ y &* 668_265_263 ^ (salt &+ 1) &* 1_274_126_177
    h = (h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 13)) &* 1_274_126_177
    let mixed = UInt32(bitPattern: h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 16))
    return Float(Double(mixed) / 4_294_967_296)
}
