import Foundation

/// Decision 575 (amendment): the Maokong gondola's cabin and station
/// furnishings, translated from Codex's studies producers — the cabin from
/// `tools/maokong-cabin-refine/produce.py` (PR #1791, commit 5cfec29) and the
/// platform, gate, queue rail, catwalk and ticket kiosk from
/// `tools/cable-support-studies/produce.py` (PR #1786, commit 2f8799c). The
/// shapes, sizes and colours are theirs; this is the Swift form the native
/// model pack builds. Native space: +x along the rope, +y left, +z up, metres.
///
/// Every part is made of closed solids (outward counter-clockwise triangles),
/// so the pack's flat shading and the tools' closed-solid check read it as the
/// producers did. UNVERIFIED as theirs: the cabin body 1.98 × 1.873 × 2.41 m is
/// the Taipei Metro's customer-service figure retold in a 2015 science-fair
/// paper (not a factory drawing), the 48 mm floor is the metro's own, and the
/// hanger, door frame, seats and glass area are proportions read off photos.
enum CableParts {
    /// Codex's palette (the studies' own look).
    enum Paint {
        static let white = Map3DColor.rgb(0xEDEFF0)
        static let blue = Map3DColor.rgb(0x5F8BC0)
        static let red = Map3DColor.rgb(0xC65A4E)
        static let green = Map3DColor.rgb(0x5E8F86)
        static let steel = Map3DColor.rgb(0x6E747B)
        static let dark = Map3DColor.rgb(0x26385C)
        static let deck = Map3DColor.rgb(0xDCD6C8)
        static let glass = Map3DColor.rgb(0x9DB3C2)
        static let warm = Map3DColor.rgb(0xFFE2A6)
        static let wood = Map3DColor.rgb(0x8E6E52)
    }

    /// Where a cabin's floor is below the rope: the body shifted 0.78 m down
    /// the hanger (photo ratio, hanger about 0.85 of the body's height).
    static let hangerShift: Float = 0.78
    static let cabinFloor: Float = -3.6 - hangerShift
}

/// One part's triangles in native space, and the closed solids they form.
struct CableSolids {
    struct Triangle { var a: Map3DPoint, b: Map3DPoint, c: Map3DPoint; var color: UInt32; var glows: Bool; var glass = false }
    var triangles: [Triangle] = []
    /// Each solid's triangle range, for the closed-solid check.
    var solids: [Range<Int>] = []

    typealias P = Map3DPoint

    mutating func solid(_ vertices: [P], _ faces: [[Int]], _ color: UInt32, glow: Bool = false, glass: Bool = false) {
        let start = triangles.count
        for face in faces where face.count >= 3 {
            for i in 1..<(face.count - 1) {
                triangles.append(Triangle(a: vertices[face[0]], b: vertices[face[i]], c: vertices[face[i + 1]], color: color, glows: glow,
                                          glass: glass))
            }
        }
        solids.append(start..<triangles.count)
    }

    mutating func box(_ x: Float, _ y: Float, _ z: Float, _ l: Float, _ w: Float, _ h: Float, _ color: UInt32, glow: Bool = false,
                      glass: Bool = false) {
        var v: [P] = []
        for sz: Float in [0, 1] {
            for sy: Float in [-1, 1] {
                for sx: Float in [-1, 1] { v.append(P(x + sx * l / 2, y + sy * w / 2, z + sz * h)) }
            }
        }
        solid(v, [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [1, 3, 7, 5], [3, 2, 6, 7], [2, 0, 4, 6]], color, glow: glow, glass: glass)
    }

    /// A square bar of side `r` from `a` to `b`.
    mutating func beam(_ a: P, _ b: P, _ r: Float, _ color: UInt32) {
        guard let d = (b - a).normalized else { return }
        let reference = abs(d.z) < 0.95 ? P(0, 0, 1) : P(0, 1, 0)
        guard let un = d.cross(reference).normalized else { return }
        let u = un * (r / 2), v = d.cross(un) * (r / 2)
        var p: [P] = []
        for q in [a, b] { for (s, t) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] { p.append(q + u * s + v * t) } }
        solid(p, [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]], color)
    }

    mutating func cylinder(_ a: P, _ b: P, _ r: Float, _ color: UInt32, sides n: Int = 12) {
        guard let d = (b - a).normalized else { return }
        let reference = abs(d.z) < 0.9 ? P(0, 0, 1) : P(0, 1, 0)
        guard let u = d.cross(reference).normalized else { return }
        let v = d.cross(u)
        var p: [P] = []
        for q in [a, b] {
            for i in 0..<n {
                let t = Float(i) * 2 * Float.pi / Float(n)
                p.append(q + u * (r * cosf(t)) + v * (r * sinf(t)))
            }
        }
        var faces: [[Int]] = [Array((0..<n).reversed()), Array(n..<(2 * n))]
        for i in 0..<n { faces.append([i, (i + 1) % n, (i + 1) % n + n, i + n]) }
        solid(p, faces, color)
    }

    /// A tube through `points`, one ring at each, capped at both ends.
    mutating func tube(_ points: [P], _ r: Float, _ color: UInt32, far: Bool) {
        let n = far ? 6 : 10
        var p: [P] = []
        for (i, q) in points.enumerated() {
            guard let d = (points[min(i + 1, points.count - 1)] - points[max(0, i - 1)]).normalized else { return }
            let reference = abs(d.z) < 0.9 ? P(0, 0, 1) : P(0, 1, 0)
            guard let u = d.cross(reference).normalized else { return }
            let v = d.cross(u)
            for j in 0..<n {
                let t = Float(j) * 2 * Float.pi / Float(n)
                p.append(q + u * (r * cosf(t)) + v * (r * sinf(t)))
            }
        }
        var faces: [[Int]] = [Array((0..<n).reversed()), Array(((points.count - 1) * n)..<(points.count * n))]
        for i in 0..<(points.count - 1) {
            for j in 0..<n { faces.append([i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n, (i + 1) * n + j]) }
        }
        solid(p, faces, color)
    }

    /// A rounded rectangle `l` × `w`, corner radius `r`, at height `z`.
    static func rounded(_ l: Float, _ w: Float, _ r: Float, _ z: Float, _ segments: Int) -> [P] {
        var p: [P] = []
        let corners: [(Float, Float, Float)] = [(l / 2 - r, w / 2 - r, 0), (-l / 2 + r, w / 2 - r, 1), (-l / 2 + r, -w / 2 + r, 2), (l / 2 - r, -w / 2 + r, 3)]
        for (cx, cy, quarter) in corners {
            for j in 0...segments {
                let a = (quarter + Float(j) / Float(segments)) * Float.pi / 2
                p.append(P(cx + r * cosf(a), cy + r * sinf(a), z))
            }
        }
        return p
    }

    /// A shell lofted through `levels` (height, length, width, radius),
    /// solid or hollow with a wall `thickness`.
    mutating func loft(_ levels: [(Float, Float, Float, Float)], _ color: UInt32, far: Bool, hollow: Bool = false,
                       glow: Bool = false, glass: Bool = false, thickness: Float = 0.035, nearSegments: Int = 5) {
        let segments = far ? 2 : nearSegments
        let rings = levels.map { Self.rounded($0.1, $0.2, $0.3, $0.0, segments) }
        let n = rings[0].count, count = rings.count
        var p = rings.flatMap { $0 }
        var faces: [[Int]] = []
        for i in 0..<(count - 1) {
            for j in 0..<n { faces.append([i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n, (i + 1) * n + j]) }
        }
        if hollow {
            let inner = levels.map { Self.rounded($0.1 - 2 * thickness, $0.2 - 2 * thickness, max(0.025, $0.3 - thickness), $0.0, segments) }
            let start = p.count
            p += inner.flatMap { $0 }
            for i in 0..<(count - 1) {
                for j in 0..<n {
                    faces.append([start + i * n + (j + 1) % n, start + i * n + j, start + (i + 1) * n + j, start + (i + 1) * n + (j + 1) % n])
                }
            }
            for j in 0..<n { faces.append([(j + 1) % n, j, start + j, start + (j + 1) % n]) }
            let outer = (count - 1) * n, inside = start + outer
            for j in 0..<n { faces.append([outer + j, outer + (j + 1) % n, inside + (j + 1) % n, inside + j]) }
        } else {
            faces.append(Array((0..<n).reversed()))
            faces.append(Array(((count - 1) * n)..<(count * n)))
        }
        solid(p, faces, color, glow: glow, glass: glass)
    }

    /// Moves the triangles from `start` on by `dz`.
    mutating func shift(from start: Int, dz: Float) {
        for i in start..<triangles.count {
            triangles[i].a.z += dz
            triangles[i].b.z += dz
            triangles[i].c.z += dz
        }
    }

    /// A railing from `a` to `b` standing on `a.z`: a post every 1.3 m (3 m
    /// far), one top rail (far) or two (near).
    mutating func rail(_ a: P, _ b: P, far: Bool) {
        let steps = max(1, Int(ceilf((b - a).length / (far ? 3 : 1.3))))
        for i in 0...steps {
            let p = a + (b - a) * (Float(i) / Float(steps))
            box(p.x, p.y, p.z, 0.065, 0.065, 1.0, CableParts.Paint.steel)
        }
        for h: Float in far ? [1] : [0.5, 1] { beam(a + P(0, 0, h), b + P(0, 0, h), 0.055, CableParts.Paint.steel) }
    }

    /// Whether every solid's edges pair up (each edge once each way) and its
    /// volume is positive: the producers' closed-solid check.
    func openSolids() -> [Int] {
        var bad: [Int] = []
        for (index, range) in solids.enumerated() {
            var edges: [String: Int] = [:]
            var volume: Float = 0
            func key(_ p: P, _ q: P) -> String { "\(p.x),\(p.y),\(p.z)>\(q.x),\(q.y),\(q.z)" }
            for t in triangles[range] {
                volume += t.a.dot(t.b.cross(t.c)) / 6
                for (p, q) in [(t.a, t.b), (t.b, t.c), (t.c, t.a)] { edges[key(p, q), default: 0] += 1 }
            }
            var closed = volume > 0
            for t in triangles[range] {
                for (p, q) in [(t.a, t.b), (t.b, t.c), (t.c, t.a)] where edges[key(q, p)] != edges[key(p, q)] { closed = false }
            }
            if !closed { bad.append(index) }
        }
        return bad
    }

    /// The triangles in the station kit's space (x forward, y up, z right);
    /// `place` takes a native point to that space (by default the plain
    /// turn: x, z, −y).
    func append(to mesh: inout Map3DMesh, place: (P) -> P = { P($0.x, $0.z, -$0.y) }) {
        for t in triangles {
            let corners = [t.a, t.b, t.c].map(place)
            guard let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized else { continue }
            // Decision 615: glass is marked as a train's glass, which
            // ``Map3DTransparentGlass`` then makes see-through.
            let layer = t.glass ? (t.glows ? Map3DVertex.trainGlassLit : Map3DVertex.trainGlass) : t.glows ? Map3DVertex.glowing : Map3DVertex.plain
            mesh.appendTriangle(corners.map { Map3DVertex($0, normal: normal, color: t.color, layer: layer) })
        }
    }
}

// MARK: - The cabins

extension CableSolids {
    /// The standard or crystal cabin: origin on the rope, the body hung below.
    static func cabin(crystal: Bool, far: Bool) -> CableSolids {
        typealias C = CableParts.Paint
        var m = CableSolids()
        var floor: Float = -3.6
        let accent = crystal ? C.red : C.green
        let n = far ? 8 : 16
        let lower: [(Float, Float, Float, Float)] = [(-3.68, 1.72, 1.57, 0.14), (-3.44, 1.80, 1.68, 0.16), (-3.08, 1.89, 1.78, 0.20)]
        let glazing: [(Float, Float, Float, Float)] = [(-3.08, 1.89, 1.78, 0.20), (-2.65, 1.90, 1.79, 0.21), (-2.05, 1.86, 1.74, 0.16), (-1.50, 1.72, 1.60, 0.10)]
        m.loft(lower, C.white, far: far, hollow: true)
        m.loft(glazing, C.glass, far: far, hollow: true, glass: true, thickness: 0.012)
        m.loft([(-1.50, 1.72, 1.60, 0.10), (-1.40, 1.82, 1.68, 0.12)], C.white, far: far, hollow: true)
        m.loft([(-1.40, 1.82, 1.68, 0.12), (-1.32, 1.84, 1.70, 0.14), (-1.27, 1.72, 1.58, 0.18)], C.white, far: far)
        // The floor: a solid slab, or a 48 mm laminated glass panel in a
        // steel frame (the crystal cabin).
        if !crystal {
            m.box(0, 0, -3.68, 1.66, 1.52, 0.08, C.deck)
        } else {
            for x: Float in [-0.76, 0.76] { m.box(x, 0, -3.68, 0.14, 1.52, 0.08, C.steel) }
            for y: Float in [-0.69, 0.69] { m.box(0, y, -3.68, 1.38, 0.14, 0.08, C.steel) }
            m.box(0, 0, floor - 0.048, 1.38, 1.24, 0.048, C.green, glass: true)
        }
        // A bench and back at each end; the crystal cabin keeps them too.
        for sign: Float in [-1, 1] {
            let x = sign * 0.63
            for y: Float in [-0.50, 0.50] { m.box(sign * 0.75, y, floor, 0.10, 0.12, 0.43, C.steel) }
            m.box(x, 0, floor + 0.43, 0.34, 1.36, 0.10, C.white)
            m.box(sign * 0.78, 0, floor + 0.53, 0.06, 1.36, 0.42, C.white)
            if !far { for y: Float in [-0.34, 0, 0.34] { m.box(x, y, floor + 0.53, 0.30, 0.012, 0.012, C.steel) } }
        }
        // Four swept corner posts with a colour panel and a rubber pad each.
        let postLevels: [(Float, Float, Float)] = [(-3.61, 0.80, 0.72), (-3.08, 0.86, 0.80), (-2.65, 0.86, 0.81), (-2.05, 0.84, 0.79), (-1.44, 0.78, 0.72)]
        for sx: Float in [-1, 1] {
            for sy: Float in [-1, 1] {
                let path = postLevels.map { P(sx * $0.1, sy * $0.2, $0.0) }
                m.tube(path, 0.048, C.white, far: far)
                m.tube(path.dropFirst().map { P($0.x + sx * 0.043, $0.y + sy * 0.043, $0.z) }, 0.044, accent, far: far)
                m.box(sx * 0.925, sy * 0.855, -2.91, 0.13, 0.163, 0.27, C.dark)
            }
        }
        // Two closed door leaves on the right (−y) side; the other side is
        // one broad pane.
        let doorLevels: [(Float, Float)] = [(-3.60, 0.76), (-3.10, 0.89), (-2.65, 0.895), (-2.05, 0.87), (-1.50, 0.80)]
        for x: Float in [-0.65, 0, 0.65] {
            m.tube(doorLevels.map { P(x, -$0.1 - 0.008, $0.0) }, x != 0 ? 0.029 : 0.018, x != 0 ? C.white : C.dark, far: far)
        }
        for (z, y) in [(Float(-3.60), Float(0.76)), (-1.50, 0.80)] { m.beam(P(-0.65, -y - 0.008, z), P(0.65, -y - 0.008, z), 0.055, C.white) }
        if !far {
            for x: Float in [-0.15, 0.15] {
                m.beam(P(x, -0.921, -2.70), P(x, -0.921, -2.46), 0.026, C.dark)
                for (z, y) in [(Float(-2.70), Float(-0.888)), (-2.46, -0.881)] { m.beam(P(x, y, z), P(x, -0.921, z), 0.026, C.dark) }
            }
        }
        m.box(0, -0.795, -3.63, 1.34, 0.10, 0.03, C.steel)
        // Fine ribs on the lower shell, seated on its sloping faces.
        if !far {
            for i in 0..<4 {
                let z = -3.52 + Float(i) * 0.09, t = (z + 3.68) / 0.60
                let lx = 0.86 + 0.085 * t, wy = 0.785 + 0.105 * t
                for sx: Float in [-1, 1] { m.box(sx * (lx + 0.005), 0, z, 0.018, 1.18, 0.018, C.steel) }
                m.box(0, wy + 0.005, z, 1.25, 0.018, 0.018, C.steel)
            }
        }
        // The end windows' vent strip and the handrail inside.
        for sx: Float in [-1, 1] {
            m.box(sx * 0.866, 0, -1.76, 0.025, 1.15, 0.15, C.dark)
            if !far { for i in 0..<3 { m.box(sx * 0.883, 0, -1.74 + Float(i) * 0.04, 0.012, 1.10, 0.012, C.steel) } }
            m.beam(P(sx * 0.80, -0.62, -2.57), P(sx * 0.80, 0.62, -2.57), 0.026, C.steel)
            for y: Float in [-0.62, 0.62] { m.beam(P(sx * 0.80, y, -2.57), P(sx * 0.94, y, -2.57), 0.026, C.steel) }
        }
        // The roof saddle and yoke.
        m.box(0, 0, -1.27, 0.80, 0.75, 0.09, C.steel)
        m.cylinder(P(0, -0.47, -1.12), P(0, 0.47, -1.12), 0.075, C.steel, sides: n)
        for y: Float in [-0.38, 0.38] {
            m.beam(P(-0.28, y, -1.24), P(0, y, -1.10), 0.075, C.steel)
            m.beam(P(0.28, y, -1.24), P(0, y, -1.10), 0.075, C.steel)
        }
        // The body hangs 0.78 m lower; then the bent hanger and the grip.
        m.shift(from: 0, dz: -CableParts.hangerShift)
        floor -= CableParts.hangerShift
        let hanger = [P(0, 0, -1.90), P(0, 0.02, -1.60), P(0, 0.34, -1.54), P(0, 0.50, -1.34), P(0, 0.48, -0.72), P(0, 0.38, -0.37), P(0, 0.12, -0.09)]
        m.tube(hanger, 0.066, C.steel, far: far)
        m.box(0, 0, -0.17, 0.62, 0.26, 0.10, C.steel)
        m.box(0, 0, -0.07, 0.58, 0.18, 0.02, C.dark)
        for y: Float in [-0.07, 0.07] { m.box(0, y, -0.05, 0.58, 0.04, 0.12, C.steel) }
        m.box(0, 0, 0.07, 0.58, 0.18, 0.035, C.steel)
        if !far {
            for x: Float in [-0.28, 0.20] { m.beam(P(x, -0.10, -0.12), P(x, -0.18, 0.16), 0.04, C.steel) }
            m.cylinder(P(-0.28, -0.18, 0.16), P(0.20, -0.18, 0.16), 0.04, C.dark)
            for i in 0..<7 { m.cylinder(P(-0.27 + Float(i) * 0.065, -0.18, 0.16), P(-0.25 + Float(i) * 0.065, -0.18, 0.16), 0.058, C.steel, sides: 8) }
            m.beam(P(0.20, -0.18, 0.16), P(0.43, -0.18, 0.24), 0.045, C.steel)
        }
        return m
    }
}

// MARK: - Station furnishings

extension CableSolids {
    /// The boarding platform (top 0.60 m above its foot, edge marking, three
    /// steps at the −x end). `length` is the island's, 8 m in the studies.
    static func platform(length: Float = 8, far: Bool) -> CableSolids {
        typealias C = CableParts.Paint
        var m = CableSolids()
        m.box(0, 0, 0, length, 3.3, 0.60, C.deck)
        for y: Float in [-1.57, 1.57] { m.box(0, y, 0.60, length, 0.16, 0.012, C.warm) }
        for i in 0..<3 { m.box(-length / 2 - 1.5 + Float(i) * 0.6, 0, 0, 0.6, 1.5, Float(i + 1) * 0.2, C.deck) }
        if !far {
            var x = -length / 2 + 1
            while x < length / 2 { m.box(x, 0, 0.60, 0.02, 2.9, 0.008, C.steel); x += 1 }
        }
        return m
    }

    /// The boarding gate: two housings and a leaf across (closed pose).
    static func gate(far: Bool) -> CableSolids {
        typealias C = CableParts.Paint
        var m = CableSolids()
        for y: Float in [-0.77, 0.77] {
            m.box(0, y, 0, 0.38, 0.30, 0.06, C.steel)
            m.box(0, y, 0.06, 0.26, 0.20, 1.02, C.white)
            m.box(0, y, 1.08, 0.29, 0.23, 0.06, C.green)
            m.box(0.136, y, 0.86, 0.012, 0.09, 0.10, C.warm, glow: true)
        }
        m.beam(P(0, -0.65, 0.25), P(0, -0.65, 1.0), 0.09, C.steel)
        m.beam(P(0, -0.65, 0.95), P(0, 0.65, 0.95), 0.06, C.steel)
        m.beam(P(0, -0.65, 0.28), P(0, 0.65, 0.28), 0.06, C.steel)
        for y: Float in far ? [-0.65, 0.65] : [-0.65, -0.325, 0, 0.325, 0.65] { m.beam(P(0, y, 0.28), P(0, y, 0.95), 0.05, C.green) }
        return m
    }

    /// A queue rail, 2 m long on its posts.
    static func queue(far: Bool) -> CableSolids {
        typealias C = CableParts.Paint
        var m = CableSolids()
        for x: Float in far ? [-1, 1] : [-1, 0, 1] {
            m.box(x, 0, 0, 0.23, 0.23, 0.05, C.steel)
            m.box(x, 0, 0.05, 0.065, 0.065, 0.95, C.steel)
        }
        for z: Float in far ? [1] : [0.52, 1] { m.beam(P(-1, 0, z), P(1, 0, z), 0.055, C.steel) }
        return m
    }

    /// A maintenance catwalk, 4 × 1.1 m: pan, grating, rails, mount plates
    /// (its underside z 0 is the mounting face — hang it from a beam).
    static func catwalk(far: Bool) -> CableSolids {
        typealias C = CableParts.Paint
        var m = CableSolids()
        m.box(0, 0, 0, 4, 1.1, 0.16, C.steel)
        if !far { for i in 0..<19 { m.box(-1.8 + Float(i) * 0.2, 0, 0.16, 0.025, 1.0, 0.018, C.deck) } }
        for y: Float in [-0.5, 0.5] { m.rail(P(-1.9, y, 0.16), P(1.9, y, 0.16), far: far) }
        for x: Float in [-1.7, 1.7] { m.box(x, 0, 0, 0.4, 1.1, 0.05, C.dark) }
        return m
    }

    /// A ticket kiosk, 2.4 × 2.2 m, front (the counter) toward +x.
    static func kiosk(far: Bool) -> CableSolids {
        typealias C = CableParts.Paint
        var m = CableSolids()
        m.box(0, 0, 0, 2.4, 2.2, 0.12, C.deck)
        m.box(-0.96, 0, 0.12, 0.16, 1.9, 2.25, C.white)
        for y: Float in [-0.87, 0.87] { m.box(0, y, 0.12, 1.8, 0.16, 2.25, C.white) }
        m.box(0.86, 0, 0.12, 0.12, 1.8, 0.75, C.white)
        m.box(0.86, 0, 0.87, 0.08, 1.8, 1.2, C.glass)
        m.box(0.86, 0, 2.07, 0.12, 1.8, 0.30, C.white)
        m.box(0, 0, 2.37, 2.5, 2.3, 0.14, C.green)
        m.box(1.0, 0, 0.87, 0.42, 1.6, 0.10, C.wood)
        m.box(0.938, 0.45, 1.35, 0.06, 0.5, 0.40, C.dark)
        m.box(0.971, 0.45, 1.39, 0.006, 0.42, 0.32, C.warm, glow: true)
        if !far {
            m.box(-0.4, -0.958, 0.12, 0.70, 0.016, 1.92, C.steel)
            m.box(-0.16, -0.98, 0.95, 0.04, 0.028, 0.12, C.dark)
        }
        return m
    }
}
