import Foundation

/// The builder of the airport and aircraft studies (decisions 594 and 698):
/// closed solids in the model's own space, x forward, y left, z up, metres.
/// It is the same recipe as `tools/airport-aircraft-studies/produce.py`,
/// which writes the preview pack; the two are compared by
/// `tools/airport-aircraft-studies/parity.sh`.
struct Map3DStudyMesh {
    typealias Paint = (color: UInt32, glow: Bool)
    typealias Triangle = (a: Map3DPoint, b: Map3DPoint, c: Map3DPoint, paint: Paint)
    /// Where a face of a loft lies: on the cap of its first ring, of its
    /// last ring, or between ring `n` and the next.
    enum Band: Equatable { case start, end, band(Int) }

    private(set) var triangles: [Triangle] = []

    /// One closed solid. Its triangles are turned to face outward, so a
    /// recipe need not mind the order of its rings.
    mutating func solid(_ faces: [Triangle]) {
        var volume = 0.0
        for t in faces {
            let n = t.b.cross(t.c)
            volume += Double(t.a.x) * Double(n.x) + Double(t.a.y) * Double(n.y) + Double(t.a.z) * Double(n.z)
        }
        triangles += volume < 0 ? faces.map { ($0.a, $0.c, $0.b, $0.paint) } : faces
    }

    /// A closed skin over rings of equal count, capped at both ends.
    mutating func loft(_ rings: [[Map3DPoint]], _ paint: (Band, Int) -> Paint) {
        let n = rings[0].count, first = rings[0], last = rings[rings.count - 1]
        var faces: [Triangle] = []
        for i in 1..<(n - 1) {
            faces.append((first[0], first[i + 1], first[i], paint(.start, i)))
            faces.append((last[0], last[i], last[i + 1], paint(.end, i)))
        }
        for k in 0..<(rings.count - 1) {
            let a = rings[k], b = rings[k + 1]
            for i in 0..<n {
                let j = (i + 1) % n, p = paint(.band(k), i)
                faces.append((a[i], a[j], b[j], p)); faces.append((a[i], b[j], b[i], p))
            }
        }
        solid(faces)
    }

    mutating func loft(_ rings: [[Map3DPoint]], _ color: UInt32, glow: Bool = false) {
        loft(rings) { _, _ in (color, glow) }
    }

    mutating func box(_ x: Float, _ y: Float, _ z: Float, _ length: Float, _ width: Float, _ height: Float, _ color: UInt32, glow: Bool = false) {
        var v: [Map3DPoint] = []
        for sz: Float in [0, 1] { for sy: Float in [-1, 1] { for sx: Float in [-1, 1] {
            v.append(Map3DPoint(x + sx * length / 2, y + sy * width / 2, z + sz * height))
        } } }
        var faces: [Triangle] = []
        for f in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [1, 3, 7, 5], [3, 2, 6, 7], [2, 0, 4, 6]] {
            faces.append((v[f[0]], v[f[1]], v[f[2]], (color, glow))); faces.append((v[f[0]], v[f[2]], v[f[3]], (color, glow)))
        }
        solid(faces)
    }

    private static func unit(_ p: Map3DPoint) -> Map3DPoint { p * (1 / p.length) }

    /// A round bar from `a` to `b`, `radius` at `a` and `endRadius` at `b`.
    mutating func cylinder(_ a: Map3DPoint, _ b: Map3DPoint, _ radius: Float, _ color: UInt32, sides: Int = 10, endRadius: Float? = nil, glow: Bool = false) {
        let d = Self.unit(b - a)
        let u = Self.unit(d.cross(abs(d.z) < 0.9 ? Map3DPoint(0, 0, 1) : Map3DPoint(1, 0, 0))), v = d.cross(u)
        func ring(_ p: Map3DPoint, _ r: Float) -> [Map3DPoint] {
            (0..<sides).map { i in
                let angle = 2 * Float.pi * Float(i) / Float(sides)
                return p + u * (r * cosf(angle)) + v * (r * sinf(angle))
            }
        }
        loft([ring(a, radius), ring(b, endRadius ?? radius)], color, glow: glow)
    }

    /// A rectangular bar from `a` to `b`: `width` across, `height` along `up`.
    mutating func bar(_ a: Map3DPoint, _ b: Map3DPoint, _ width: Float, _ height: Float, _ color: UInt32, up: Map3DPoint = Map3DPoint(0, 0, 1), glow: Bool = false) {
        let d = Self.unit(b - a), side = Self.unit(up.cross(d)), rise = d.cross(side)
        func ring(_ p: Map3DPoint) -> [Map3DPoint] {
            [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { p + side * (Float($0.0) * width / 2) + rise * (Float($0.1) * height / 2) }
        }
        loft([ring(a), ring(b)], color, glow: glow)
    }

    /// A square beam (the fence's arms), as the ferry studies' mesh makes it.
    mutating func beam(_ a: Map3DPoint, _ b: Map3DPoint, _ size: Float, _ color: UInt32) {
        let d = Self.unit(b - a)
        let u0 = Self.unit(d.cross(abs(d.z) < 0.95 ? Map3DPoint(0, 0, 1) : Map3DPoint(0, 1, 0)))
        let u = u0 * (size / 2), v = d.cross(u0) * (size / 2)
        func ring(_ p: Map3DPoint) -> [Map3DPoint] {
            [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { p + u * Float($0.0) + v * Float($0.1) }
        }
        loft([ring(a), ring(b)], color)
    }

    /// A thin plate on a surface: four corners, pushed out along their normal.
    mutating func slab(_ corners: [Map3DPoint], _ color: UInt32, glow: Bool = false, out: Float = 0.02, back: Float = 0.04) {
        let n = Self.unit((corners[1] - corners[0]).cross(corners[3] - corners[0]))
        loft([corners.map { $0 + n * (-back) }, corners.map { $0 + n * out }], color, glow: glow)
    }

    /// A thin disc on the ground: the pool a lamp lights.
    mutating func disc(_ x: Float, _ y: Float, _ z: Float, _ radius: Float, _ color: UInt32, glow: Bool = false, sides: Int = 8) {
        cylinder(Map3DPoint(x, y, z), Map3DPoint(x, y, z + 0.004), radius, color, sides: sides, glow: glow)
    }

    /// A fuselage section at `x`: a superellipse of exponent `e` (2 is round,
    /// larger is boxy), `halfWidth` wide, `up` above and `down` below `zc`.
    static func section(_ x: Float, _ zc: Float, _ halfWidth: Float, _ up: Float, _ down: Float, _ sides: Int, _ e: Float, y: Float = 0) -> [Map3DPoint] {
        (0..<sides).map { i in
            let angle = 2 * Float.pi * (Float(i) + 0.5) / Float(sides), c = cosf(angle), s = sinf(angle)
            let across = halfWidth * (c < 0 ? -1 : 1) * powf(abs(c), 2 / e)
            let rise = (s >= 0 ? up : down) * (s < 0 ? -1 : 1) * powf(abs(s), 2 / e)
            return Map3DPoint(x, across + y, zc + rise)
        }
    }

    private static let aerofoilProfile: [(Float, Float)] = [(0, 0), (0.07, 0.58), (0.30, 1), (0.66, 0.60), (1, 0.05), (0.66, -0.36), (0.30, -0.55), (0.07, -0.42)]
    /// A wing section: `leading` edge, `chord` back along x, `thickness` along `across`.
    static func aerofoil(_ leading: Map3DPoint, _ chord: Float, _ thickness: Float, across: Map3DPoint = Map3DPoint(0, 0, 1)) -> [Map3DPoint] {
        aerofoilProfile.map { Map3DPoint(leading.x - chord * $0.0, leading.y, leading.z) + across * (thickness * $0.1 * 0.5) }
    }

    /// A round wheel on the ground at (x, y), its axle along y.
    mutating func wheel(_ x: Float, _ y: Float, _ radius: Float, _ width: Float, far: Bool) {
        cylinder(Map3DPoint(x, y - width / 2, radius), Map3DPoint(x, y + width / 2, radius), radius, Map3DStudyColor.tyre, sides: far ? 6 : 12)
        if !far {
            cylinder(Map3DPoint(x, y - width / 2 - 0.012, radius), Map3DPoint(x, y + width / 2 + 0.012, radius), radius * 0.40, Map3DStudyColor.metal, sides: 8)
        }
    }

    func model(named name: String) -> Map3DModelPack.Model {
        var vertices: [Map3DVertex] = []
        vertices.reserveCapacity(triangles.count * 3)
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        for t in triangles {
            guard let normal = (t.b - t.a).cross(t.c - t.a).normalized else { continue }
            for p in [t.a, t.b, t.c] {
                vertices.append(Map3DVertex(p, normal: normal, color: t.paint.color, u: 0, layer: t.paint.glow ? Map3DVertex.glowing : Map3DVertex.plain))
                low = Map3DPoint(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
                high = Map3DPoint(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
            }
        }
        return Map3DModelPack.Model(name: name, vertices: vertices, minimum: low, maximum: high)
    }
}

/// The studies' colours: muted and flat, beside the game's palette. Pavement
/// is grey; the first pass's navy runway read as water.
enum Map3DStudyColor {
    static let white = Map3DColor.rgb(0xEDEFF0), blue = Map3DColor.rgb(0x5F8BC0), red = Map3DColor.rgb(0xC65A4E)
    static let green = Map3DColor.rgb(0x5E8F86), navy = Map3DColor.rgb(0x2F4470), steel = Map3DColor.rgb(0x6E747B)
    static let deck = Map3DColor.rgb(0xC6C8CA), warm = Map3DColor.rgb(0xE3B349), asphalt = Map3DColor.rgb(0x4B4E56)
    static let taxi = Map3DColor.rgb(0x5C6069), joint = Map3DColor.rgb(0xA9ACB1), grass = Map3DColor.rgb(0xBDD1AB)
    static let belly = Map3DColor.rgb(0xC9CED6), cockpit = Map3DColor.rgb(0x22304A), tyre = Map3DColor.rgb(0x2A2C33)
    static let metal = Map3DColor.rgb(0x9BA2AB), wall = Map3DColor.rgb(0xDDE0E4), base = Map3DColor.rgb(0xB4B9C2)
    static let roof = Map3DColor.rgb(0x7F90A8), orange = Map3DColor.rgb(0xE28A3A), lamp = Map3DColor.rgb(0xFFF1C4)
    static let lampGreen = Map3DColor.rgb(0x62D29A), lampRed = Map3DColor.rgb(0xF0604E), lampBlue = Map3DColor.rgb(0x6FA8F5)
    static let window = Map3DColor.rgb(0x3B4D6B), hub = Map3DColor.rgb(0xD8DCE2), pane = Map3DColor.rgb(0x7C9BBB)
    /// The pavement's colour under a lamp: a shade below it, because a
    /// glowing face is drawn a shade brighter by day.
    static let litDeck = Map3DColor.rgb(0xC6C8CA - 0x060606), litAsphalt = Map3DColor.rgb(0x4B4E56 - 0x060606), litTaxi = Map3DColor.rgb(0x5C6069 - 0x060606)
}
