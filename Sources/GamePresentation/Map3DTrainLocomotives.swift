import Foundation

/// Decision 318: the locomotives of the hauled sets, each in its own
/// livery and shape, from the reference's E201 (`Simulator/…/tra-e201.glb`:
/// the two-tone body, the roof's grilles, insulators and pantographs, the
/// three-axle bogies, the yellow pilot) and its garage models
/// (`garage-blender-v1/*.json`: colours, pantographs, axles, side grilles,
/// the cab's kind). Rebuilt here from boxes and beams in the game's flat
/// colours, at a car's size, not their vertices.
///
/// The mesh space is the scene kit's: +x front, +y up, +z left, metres;
/// the head lamps glow at the front only.
enum Map3DTrainLocomotive: Sendable {
    case e200, e500, r100, r200, r135, e1000
    /// Decision 286, later (fourth): the CT273 steam locomotive's black
    /// and gold (the reference's garage `ct273`) on the hood unit, until
    /// there is a steam locomotive's shape.
    case ct273

    var model: Map3DModelPack.Model {
        var b = SceneKitBuilder()
        switch self {
        case .e200: b.e200()
        case .e500: b.e500()
        case .r100: b.hoodUnit(body: 0xDF753B, stripe: 0xEAE6D3, rail: 0xEAE6D3, chevron: false, fans: 2)
        case .r200: b.r200()
        case .r135: b.hoodUnit(body: 0x232E48, stripe: 0xEEEDE4, rail: 0xEEEDE4, chevron: true, fans: 2)
        case .e1000: b.e1000()
        case .ct273: b.hoodUnit(body: 0x262D2B, stripe: 0xBCAB74, rail: 0xBCAB74, chevron: false, fans: 0)
        }
        return .flat(named: "\(self)", from: b.mesh)
    }
}

extension SceneKitBuilder {
    fileprivate static let half: Float = 8.2
    fileprivate static let roofTop: Float = 3.9
    fileprivate static let pilotYellow = Map3DColor.rgb(0xF0A41C)
    fileprivate static let graphite = Map3DColor.rgb(0x2A2F33)
    fileprivate static let porcelain = Map3DColor.rgb(0x63797C)

    // MARK: The locomotives

    /// E200 (E201): ivory above, TRA orange below with an orange line in
    /// the ivory, a cab at each end, roof grilles between two pantographs.
    fileprivate mutating func e200() {
        let orange = Map3DColor.rgb(0xE57939), ivory = Map3DColor.rgb(0xE8DFB9)
        running(axles: 3)
        // The GE cab: nearly upright, its windscreen raked a little, the
        // ivory coming down the nose's upper half.
        let nose = Nose(rake: 0.3, chamfer: 0.3, split: 2.75, lower: orange, upper: ivory)
        body(lower: orange, upper: ivory, split: 2.75, line: orange, front: nose.depth, back: nose.depth)
        roof(Map3DTrainStyle.roofColour)
        for end: Float in [1, -1] {
            boxCab(end: end, nose: nose, lit: end > 0)
            // The ivory V on the orange of each face.
            for z: Float in [-1, 1] {
                beam(Map3DPoint(end * (Self.half + 0.03), 2.65, z * 1.25), Map3DPoint(end * (Self.half + 0.03), 1.95, 0),
                     thickness: 0.12, color: ivory)
            }
        }
        sideGrilles(count: 6, from: -4.6, to: 4.6, y: 2.95, height: 0.6, colour: Map3DColor.shaded(ivory, 0.55))
        roofGrilles(from: -3, to: 3)
        pantographs(at: [-5.2, 5.2])
    }

    /// E500: orange all over, a row of dark grilles along each side, the
    /// pantographs at the ends.
    fileprivate mutating func e500() {
        let orange = Map3DColor.rgb(0xF07532), dark = Map3DColor.rgb(0x333F42)
        running(axles: 3)
        // The Toshiba cab: a raked windscreen wrapping round wide corners.
        let nose = Nose(rake: 0.6, chamfer: 0.45, split: 2.2, lower: orange, upper: orange)
        body(lower: orange, upper: orange, split: 2.6, line: nil, front: nose.depth, back: nose.depth)
        roof(Map3DTrainStyle.roofColour)
        for end: Float in [1, -1] { boxCab(end: end, nose: nose, lit: end > 0) }
        sideGrilles(count: 8, from: -5, to: 5, y: 2.1, height: 1.35, colour: dark)
        roofGrilles(from: -2.6, to: 2.6)
        pantographs(at: [-5.4, 5.4])
    }

    /// R200: white, one cab, a wide dark grille band along the engine
    /// room, three radiator fans on the roof.
    fileprivate mutating func r200() {
        let white = Map3DColor.rgb(0xEBEDEA), dark = Map3DColor.rgb(0x283944)
        running(axles: 3)
        // The Stadler cab: the most raked, a big windscreen.
        let nose = Nose(rake: 0.85, chamfer: 0.5, split: 2.0, lower: white, upper: white)
        body(lower: white, upper: white, split: 2.6, line: nil, front: nose.depth, back: 0)
        roof(white)
        boxCab(end: 1, nose: nose, lit: true)
        closedEnd(end: -1, body: white)
        box(-1.2, 1.75, 0, 10.4, 2.84, 1.6, dark)
        sideGrilles(count: 7, from: -5.8, to: 3.4, y: 1.85, height: 1.4, colour: Map3DColor.shaded(dark, 0.7))
        fans(at: [-4.6, -1.9, 0.8], colour: Map3DColor.shaded(white, 0.6))
    }

    /// E1000 power car: white, the nose and a band of grilles orange, one
    /// pantograph; its back is the gangway to the coaches.
    fileprivate mutating func e1000() {
        let white = Map3DColor.rgb(0xD8DDDB), orange = Map3DColor.rgb(0xE66D2F)
        running(axles: 2)
        // The power car's orange nose: raked, its corners rounded off.
        let nose = Nose(rake: 0.7, chamfer: 0.6, split: 2.1, lower: orange, upper: orange)
        body(lower: white, upper: white, split: 2.6, line: nil, front: nose.depth, back: 0)
        roof(Map3DTrainStyle.roofColour)
        box(Self.half - nose.depth - 0.5, 1.08, 0, 1.0, 2.82, Self.roofTop - 1.08, orange)
        boxCab(end: 1, nose: nose, lit: true)
        closedEnd(end: -1, body: white)
        box(-1.5, 1.9, 0, 9.4, 2.82, 1.3, orange)
        sideGrilles(count: 7, from: -5.6, to: 2.6, y: 2.0, height: 1.1, colour: Map3DColor.shaded(orange, 0.6))
        roofGrilles(from: -4, to: 0)
        pantographs(at: [2.6])
    }

    /// A hood unit (R100, R135): a long hood, the cab near the front, a
    /// short nose, a walkway with handrails round it.
    fileprivate mutating func hoodUnit(body colour: UInt32, stripe: UInt32, rail: UInt32, chevron: Bool, fans count: Int) {
        let body = Map3DColor.rgb(colour), line = Map3DColor.rgb(stripe), handrail = Map3DColor.rgb(rail)
        running(axles: 3)
        box(0, 1.2, 0, 2 * Self.half - 0.2, 2.9, 0.14, Self.graphite)
        // The long hood, the cab and the short nose.
        box(-2.5, 1.34, 0, 10.8, 2.2, 2.0, body)
        box(4.4, 1.34, 0, 3.0, 2.8, Self.roofTop - 1.34, body)
        box(6.95, 1.34, 0, 2.1, 2.1, 1.25, body)
        box(-2.5, 1.62, 0, 10.82, 2.22, 0.12, line)
        box(4.4, Self.roofTop - 0.05, 0, 3.1, 2.84, 0.12, Map3DTrainStyle.roofColour)
        box(-2.5, 3.34, 0, 10.6, 2.0, 0.08, Map3DColor.shaded(body, 0.8))
        // The cab's windows, all round.
        box(4.4, 2.7, 0, 2.2, 2.84, 0.85, Map3DTrainStyle.glass)
        box(4.4, 2.7, 0, 3.04, 2.0, 0.85, Map3DTrainStyle.glass)
        // The hood's louvres and fans.
        sideGrilles(count: 5, from: -6.8, to: 1.4, y: 1.9, height: 1.15, colour: Map3DColor.shaded(body, 0.6), width: 2.24)
        for x: Float in stride(from: -6.4, through: -6.4 + Float(count - 1) * 2.6, by: 2.6) {
            cylinder(x, 3.34, 0, radius: 0.55, height: 0.1, color: Map3DColor.shaded(body, 0.55), sides: 10)
        }
        // Handrails along the walkway.
        for z: Float in [-1.4, 1.4] {
            beam(Map3DPoint(-7.9, 2.25, z), Map3DPoint(2.8, 2.25, z), thickness: 0.06, color: handrail)
            beam(Map3DPoint(6.0, 2.25, z), Map3DPoint(7.95, 2.25, z), thickness: 0.06, color: handrail)
            for x: Float in [-7.9, -4.3, -0.7, 2.8, 6.0, 7.95] {
                beam(Map3DPoint(x, 1.34, z), Map3DPoint(x, 2.25, z), thickness: 0.06, color: handrail)
            }
        }
        // The nose: lamps, and on the R135 its yellow and black V.
        let face: Float = 8.0
        for z: Float in [-0.6, 0.6] {
            let start = mesh.vertices.count
            box(face + 0.05, 2.15, z, 0.12, 0.26, 0.2, Map3DTrainStyle.headlamp)
            mesh.makeGlowing(from: start)
        }
        if chevron {
            box(face + 0.02, 1.4, 0, 0.06, 2.0, 0.6, Self.pilotYellow)
            for z: Float in [-1, 1] {
                beam(Map3DPoint(face + 0.07, 2.0, z * 0.95), Map3DPoint(face + 0.07, 1.42, 0), thickness: 0.12, color: Self.graphite)
            }
        }
        pilot(end: 1, chevron: true)
        pilot(end: -1, chevron: true)
        for z: Float in [-0.9, 0.9] { box(-Self.half + 0.05, 1.7, z, 0.1, 0.22, 0.2, Map3DTrainStyle.roofColour) }
    }

    // MARK: Parts

    /// The underframe and two bogies of `axles` wheel pairs.
    fileprivate mutating func running(axles: Int) {
        box(0, 0.95, 0, 2 * Self.half - 0.3, 2.6, 0.27, Self.graphite)
        box(0, 0.75, 0, 5.0, 1.8, 0.2, Self.graphite)
        let spacing: Float = 1.9
        for centre: Float in [-5.0, 5.0] {
            for z: Float in [-1.2, 1.2] {
                box(centre, 0.35, z, spacing * Float(axles - 1) + 1.3, 0.16, 0.6, Map3DTrainStyle.under)
                for i in 0..<axles {
                    wheel(centre + (Float(i) - Float(axles - 1) / 2) * spacing, 0.5, z, radius: 0.48, width: 0.2)
                }
            }
        }
    }

    /// The body from the underframe to the roof: `lower` below `split`,
    /// `upper` above, and a thin `line` along the join.
    /// `front` and `back` leave room for a cab's nose at that end.
    fileprivate mutating func body(lower: UInt32, upper: UInt32, split: Float, line: UInt32?, front: Float, back: Float) {
        let from = -Self.half + max(back, 0.05), to = Self.half - max(front, 0.05)
        let length = to - from, x = (from + to) / 2
        box(x, 1.08, 0, length, 2.8, split - 1.08, lower)
        box(x, split, 0, length, 2.8, Self.roofTop - split, upper)
        if let line { box(x, split + 0.18, 0, length + 0.02, 2.82, 0.08, line) }
    }

    fileprivate mutating func roof(_ colour: UInt32) {
        box(0, Self.roofTop, 0, 2 * Self.half - 0.5, 2.5, 0.08, colour)
    }

    /// A box cab's nose: upright below `split`, its windscreen raked back
    /// `rake` metres from there to the roof, the corners cut `chamfer` in
    /// from the sides.
    struct Nose {
        var rake: Float
        var chamfer: Float
        var split: Float
        var lower: UInt32
        var upper: UInt32
        /// How far it stands out from the body's end.
        var depth: Float { rake + chamfer + 0.15 }
    }

    /// A box cab at `end` (+1 front, −1 back): its nose, windscreen and
    /// side windows, the lamps (lit at the front) and the pilot.
    fileprivate mutating func boxCab(end: Float, nose: Nose, lit: Bool) {
        let face = end * Self.half, half: Float = 1.4
        let bottom: Float = 1.08, top = Self.roofTop
        // The plan outline at height `y`: from the body's end round the
        // cut corners to the nose's front, which moves back above `split`.
        func ring(_ y: Float) -> [Map3DPoint] {
            let back = y <= nose.split ? 0 : nose.rake * (y - nose.split) / (top - nose.split)
            let front = face - end * back, root = face - end * nose.depth
            let corner = front - end * nose.chamfer
            return [Map3DPoint(root, y, -half), Map3DPoint(corner, y, -half), Map3DPoint(front, y, -half + nose.chamfer),
                    Map3DPoint(front, y, half - nose.chamfer), Map3DPoint(corner, y, half), Map3DPoint(root, y, half)]
        }
        let rings = [ring(bottom), ring(nose.split), ring(top)]
        let centre = Map3DPoint(face - end * nose.depth / 2, (bottom + top) / 2, 0)
        func facet(_ points: [Map3DPoint], _ colour: UInt32) {
            let middle = points.reduce(Map3DPoint.zero, +) * (1 / Float(points.count))
            let normal = (points[1] - points[0]).cross(points[2] - points[0])
            mesh.addFacet(normal.dot(middle - centre) < 0 ? points.reversed() : points, color: colour)
        }
        for (level, colour) in [(0, nose.lower), (1, nose.upper)] {
            let a = rings[level], b = rings[level + 1]
            for i in 0..<5 { facet([a[i], a[i + 1], b[i + 1], b[i]], colour) }
        }
        facet(rings[0], Map3DColor.shaded(nose.lower, 0.7))
        facet(rings[2], Map3DTrainStyle.roofColour)
        // The windscreen across the raked front and round its corners, a
        // hair proud of it.
        let low = rings[1], high = rings[2]
        func pane(_ i: Int, inset: Float) {
            func at(_ u: Float, _ v: Float) -> Map3DPoint {
                let a = low[i] + (low[i + 1] - low[i]) * u, b = high[i] + (high[i + 1] - high[i]) * u
                return a + (b - a) * v
            }
            let points = [at(inset, 0.18), at(1 - inset, 0.18), at(1 - inset, 0.8), at(inset, 0.8)]
            guard let normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized else { return }
            let middle = points.reduce(Map3DPoint.zero, +) * 0.25
            let out = normal.dot(middle - centre) < 0 ? normal * -1 : normal
            facet(points.map { $0 + out * 0.02 }, Map3DTrainStyle.glass)
        }
        pane(2, inset: 0.06)
        pane(1, inset: 0.12)
        pane(3, inset: 0.12)
        box(face - end * (nose.depth + 0.7), 2.6, 0, 0.8, 2.84, 0.8, Map3DTrainStyle.glass)
        for z: Float in [-0.85, 0.85] {
            let start = mesh.vertices.count
            box(face + end * 0.05, 1.6, z, 0.1, 0.28, 0.2, lit ? Map3DTrainStyle.headlamp : Map3DTrainStyle.roofColour)
            if lit { mesh.makeGlowing(from: start) }
        }
        pilot(end: end, chevron: false)
    }

    /// A plain end with the gangway door, where the coaches couple on.
    fileprivate mutating func closedEnd(end: Float, body: UInt32) {
        let face = end * Self.half
        box(face + end * 0.02, 1.2, 0, 0.06, 1.0, 2.2, Map3DTrainStyle.doorColour)
        box(face + end * 0.03, 2.4, 0, 0.04, 0.6, 0.8, Map3DTrainStyle.glass)
        pilot(end: end, chevron: false)
    }

    /// The pilot under an end: yellow, with black stripes on a hood unit.
    fileprivate mutating func pilot(end: Float, chevron: Bool) {
        let face = end * Self.half
        box(face + end * 0.15, 0.4, 0, 0.3, 2.3, 0.55, Self.pilotYellow)
        if chevron {
            for z: Float in [-0.7, 0, 0.7] {
                box(face + end * 0.31, 0.4, z, 0.04, 0.22, 0.55, Self.graphite)
            }
        }
        box(face + end * 0.35, 0.95, 0, 0.3, 0.3, 0.25, Self.graphite)
    }

    /// `count` louvred panels between `from` and `to` on both sides.
    fileprivate mutating func sideGrilles(count: Int, from: Float, to: Float, y: Float, height: Float, colour: UInt32,
                                          width: Float = 2.84) {
        let pitch = (to - from) / Float(count), panel = pitch * 0.78
        for i in 0..<count {
            let x = from + pitch * (Float(i) + 0.5)
            box(x, y, 0, panel, width, height, colour)
            for slat in 1..<4 {
                box(x, y + height * Float(slat) / 4, 0, panel, width + 0.02, 0.05, Map3DColor.shaded(colour, 0.6))
            }
        }
    }

    /// The roof's grilles over the machine room.
    fileprivate mutating func roofGrilles(from: Float, to: Float) {
        let count = 3, pitch = (to - from) / Float(count)
        for i in 0..<count {
            let x = from + pitch * (Float(i) + 0.5)
            box(x, Self.roofTop + 0.08, 0, pitch * 0.85, 1.7, 0.1, Self.graphite)
        }
    }

    /// Radiator fans on the roof.
    fileprivate mutating func fans(at xs: [Float], colour: UInt32) {
        for x in xs {
            cylinder(x, Self.roofTop + 0.08, 0, radius: 0.6, height: 0.08, color: colour, sides: 10)
            box(x, Self.roofTop + 0.16, 0, 1.0, 0.1, 0.03, Self.graphite)
        }
    }

    /// Lowered pantographs at `xs` on their insulators, joined by the roof
    /// line (the E201's).
    fileprivate mutating func pantographs(at xs: [Float]) {
        let top = Self.roofTop + 0.08
        for x in xs {
            for dx: Float in [-0.6, 0.6] {
                for z: Float in [-0.55, 0.55] {
                    cylinder(x + dx, top, z, radius: 0.09, height: 0.22, color: Self.porcelain, sides: 6)
                }
            }
            box(x, top + 0.22, 0, 1.5, 1.3, 0.06, Self.graphite)
            let side: Float = x > 0 ? -1 : 1
            for z: Float in [-0.45, 0.45] {
                beam(Map3DPoint(x - side * 0.6, top + 0.28, z), Map3DPoint(x + side * 0.5, top + 0.46, z * 0.4),
                     thickness: 0.06, color: Self.graphite)
            }
            beam(Map3DPoint(x + side * 0.5, top + 0.46, 0), Map3DPoint(x - side * 0.4, top + 0.55, 0), thickness: 0.06,
                 color: Self.graphite)
            box(x - side * 0.4, top + 0.52, 0, 0.14, 1.9, 0.06, Self.graphite)
        }
        if let first = xs.min(), let last = xs.max(), last > first {
            beam(Map3DPoint(first, top + 0.3, 0.9), Map3DPoint(last, top + 0.3, 0.9), thickness: 0.05, color: Self.porcelain)
        }
    }
}
