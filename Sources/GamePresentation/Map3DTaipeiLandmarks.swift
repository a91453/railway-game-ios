import Foundation
import GameCore

// Decision 370 (step 2): Taipei 101 and Taipei Main Station in the model
// look, where they stand. Ported from the preview's `landmarks.py`
// (`taipei101`, `station`, `place`) and its palette (`compose_palettes.py`,
// `PALETTES[1.0]`), in the reference repository's
// `Railway/game-art-previews/docs/art/map3d-mapbox-look-2026-10-23/scripts/`. Not
// the reference meshes: only their measured proportions and their OSM
// placement (`blender-buildings-v1/placement.json`, ODbL) are used; the
// shapes are new parts with new colours and line patterns.

/// Decision 370: the two landmarks, each built in its own metres (x right,
/// y back, z up, its middle at the origin), then stood where it is.
enum Map3DTaipeiLandmark: CaseIterable, Sendable {
    case taipei101, taipeiMainStation

    /// Where the landmark's middle stands (`placement.json`), and how far
    /// it is turned about the up axis, degrees east of north as the
    /// preview's group is.
    var latitude: Double { self == .taipei101 ? 25.033946307135494 : 25.0477174 }
    var longitude: Double { self == .taipei101 ? 121.56455513294843 : 121.51711425 }
    var rotation: Float { self == .taipei101 ? 89 : 169.5 }
    /// Half the length and width of the ground it clears of the city
    /// (`compose_play.py`), and of its body, which the player's track must
    /// keep clear of (the podium and canopy; the station's eaves and
    /// porches).
    var clearing: (x: Float, y: Float) { self == .taipei101 ? (82, 82) : (92, 80) }
    var body: (x: Float, y: Float) { self == .taipei101 ? (68.3, 70.5) : (78.4, 66.8) }

    /// The README's colours (`PALETTES[1.0]`).
    static let palette: [String: UInt32] = [
        "podiumRoof": 0xEDEEF0, "glass": 0xC0DDEE, "glassTop": 0xCCE4F2, "frame": 0xF9F9F7, "podiumGlass": 0xDCEDFC,
        "coin": 0xD7E3EF, "spire": 0xDDE0E5, "ornament": 0xECE2C6, "wall": 0xF5F1E9, "trim": 0xFBF9F4, "roof": 0xE2C4B6,
        "ridge": 0xF3EFE8, "wellWall": 0xF0EBE2, "skylight": 0xD8E2EA, "plinth": 0xE4E2DE, "groundGlass": 0xC9D8E2,
        "soffit": 0xE9E4DB, "stripGlass": 0xD3DEE6, "flatRoof": 0xE6E4E0, "plant": 0xDCDCDA,
    ].mapValues(Map3DColor.rgb)

    /// The model, in full close by, or without its small parts from afar.
    func model(full: Bool) -> LandmarkMesh {
        var mesh = LandmarkMesh(full: full)
        switch self {
        case .taipei101: mesh.taipei101()
        case .taipeiMainStation: mesh.station()
        }
        return mesh
    }
}

/// A landmark's faces in its own metres (x right, y back, z up), each
/// vertex with its u and v in metres for its line pattern.
struct LandmarkMesh {
    typealias P2 = (x: Float, y: Float)
    typealias P3 = (x: Float, y: Float, z: Float)

    /// No small parts when false (the far model).
    let full: Bool
    var vertices: [Map3DVertex] = []
    var indices: [UInt32] = []

    static let curtain = Map3DVertex.curtainGlass, plain = Map3DVertex.plain
    static let tiles = Map3DVertex.roofTiles, floors = Map3DVertex.floorLines

    func colour(_ name: String) -> UInt32 { Map3DTaipeiLandmark.palette[name]! }

    mutating func tri(_ a: P3, _ b: P3, _ c: P3, _ color: UInt32, _ layer: Float, _ uv: [P2]? = nil) {
        let e1 = Map3DPoint(b.x - a.x, b.y - a.y, b.z - a.z), e2 = Map3DPoint(c.x - a.x, c.y - a.y, c.z - a.z)
        guard let n = e1.cross(e2).normalized else { return }
        let uvs = uv ?? [(0, 0), (0, 0), (0, 0)]
        let base = UInt32(vertices.count)
        for (p, t) in zip([a, b, c], uvs) {
            vertices.append(Map3DVertex(Map3DPoint(p.x, p.y, p.z), normal: n, color: color, u: t.x, v: t.y, layer: layer))
        }
        indices += [base, base + 1, base + 2]
    }

    /// `a b c d` counter-clockwise seen from outside.
    mutating func quad(_ a: P3, _ b: P3, _ c: P3, _ d: P3, _ color: UInt32, _ layer: Float, _ uv: [P2]? = nil) {
        let uv = uv ?? [(0, 0), (0, 0), (0, 0), (0, 0)]
        tri(a, b, c, color, layer, [uv[0], uv[1], uv[2]])
        tri(a, c, d, color, layer, [uv[0], uv[2], uv[3]])
    }

    static func distance(_ a: P2, _ b: P2) -> Float { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }

    /// Walls between two closed rings at heights `z0` and `z1`, facing
    /// out; u along the ring and v up, in metres.
    mutating func wallBand(_ ring0: [P2], _ z0: Float, _ ring1: [P2], _ z1: Float, _ color: UInt32, _ layer: Float) {
        band(ring0, Array(repeating: z0, count: ring0.count), ring1, Array(repeating: z1, count: ring1.count), color, layer)
    }

    /// Like ``wallBand``, but each ring point at its own height.
    mutating func band(_ ring0: [P2], _ zs0: [Float], _ ring1: [P2], _ zs1: [Float], _ color: UInt32, _ layer: Float) {
        var u: Float = 0
        for k in ring0.indices {
            let j = (k + 1) % ring0.count
            let a0 = ring0[k], b0 = ring0[j], a1 = ring1[k], b1 = ring1[j]
            let w = Self.distance(a0, b0)
            quad((a0.x, a0.y, zs0[k]), (b0.x, b0.y, zs0[j]), (b1.x, b1.y, zs1[j]), (a1.x, a1.y, zs1[k]), color, layer,
                 [(u, zs0[k]), (u + w, zs0[j]), (u + w, zs1[j]), (u, zs1[k])])
            u += w
        }
    }

    mutating func cap(_ ring: [P2], _ z: Float, _ color: UInt32, _ layer: Float) {
        let n = Float(ring.count)
        let c = (x: ring.reduce(0) { $0 + $1.x } / n, y: ring.reduce(0) { $0 + $1.y } / n)
        for k in ring.indices {
            let a = ring[k], b = ring[(k + 1) % ring.count]
            tri((c.x, c.y, z), (a.x, a.y, z), (b.x, b.y, z), color, layer, [c, a, b])
        }
    }

    mutating func box(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ color: UInt32, _ layer: Float,
                      top: UInt32? = nil) {
        let ring: [P2] = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        wallBand(ring, z0, ring, z1, color, layer)
        cap(ring, z1, top ?? color, Self.plain)
    }

    /// A square of half side `h`, its corners cut by `c` (an octagon),
    /// counter-clockwise from the front (-y) face.
    static func chamfered(_ h: Float, _ c: Float) -> [P2] {
        [(-h + c, -h), (h - c, -h), (h, -h + c), (h, h - c), (h - c, h), (-h + c, h), (-h, h - c), (-h, -h + c)]
    }

    /// A square of half side `h` with each corner stepped in twice (the
    /// tower's double notches), counter-clockwise.
    static func notched(_ h: Float, _ c: Float) -> [P2] {
        let s = c / 2
        let one: [P2] = [(h - c, -h), (h - c, -h + s), (h - s, -h + s), (h - s, -h + c), (h, -h + c)]
        var out: [P2] = []
        for q in 0..<4 {
            let angle = Float(q) * .pi / 2, ca = cos(angle), sa = sin(angle)
            out += one.map { ($0.x * ca - $0.y * sa, $0.x * sa + $0.y * ca) }
        }
        return out
    }

    /// A rectangle's outline, each side cut into `perSide` pieces,
    /// counter-clockwise from the front-left corner; with each point, how
    /// far (0 to 1) it is from the nearest corner along its side.
    static func rectRing(_ hx: Float, _ hy: Float, perSide: Int = 12) -> (points: [P2], near: [Float]) {
        let corners: [P2] = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
        var points: [P2] = [], near: [Float] = []
        for c in 0..<4 {
            let a = corners[c], b = corners[(c + 1) % 4]
            for s in 0..<perSide {
                let t = Float(s) / Float(perSide)
                points.append((a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
                near.append(min(t, 1 - t) * 2)
            }
        }
        return (points, near)
    }

    /// Pilasters `step` apart round a rectangle's walls, standing `depth`
    /// proud, and between them the wall's glass panels.
    mutating func pilasters(_ hx: Float, _ hy: Float, _ z0: Float, _ z1: Float, step: Float, depth: Float, width: Float,
                            _ color: UInt32, panel: UInt32, panelLayer: Float) {
        let corners: [P2] = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
        for c in 0..<4 {
            let a = corners[c], b = corners[(c + 1) % 4]
            let length = Self.distance(a, b)
            let dx = (b.x - a.x) / length, dy = (b.y - a.y) / length
            let ox = dy, oy = -dx
            if full {
                let n = max(1, Int((length / step).rounded()))
                for s in 0...n {
                    let t = Float(s) / Float(n) * length
                    let x = a.x + dx * t, y = a.y + dy * t, w = width / 2
                    let p: [P2] = [(x - dx * w, y - dy * w), (x + dx * w, y + dy * w),
                                   (x + dx * w + ox * depth, y + dy * w + oy * depth), (x - dx * w + ox * depth, y - dy * w + oy * depth)]
                    wallBand(p, z0, p, z1, color, Self.plain)
                }
            }
            quad((a.x, a.y, z0), (b.x, b.y, z0), (b.x, b.y, z1), (a.x, a.y, z1), panel, panelLayer,
                 [(0, z0), (length, z0), (length, z1), (0, z1)])
        }
    }

    /// A notched band whose corner steps are white strips and whose four
    /// main faces are glass.
    mutating func notchedBand(_ h0: Float, _ c0: Float, _ z0: Float, _ h1: Float, _ c1: Float, _ z1: Float,
                              glass: UInt32, white: UInt32, glassLayer: Float) {
        let r0 = Self.notched(h0, c0), r1 = Self.notched(h1, c1)
        for k in r0.indices {
            let j = (k + 1) % r0.count
            let a0 = r0[k], b0 = r0[j], a1 = r1[k], b1 = r1[j]
            let w = Self.distance(a0, b0), main = k % 5 == 4
            quad((a0.x, a0.y, z0), (b0.x, b0.y, z0), (b1.x, b1.y, z1), (a1.x, a1.y, z1), main ? glass : white, main ? glassLayer : Self.plain,
                 [(0, z0), (w, z0), (w, z1), (0, z1)])
        }
    }

    /// Thin boxes (x0, x1, z0, z1, depth) standing proud of the four faces
    /// of a square of half side `half`.
    mutating func faceBoxes(_ half: Float, _ boxes: [(Float, Float, Float, Float, Float)], _ color: UInt32) {
        for q in 0..<4 {
            let angle = Float(q) * .pi / 2, ca = cos(angle), sa = sin(angle)
            func turned(_ x: Float, _ y: Float) -> P2 { (x * ca - y * sa, x * sa + y * ca) }
            for (x0, x1, z0, z1, d) in boxes {
                let ring = [turned(x0, -half - d), turned(x1, -half - d), turned(x1, -half), turned(x0, -half)]
                wallBand(ring, z0, ring, z1, color, Self.plain)
                cap(ring, z1, color, Self.plain)
            }
        }
    }

    // MARK: Taipei 101

    mutating func taipei101() {
        let glass = colour("glass"), white = colour("frame")
        // The podium: glass walls with white floor bands, two terraced
        // roofs, the entrance canopy on the front.
        let outer: [P2] = [(-68.3, -61.8), (68.3, -61.8), (68.3, 61.8), (-68.3, 61.8)]
        for (z0, z1, color, layer) in [(Float(0), Float(1.2), white, Self.plain), (1.2, 6.6, colour("podiumGlass"), Self.curtain),
                                       (6.6, 8.0, white, Self.plain), (8.0, 13.2, colour("podiumGlass"), Self.curtain),
                                       (13.2, 14.5, white, Self.plain)] {
            wallBand(outer, z0, outer, z1, color, layer)
        }
        cap(outer, 14.5, colour("podiumRoof"), Self.plain)
        let inner: [P2] = [(-56, -50), (56, -50), (56, 50), (-56, 50)]
        wallBand(inner, 14.5, inner, 22.5, colour("podiumGlass"), Self.curtain)
        wallBand(inner, 22.5, inner, 24, white, Self.plain)
        cap(inner, 24, colour("podiumRoof"), Self.plain)
        box(-22, -70, 0, 22, -61.8, 9, white, Self.plain, top: white)
        box(-18, -70.5, 0, 18, -69.8, 7.5, glass, Self.curtain)
        // The base tower, 25-90 m, on a short white plinth; white corner
        // strips, and on each face the white frame with stacked bars under
        // the coin.
        wallBand(Self.notched(29.4, 5.2), 24, Self.notched(29.4, 5.2), 26, white, Self.plain)
        notchedBand(28.1, 5, 26, 28.9, 5, 89.4, glass: glass, white: white, glassLayer: Self.floors)
        if full {
            var bars: [(Float, Float, Float, Float, Float)] = [(-9.5, -8.0, 26, 70, 0.5), (8.0, 9.5, 26, 70, 0.5)]
            bars += stride(from: Float(30), to: 70, by: 4).map { (-8.0, 8.0, $0, $0 + 0.9, 0.35) }
            faceBoxes(28.5, bars, white)
            coins(glass: glass)
        }
        // Eight flared modules of 40 m: the glass flares out with white
        // corner strips, and a thick white lip overhangs at the top, its
        // corners turned up a little (the ruyi).
        for k in 0..<8 {
            let z0 = 90 + 40 * Float(k)
            notchedBand(28.6, 5, z0, 36.4, 6.4, z0 + 38.2, glass: glass, white: white, glassLayer: Self.floors)
            let lip0 = Self.notched(37.6, 6.6), lip1 = Self.notched(38.4, 6.8)
            wallBand(Self.notched(36.4, 6.4), z0 + 38.2, lip0, z0 + 38.6, white, Self.plain)
            wallBand(lip0, z0 + 38.6, lip1, z0 + 40.0, white, Self.plain)
            cap(lip1, z0 + 40.0, white, Self.plain)
            guard full else { continue }
            for q in 0..<4 {
                let angle = Float(q) * .pi / 2 + .pi / 4
                let r = 38.4 * Float(2).squareRoot() - 3.2
                let cx = r * cos(angle), cy = r * sin(angle), ux = cos(angle), uy = sin(angle)
                let a: P3 = (cx - uy * 2.0, cy + ux * 2.0, z0 + 39.0)
                let b: P3 = (cx + uy * 2.0, cy - ux * 2.0, z0 + 39.0)
                tri(a, b, (cx + ux * 3.4, cy + uy * 3.4, z0 + 41.4), white, Self.plain)
                tri(b, a, (cx, cy, z0 + 41.0), white, Self.plain)
            }
        }
        // The crown: 410-448 m tapering in two steps, the white lantern,
        // the spire.
        notchedBand(28, 4.6, 410, 24, 4, 427, glass: colour("glassTop"), white: white, glassLayer: Self.floors)
        wallBand(Self.notched(24, 4), 427, Self.notched(26.4, 4.4), 429, white, Self.plain)
        cap(Self.notched(26.4, 4.4), 429, white, Self.plain)
        notchedBand(22, 3.6, 429, 18.3, 3, 445, glass: colour("glassTop"), white: white, glassLayer: Self.floors)
        wallBand(Self.notched(18.3, 3), 445, Self.notched(20.2, 3.3), 448, white, Self.plain)
        cap(Self.notched(20.2, 3.3), 448, white, Self.plain)
        if full {
            for (x0, y0) in [(Float(-13), Float(-13)), (7, -13), (-13, 7), (7, 7)] { box(x0, y0, 448, x0 + 6, y0 + 6, 454, white, Self.plain) }
        }
        wallBand(Self.chamfered(10, 3), 448, Self.chamfered(9, 2.8), 462, white, Self.floors)
        cap(Self.chamfered(9, 2.8), 462, white, Self.plain)
        wallBand(Self.chamfered(6, 2), 462, Self.chamfered(5, 1.7), 468, colour("spire"), Self.plain)
        cap(Self.chamfered(5, 1.7), 468, colour("spire"), Self.plain)
        wallBand(Self.chamfered(1.6, 0.5), 468, Self.chamfered(0.35, 0.1), 508, colour("spire"), Self.plain)
        if full {
            for z in [Float(476), 486, 495] {
                let r = 1.6 - (z - 468) / 40 * 1.25 + 0.5
                wallBand(Self.chamfered(r, r * 0.3), z, Self.chamfered(r, r * 0.3), z + 1.2, white, Self.plain)
                cap(Self.chamfered(r, r * 0.3), z + 1.2, white, Self.plain)
            }
        }
    }

    /// The four coins at 74-86 m: a ring with a square hole, slightly
    /// proud of each face.
    mutating func coins(glass: UInt32) {
        for q in 0..<4 {
            let angle = Float(q) * .pi / 2, ca = cos(angle), sa = sin(angle)
            let y: Float = -28.9 - 0.8
            func at(_ x: Float, _ z: Float, _ d: Float = 0) -> P3 {
                let yy = y - d
                return (x * ca - yy * sa, x * sa + yy * ca, z)
            }
            let segments = 28
            for s in 0..<segments {
                let t0 = 2 * Float.pi * Float(s) / Float(segments), t1 = 2 * Float.pi * Float(s + 1) / Float(segments)
                for (r0, r1, color) in [(Float(6.2), Float(7.2), colour("ornament")), (2.2, 6.2, colour("coin"))] {
                    quad(at(r1 * cos(t0), 80 + r1 * sin(t0)), at(r1 * cos(t1), 80 + r1 * sin(t1)),
                         at(r0 * cos(t1), 80 + r0 * sin(t1)), at(r0 * cos(t0), 80 + r0 * sin(t0)), color, Self.plain)
                }
                let a = at(7.2 * cos(t0), 80 + 7.2 * sin(t0)), b = at(7.2 * cos(t1), 80 + 7.2 * sin(t1))
                let a2 = at(7.2 * cos(t0), 80 + 7.2 * sin(t0), -0.8), b2 = at(7.2 * cos(t1), 80 + 7.2 * sin(t1), -0.8)
                quad(a2, b2, b, a, colour("ornament"), Self.plain)
            }
            quad(at(-2.2, 77.8, -0.05), at(2.2, 77.8, -0.05), at(2.2, 82.2, -0.05), at(-2.2, 82.2, -0.05), glass, Self.plain)
        }
    }

    // MARK: Taipei Main Station

    mutating func station() {
        let hx: Float = 72.8, hy: Float = 57.8
        // A grey plinth, the ground storey's glass behind square columns.
        box(-hx - 2, -hy - 2, 0, hx + 2, hy + 2, 0.8, colour("plinth"), Self.plain, top: colour("plinth"))
        let gx = hx - 2.5, gy = hy - 2.5
        let ground: [P2] = [(-gx, -gy), (gx, -gy), (gx, gy), (-gx, gy)]
        wallBand(ground, 0.8, ground, 9, colour("groundGlass"), Self.curtain)
        if full {
            let sides: [(P2, P2)] = [((-hx, -hy), (hx, -hy)), ((hx, -hy), (hx, hy)), ((hx, hy), (-hx, hy)), ((-hx, hy), (-hx, -hy))]
            for (a, b) in sides {
                let n = Int((Self.distance(a, b) / 7.2).rounded())
                for s in 0...n {
                    let x = a.x + (b.x - a.x) * Float(s) / Float(n), y = a.y + (b.y - a.y) * Float(s) / Float(n)
                    box(x - 0.9, y - 0.9, 0.8, x + 0.9, y + 0.9, 9, colour("wall"), Self.plain)
                }
            }
        }
        // The entrance porches at the middle of the long faces.
        for sign in [Float(-1), 1] {
            let y0 = sign * hy, y1 = sign * (hy + 9)
            box(-16, min(y0, y1), 0.8, 16, max(y0, y1), 7.5, colour("groundGlass"), Self.curtain, top: colour("wall"))
            box(-18, min(y0, y1) - (sign < 0 ? 0.6 : 0), 7.5, 18, max(y0, y1) + (sign > 0 ? 0.6 : 0), 9, colour("trim"), Self.plain,
                top: colour("trim"))
            if full {
                for x in [Float(-16.5), -5.5, 5.5, 16.5] {
                    let yy = sign * (hy + 8.4)
                    box(x - 0.6, yy - 0.6, 0.8, x + 0.6, yy + 0.6, 7.5, colour("wall"), Self.plain)
                }
            }
        }
        // The lower eave: a tiled skirt round the building over the
        // colonnade, its corners turned up a little.
        let (ringIn, nearIn) = Self.rectRing(hx, hy)
        let ringOut = ringIn.map { (x: $0.x * (hx + 4.2) / hx, y: $0.y * (hy + 4.2) / hy) }
        let up = nearIn.map { n -> Float in let t = 1 - min(n, 0.25) / 0.25; return 0.9 * t * t }
        band(ringOut, up.map { 8.6 + $0 }, ringIn, up.map { _ in 11.4 }, colour("roof"), Self.tiles)
        band(ringOut, up.map { 8.1 + $0 }, ringOut, up.map { 8.6 + $0 }, colour("trim"), Self.plain)
        band(ringIn, up.map { _ in 8.1 }, ringOut, up.map { 8.1 + $0 }, colour("soffit"), Self.plain)
        // The upper walls: cream pilasters every 3.6 m, pale glass strips.
        let ux = hx - 1.2, uy = hy - 1.2
        cap([(-ux, -uy), (ux, -uy), (ux, uy), (-ux, uy)], 11.4, colour("wall"), Self.plain)
        pilasters(ux, uy, 11.4, 25.6, step: 3.6, depth: 0.7, width: 1.3, colour("wall"), panel: colour("stripGlass"), panelLayer: Self.curtain)
        let belt: [P2] = [(-ux - 0.3, -uy - 0.3), (ux + 0.3, -uy - 0.3), (ux + 0.3, uy + 0.3), (-ux - 0.3, uy + 0.3)]
        wallBand(belt, 17.8, belt, 18.4, colour("wall"), Self.plain)
        // The cornice: a white band and a bracket course.
        box(-ux - 0.9, -uy - 0.9, 25.6, ux + 0.9, uy + 0.9, 27.4, colour("trim"), Self.plain)
        box(-ux - 2.2, -uy - 2.2, 27.4, ux + 2.2, uy + 2.2, 28.6, colour("soffit"), Self.plain)
        // The great roof: from eaves 5 m out, concave, the corners swept
        // up, to the ridge round the flat middle.
        let ex = hx + 5.6, ey = hy + 5.6, rx: Float = 46.5, ry: Float = 29.5
        let steps = full ? 12 : 6
        let (unit, near) = Self.rectRing(1, 1, perSide: 16)
        var rings: [(points: [P2], heights: [Float])] = []
        for s in 0...steps {
            let t = Float(s) / Float(steps)
            let sx = ex - (ex - rx) * t, sy = ey - (ey - ry) * t
            let sweep = 1.8 * (1 - t) * (1 - t) * (1 - t)
            let heights = near.map { n -> Float in
                let corner = 1 - min(n, 0.3) / 0.3
                return 28.6 + 13.4 * powf(t, 1.7) + sweep * corner * corner
            }
            rings.append((unit.map { (x: $0.x * sx, y: $0.y * sy) }, heights))
        }
        for s in 0..<steps { band(rings[s].points, rings[s].heights, rings[s + 1].points, rings[s + 1].heights, colour("roof"), Self.tiles) }
        // The eave's edge, white, and its underside.
        let eave = rings[0]
        band(eave.points, eave.heights.map { $0 - 0.9 }, eave.points, eave.heights, colour("trim"), Self.plain)
        band(eave.points.map { (x: $0.x * (ux + 2.2) / ex, y: $0.y * (uy + 2.2) / ey) }, eave.heights.map { _ in 28.6 },
             eave.points, eave.heights.map { $0 - 0.9 }, colour("soffit"), Self.plain)
        // Four hip ridges and the ridge round the middle, with end
        // ornaments.
        if full {
            for k in [0, 16, 32, 48] {
                for s in 0..<steps {
                    let a = rings[s].points[k], b = rings[s + 1].points[k]
                    let za = rings[s].heights[k], zb = rings[s + 1].heights[k]
                    let d = Self.distance(a, b)
                    let nx = -(b.y - a.y) / d * 0.55, ny = (b.x - a.x) / d * 0.55
                    quad((a.x - nx, a.y - ny, za + 0.6), (a.x + nx, a.y + ny, za + 0.6),
                         (b.x + nx, b.y + ny, zb + 0.6), (b.x - nx, b.y - ny, zb + 0.6), colour("ridge"), Self.plain)
                }
                let a = rings[0].points[k], z = rings[0].heights[k]
                box(a.x - 0.8, a.y - 0.8, z, a.x + 0.8, a.y + 0.8, z + 1.6, colour("ridge"), Self.plain)
            }
        }
        let top = rings[steps].points, ztop = rings[steps].heights[0]
        let ridge = top.map { (x: $0.x * (rx + 1.2) / rx, y: $0.y * (ry + 1.2) / ry) }
        band(ridge, top.map { _ in ztop - 0.3 }, ridge, top.map { _ in ztop + 1.4 }, colour("ridge"), Self.plain)
        band(ridge, top.map { _ in ztop + 1.4 }, top, top.map { _ in ztop + 1.4 }, colour("ridge"), Self.plain)
        // The flat middle a little below the ridge, with a skylight and
        // plant.
        let well = Array(top.reversed())
        band(well, well.map { _ in ztop - 2.2 }, well, well.map { _ in ztop + 1.4 }, colour("wellWall"), Self.plain)
        cap([(-rx, -ry), (rx, -ry), (rx, ry), (-rx, ry)], ztop - 2.2, colour("flatRoof"), Self.plain)
        box(-24, -8, ztop - 2.2, 24, 8, ztop - 0.6, colour("skylight"), Self.curtain, top: colour("skylight"))
        if full {
            for (x, y) in [(Float(-36), Float(-18)), (-30, 18), (33, -17), (36, 17)] {
                box(x - 3, y - 2, ztop - 2.2, x + 3, y + 2, ztop - 0.4, colour("plant"), Self.plain)
            }
        }
    }

    /// The model stood in the scene (x east, y up, z south) with its
    /// middle on `origin` and its foot `ground` high, turned `rotation`
    /// degrees about the up axis as the preview's `place` does.
    func placed(origin: Map3DPoint, ground: Float, rotation: Float) -> Map3DMesh {
        let r = rotation * .pi / 180, c = cos(r), s = sin(r)
        return Map3DMesh(vertices: vertices.map { v in
            let e = v.x * c - v.y * s, n = v.x * s + v.y * c
            let ne = v.nx * c - v.ny * s, nn = v.nx * s + v.ny * c
            return Map3DVertex(Map3DPoint(e + origin.x, v.z + ground, -n + origin.z), normal: Map3DPoint(ne, v.nz, -nn),
                               color: v.color, u: v.u, v: v.v, layer: v.layer)
        }, indices: indices)
    }

    /// The scene points of the rectangle of half sides `x` and `y` round
    /// the model's middle, stood as ``placed(origin:ground:rotation:)``.
    static func corners(_ half: (x: Float, y: Float), origin: Map3DPoint, rotation: Float) -> [Map3DPoint] {
        let r = rotation * .pi / 180, c = cos(r), s = sin(r)
        return [(-half.x, -half.y), (half.x, -half.y), (half.x, half.y), (-half.x, half.y)].map { p in
            Map3DPoint(p.0 * c - p.1 * s + origin.x, 0, -(p.0 * s + p.1 * c) + origin.z)
        }
    }
}

extension Map3DScene.Builder {
    /// Decision 370: Taipei 101 and Taipei Main Station where they stand,
    /// when the scene holds their middle and neither the player's track
    /// nor a platform runs within their body: in full close by, without
    /// their small parts from afar. Returns those built, each with the
    /// 64 m cells of the ground it clears, which keep no city lot or real
    /// building.
    mutating func addTaipeiLandmarks(frame: RealWorldFrame) -> [Map3DTaipeiLandmark: Set<Map3DScene.ChunkKey>] {
        var built: [Map3DTaipeiLandmark: Set<Map3DScene.ChunkKey>] = [:]
        for landmark in Map3DTaipeiLandmark.allCases {
            let place = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
            guard contains(x: place.x, y: place.y) else { continue }
            let centre = point(x: place.x, y: place.y, height: 0)
            let body = LandmarkMesh.corners(landmark.body, origin: centre, rotation: landmark.rotation)
            guard isClearOfTrack(body) else { continue }
            let clearing = LandmarkMesh.corners(landmark.clearing, origin: centre, rotation: landmark.rotation)
            let ground = body.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0
            let saved = target
            for (level, full) in [(Target.near, true), (.far, false)] {
                target = level
                let mesh = landmark.model(full: full).placed(origin: centre, ground: ground, rotation: landmark.rotation)
                keptColours.formUnion(mesh.vertices.map(\.color))
                self.mesh(at: centre) { $0.append(mesh) }
            }
            target = saved
            built[landmark] = cells(under: clearing)
        }
        return built
    }

    /// Whether no track comes within 4 m of the rectangle `outline` (its
    /// corners in turn), nor any platform within a metre: as
    /// ``isClear(_:facing:)``, but over the real roads the landmark stands
    /// beside, and over tunnels (the real station's tracks run under it).
    func isClearOfTrack(_ outline: [Map3DPoint]) -> Bool {
        let middle = outline.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * 0.25
        let along = outline[1] - outline[0], across = outline[2] - outline[1]
        guard let facing = along.normalized, let side = across.normalized else { return false }
        let length = along.length / 2, width = across.length / 2
        func near(_ p: Map3DPoint, _ margin: Float) -> Bool {
            let d = p - middle
            return abs(d.dot(facing)) < length + margin && abs(d.dot(side)) < width + margin
        }
        if trackLines.contains(where: { $0.kind != .tunnel && $0.points.contains { near($0, 4) } }) { return false }
        return !laidPlatforms.contains { platform in
            platform.structure != .tunnel && platform.line.contains { near($0, abs(platform.offset) + platform.width / 2 + 1) }
        }
    }
}
