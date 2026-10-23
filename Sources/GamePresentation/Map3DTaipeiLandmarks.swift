import Foundation
import GameCore

// Decision 370 (step 2): Taipei 101 and Taipei Main Station in the model
// look, where they stand. Their plans and heights are OpenStreetMap's
// (ODbL; read from osmtoday's Taiwan extract of 2026-10-23, the same data
// Overture's release 2026-10-21.0 carries for them): 101's building
// relation 11551064 and its parts, the station's way 23641610. The
// details the map does not hold (the eight flared modules, the coins, the
// station's eaves and pilasters) and the colours and line patterns come
// from the preview's `landmarks.py` and `compose_palettes.py`
// (`PALETTES[1.0]`), in the reference repository's
// `Railway/game-art-previews/docs/art/map3d-mapbox-look-2026-10-23/scripts/`.

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
    var body: (x: Float, y: Float) { self == .taipei101 ? (65.4, 69.2) : (78.4, 66.8) }

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

    /// Where the tower stands on the podium, from OSM's tower part
    /// (way 198637969): not in its middle, the mall wraps it on two sides.
    static let towerAt: P2 = (-30.4, -26.2)

    mutating func taipei101() {
        let glass = colour("glass"), white = colour("frame"), podium = colour("podiumGlass")
        // The mall (OSM way 64566862, 30 m, six storeys) round two sides
        // of the tower: glass with white floor bands, its roof in four
        // rectangles, and on it the atrium's glass vault (way 615183624,
        // 30-42 m).
        let mall: [P2] = [(-54.5, 30.3), (-17.8, 30.3), (-17.8, 0.6), (-3.4, 0.6), (-3.4, -14.0), (26.3, -14.0),
                          (26.3, -50.8), (65.4, -50.8), (65.4, 69.2), (-54.5, 69.2)]
        for (z0, z1, color, layer) in [(Float(0), Float(1.2), white, Self.plain), (1.2, 9.4, podium, Self.curtain),
                                       (9.4, 10.6, white, Self.plain), (10.6, 18.8, podium, Self.curtain),
                                       (18.8, 20.0, white, Self.plain), (20.0, 28.6, podium, Self.curtain),
                                       (28.6, 30.0, white, Self.plain)] {
            wallBand(mall, z0, mall, z1, color, layer)
        }
        for (x0, y0, x1, y1) in [(Float(-54.5), Float(30.3), Float(65.4), Float(69.2)), (-17.8, 0.6, 65.4, 30.3),
                                 (-3.4, -14.0, 65.4, 0.6), (26.3, -50.8, 65.4, -14.0)] {
            cap([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], 30, colour("podiumRoof"), Self.plain)
        }
        vault(from: (-3.0, 12.5), to: (52.5, 49.0), halfWidth: 7.5, z0: 30, z1: 42, colour("skylight"))
        // The low block under the tower (ways 1159328963 and 1159328964,
        // 25 m), the entrance canopy on its front.
        box(-62.6, -58.4, 0, 1.8, 2.6, 1.2, white, Self.plain)
        box(-62.6, -58.4, 1.2, 1.8, 2.6, 23.6, podium, Self.curtain)
        box(-62.6, -58.4, 23.6, 1.8, 2.6, 25, white, Self.plain, top: colour("podiumRoof"))
        box(-42, -66, 0, -18, -58.4, 9, white, Self.plain, top: white)
        box(-38, -66.5, 0, -22, -65.8, 7.5, glass, Self.curtain)
        let start = vertices.count
        // The base tower, 25-98 m, tapering a little; white corner strips,
        // and on each face the white frame with stacked bars under the
        // coin. Its plan is OSM's: 54 m square, each corner stepped in
        // twice (5.4 m).
        notchedBand(26.6, 5.4, 25, 26.0, 5.2, 98, glass: glass, white: white, glassLayer: Self.floors)
        if full {
            var bars: [(Float, Float, Float, Float, Float)] = [(-9.5, -8.0, 25, 78, 0.5), (8.0, 9.5, 25, 78, 0.5)]
            bars += stride(from: Float(30), to: 78, by: 4).map { (-8.0, 8.0, $0, $0 + 0.9, 0.35) }
            faceBoxes(26.3, bars, white)
            coins(glass: glass, face: 26.15, z: 88)
        }
        // Eight flared modules of eight storeys, 98-386 m (OSM: the 89th
        // floor's roof at 386 m): the glass flares out with white corner
        // strips, and a white lip overhangs at the top as wide as OSM's
        // plan, its corners turned up a little (the ruyi).
        for k in 0..<8 {
            let z0 = 98 + 36 * Float(k)
            notchedBand(23.6, 4.8, z0, 26.2, 5.3, z0 + 34.4, glass: glass, white: white, glassLayer: Self.floors)
            // A white waist round the module's foot.
            wallBand(Self.notched(23.9, 4.85), z0, Self.notched(24.1, 4.9), z0 + 1.4, white, Self.plain)
            cap(Self.notched(24.1, 4.9), z0 + 1.4, white, Self.plain)
            let lip0 = Self.notched(26.8, 5.4), lip1 = Self.notched(27.2, 5.5)
            wallBand(Self.notched(26.2, 5.3), z0 + 34.4, lip0, z0 + 34.8, white, Self.plain)
            wallBand(lip0, z0 + 34.8, lip1, z0 + 36.0, white, Self.plain)
            cap(lip1, z0 + 36.0, white, Self.plain)
            guard full else { continue }
            // Two white strips up each corner's steps, flaring with it.
            let foot = Self.notched(23.6, 4.8), head = Self.notched(26.2, 5.3)
            for k in foot.indices where k % 5 == 1 || k % 5 == 3 {
                fin(from: foot[k], z0 + 1.4, to: head[k], z0 + 34.4, width: 0.5, depth: 0.5, white)
            }
            for q in 0..<4 {
                let angle = Float(q) * .pi / 2 + .pi / 4
                let r = 27.2 * Float(2).squareRoot() - 2.4
                let cx = r * cos(angle), cy = r * sin(angle), ux = cos(angle), uy = sin(angle)
                let a: P3 = (cx - uy * 1.5, cy + ux * 1.5, z0 + 35.2)
                let b: P3 = (cx + uy * 1.5, cy - ux * 1.5, z0 + 35.2)
                tri(a, b, (cx + ux * 2.6, cy + uy * 2.6, z0 + 37.0), white, Self.plain)
                tri(b, a, (cx, cy, z0 + 36.8), white, Self.plain)
            }
        }
        // The crown over the eighth module: a white platform a little wider
        // than its lip at the 89th floor's roof, its edge toothed; on it a
        // small glass box at each corner round a low middle stage; the top
        // floors (OSM: 90th-101st, 390.6-439 m) as one more module, much
        // narrower, flaring out to a white lip; the white stepped base of
        // the spire to the roof at 448 m; the spire to 508 m (OSM way
        // 615183623).
        let deck = Self.notched(28.0, 5.6)
        wallBand(deck, 386, deck, 388.4, white, Self.plain)
        cap(deck, 388.4, white, Self.plain)
        if full {
            for k in deck.indices {
                let a = deck[k], b = deck[(k + 1) % deck.count], length = Self.distance(a, b)
                let ox = (b.y - a.y) / length, oy = -(b.x - a.x) / length
                let teeth = max(1, Int((length / 3.2).rounded()))
                for t in 0..<teeth {
                    let s0 = Float(t) / Float(teeth), s1 = Float(t + 1) / Float(teeth), sm = (s0 + s1) / 2
                    func at(_ s: Float, _ out: Float) -> P3 { (a.x + (b.x - a.x) * s + ox * out, a.y + (b.y - a.y) * s + oy * out, 387.2) }
                    tri(at(s0, 0), at(s1, 0), at(sm, 1.1), white, Self.plain)
                    tri(at(s1, 0), at(s0, 0), at(sm, 1.1), white, Self.plain)
                }
            }
            for (x, y) in [(Float(-19.5), Float(-19.5)), (19.5, -19.5), (19.5, 19.5), (-19.5, 19.5)] {
                box(x - 3.2, y - 3.2, 388.4, x + 3.2, y + 3.2, 394.4, colour("glassTop"), Self.curtain, top: white)
                box(x - 3.6, y - 3.6, 394.4, x + 3.6, y + 3.6, 395.2, white, Self.plain)
            }
        }
        wallBand(Self.notched(17.0, 3.0), 388.4, Self.notched(17.0, 3.0), 391.0, white, Self.plain)
        cap(Self.notched(17.0, 3.0), 391.0, white, Self.plain)
        notchedBand(13.4, 2.6, 391.0, 17.6, 3.4, 430.6, glass: colour("glassTop"), white: white, glassLayer: Self.floors)
        wallBand(Self.notched(13.6, 2.6), 391.0, Self.notched(13.8, 2.65), 392.2, white, Self.plain)
        wallBand(Self.notched(17.6, 3.4), 430.6, Self.notched(18.6, 3.6), 431.2, white, Self.plain)
        wallBand(Self.notched(18.6, 3.6), 431.2, Self.notched(18.9, 3.7), 433.0, white, Self.plain)
        cap(Self.notched(18.9, 3.7), 433.0, white, Self.plain)
        if full {
            let foot = Self.notched(13.4, 2.6), head = Self.notched(17.6, 3.4)
            for k in foot.indices where k % 5 == 2 {
                fin(from: foot[k], 392.2, to: head[k], 430.6, width: 0.4, depth: 0.4, white)
            }
        }
        for (z0, z1, h, c) in [(Float(433), Float(438), Float(12.0), Float(3.0)), (438, 443, 9.0, 2.4), (443, 448, 6.2, 1.8)] {
            wallBand(Self.chamfered(h, c), z0, Self.chamfered(h, c), z1, white, Self.plain)
            cap(Self.chamfered(h, c), z1, white, Self.plain)
        }
        wallBand(Self.chamfered(3.2, 1.0), 448, Self.chamfered(2.6, 0.8), 456, white, Self.plain)
        cap(Self.chamfered(2.6, 0.8), 456, white, Self.plain)
        wallBand(Self.chamfered(1.3, 0.4), 456, Self.chamfered(0.22, 0.07), 508, white, Self.plain)
        if full {
            for z in [Float(466), 478, 490] {
                let r = 1.3 - (z - 456) / 52 * 1.08 + 0.35
                wallBand(Self.chamfered(r, r * 0.3), z, Self.chamfered(r, r * 0.3), z + 0.9, white, Self.plain)
                cap(Self.chamfered(r, r * 0.3), z + 0.9, white, Self.plain)
            }
        }
        shift(from: start, by: Self.towerAt)
    }

    /// Moves the vertices from `start` on by `by` across the ground.
    mutating func shift(from start: Int, by d: P2) {
        for k in start..<vertices.count {
            let v = vertices[k]
            vertices[k] = Map3DVertex(Map3DPoint(v.x + d.x, v.y + d.y, v.z), normal: Map3DPoint(v.nx, v.ny, v.nz),
                                      color: v.color, u: v.u, v: v.v, layer: v.layer)
        }
    }

    /// A white strip `width` wide standing `depth` proud along the
    /// diagonal from the point `a` at `za` to `b` at `zb`, as a tower's
    /// corner strips run up its steps.
    mutating func fin(from a: P2, _ za: Float, to b: P2, _ zb: Float, width: Float, depth: Float, _ color: UInt32) {
        func ring(_ p: P2) -> [P2] {
            let r = (p.x * p.x + p.y * p.y).squareRoot(), ux = p.x / r, uy = p.y / r, w = width / 2
            return [(p.x - uy * w, p.y + ux * w), (p.x + uy * w, p.y - ux * w),
                    (p.x + uy * w + ux * depth, p.y - ux * w + uy * depth), (p.x - uy * w + ux * depth, p.y + ux * w + uy * depth)]
        }
        let ra = ring(a), rb = ring(b)
        for k in 0..<4 {
            let j = (k + 1) % 4
            quad((ra[k].x, ra[k].y, za), (ra[j].x, ra[j].y, za), (rb[j].x, rb[j].y, zb), (rb[k].x, rb[k].y, zb), color, Self.plain)
        }
    }

    /// A glass vault from `a` to `b` on a roof `z0` high, `halfWidth`
    /// across at its middle, narrowing to its ends, its crest `z1` high.
    mutating func vault(from a: P2, to b: P2, halfWidth: Float, z0: Float, z1: Float, _ color: UInt32) {
        let length = Self.distance(a, b), dx = (b.x - a.x) / length, dy = (b.y - a.y) / length
        let along = full ? 12 : 6, across = full ? 8 : 4
        func at(_ i: Int, _ j: Int) -> P3 {
            let s = Float(i) / Float(along), t = Float(j) / Float(across) * 2 - 1
            let w = halfWidth * (1 - (2 * s - 1) * (2 * s - 1)).squareRoot()
            let x = a.x + dx * length * s - dy * w * t, y = a.y + dy * length * s + dx * w * t
            return (x, y, z0 + (z1 - z0) * (1 - t * t) * (w / halfWidth).squareRoot())
        }
        for i in 0..<along {
            for j in 0..<across {
                quad(at(i, j), at(i + 1, j), at(i + 1, j + 1), at(i, j + 1), color, Self.curtain,
                     [(Float(i) * length / Float(along), Float(j)), (Float(i + 1) * length / Float(along), Float(j)),
                      (Float(i + 1) * length / Float(along), Float(j + 1)), (Float(i) * length / Float(along), Float(j + 1))])
            }
        }
    }

    /// The four coins on the base tower's faces, `face` from its middle,
    /// centred `z` high: a ring with a square hole, slightly proud.
    mutating func coins(glass: UInt32, face: Float, z zc: Float) {
        for q in 0..<4 {
            let angle = Float(q) * .pi / 2, ca = cos(angle), sa = sin(angle)
            let y: Float = -face - 0.8
            func at(_ x: Float, _ z: Float, _ d: Float = 0) -> P3 {
                let yy = y - d
                return (x * ca - yy * sa, x * sa + yy * ca, z)
            }
            let segments = 28
            for s in 0..<segments {
                let t0 = 2 * Float.pi * Float(s) / Float(segments), t1 = 2 * Float.pi * Float(s + 1) / Float(segments)
                for (r0, r1, color) in [(Float(6.2), Float(7.2), colour("ornament")), (2.2, 6.2, colour("coin"))] {
                    quad(at(r1 * cos(t0), zc + r1 * sin(t0)), at(r1 * cos(t1), zc + r1 * sin(t1)),
                         at(r0 * cos(t1), zc + r0 * sin(t1)), at(r0 * cos(t0), zc + r0 * sin(t0)), color, Self.plain)
                }
                let a = at(7.2 * cos(t0), zc + 7.2 * sin(t0)), b = at(7.2 * cos(t1), zc + 7.2 * sin(t1))
                let a2 = at(7.2 * cos(t0), zc + 7.2 * sin(t0), -0.8), b2 = at(7.2 * cos(t1), zc + 7.2 * sin(t1), -0.8)
                quad(a2, b2, b, a, colour("ornament"), Self.plain)
            }
            quad(at(-2.2, zc - 2.2, -0.05), at(2.2, zc - 2.2, -0.05), at(2.2, zc + 2.2, -0.05), at(-2.2, zc + 2.2, -0.05), glass, Self.plain)
        }
    }

    // MARK: Taipei Main Station

    mutating func station() {
        let hx: Float = 72.8, hy: Float = 57.8
        // A grey plinth; an arcade round all four sides, square stone
        // columns on the outer line and the ground storey's glass 4.5 m
        // behind them.
        box(-hx - 2, -hy - 2, 0, hx + 2, hy + 2, 0.8, colour("plinth"), Self.plain, top: colour("plinth"))
        let gx = hx - 4.5, gy = hy - 4.5
        let ground: [P2] = [(-gx, -gy), (gx, -gy), (gx, gy), (-gx, gy)]
        wallBand(ground, 0.8, ground, 9, colour("groundGlass"), Self.curtain)
        let outer: [P2] = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
        band(ground, [Float](repeating: 8.1, count: 4), outer, [Float](repeating: 8.1, count: 4), colour("soffit"), Self.plain)
        if full {
            let sides: [(P2, P2)] = [((-hx, -hy), (hx, -hy)), ((hx, -hy), (hx, hy)), ((hx, hy), (-hx, hy)), ((-hx, hy), (-hx, -hy))]
            for (a, b) in sides {
                let n = Int((Self.distance(a, b) / 7.2).rounded())
                for s in 0...n {
                    let x = a.x + (b.x - a.x) * Float(s) / Float(n), y = a.y + (b.y - a.y) * Float(s) / Float(n)
                    box(x - 0.8, y - 0.8, 0.8, x + 0.8, y + 0.8, 8.1, colour("wall"), Self.plain)
                }
            }
        }
        // The gates where OSM's entrance nodes are (x is west, y south):
        // 北1／北3 and 南1／南3 at x ±44, 東1／東3 and 西1／西3 at y ±28.6,
        // 東2 and 西2 in the middle of the short faces; each a white
        // canopy over the arcade between two wider piers.
        var gates: [(at: P2, along: P2, out: P2)] = []
        for x in [Float(-44), 44] { gates += [((x, -hy), (1, 0), (0, -1)), ((x, hy), (1, 0), (0, 1))] }
        for y in [Float(-28.6), 0, 28.6] { gates += [((-hx, y), (0, 1), (-1, 0)), ((hx, y), (0, 1), (1, 0))] }
        for g in gates {
            func at(_ a: Float, _ o: Float) -> P2 { (g.at.x + g.along.x * a + g.out.x * o, g.at.y + g.along.y * a + g.out.y * o) }
            let c0 = at(-6.5, -0.4), c1 = at(6.5, 2.6)
            box(min(c0.x, c1.x), min(c0.y, c1.y), 6.4, max(c0.x, c1.x), max(c0.y, c1.y), 7.3, colour("trim"), Self.plain, top: colour("trim"))
            if full {
                for a in [Float(-5.6), 5.6] {
                    let p = at(a, 0.2)
                    box(p.x - 1.1, p.y - 1.1, 0.8, p.x + 1.1, p.y + 1.1, 8.1, colour("wall"), Self.plain)
                }
            }
        }
        // The main entrances, 北2 and 南2, stand out from the middle of the
        // long faces: glass behind columns under a tiled hip roof that
        // meets the lower eave.
        for sign in [Float(-1), 1] {
            let y0 = sign * hy, y1 = sign * (hy + 9), yf = sign * (hy + 10.2)
            box(-12, min(y0, y1), 0.8, 12, max(y0, y1), 7.4, colour("groundGlass"), Self.curtain, top: colour("wall"))
            box(-13.6, min(y0, yf), 7.4, 13.6, max(y0, yf), 9.0, colour("trim"), Self.plain, top: colour("trim"))
            let front0: P3 = (-14.4, sign * (hy + 11.0), 8.8), front1: P3 = (14.4, sign * (hy + 11.0), 8.8)
            let back0: P3 = (-10.0, y0, 11.6), back1: P3 = (10.0, y0, 11.6)
            let foot0: P3 = (-14.4, y0, 8.8), foot1: P3 = (14.4, y0, 8.8)
            if sign < 0 {
                quad(front0, front1, back1, back0, colour("roof"), Self.tiles, [(0, 0), (28.8, 0), (24.4, 11.4), (4.4, 11.4)])
                tri(foot0, front0, back0, colour("roof"), Self.tiles)
                tri(front1, foot1, back1, colour("roof"), Self.tiles)
            } else {
                quad(front1, front0, back0, back1, colour("roof"), Self.tiles, [(0, 0), (28.8, 0), (24.4, 11.4), (4.4, 11.4)])
                tri(front0, foot0, back0, colour("roof"), Self.tiles)
                tri(foot1, front1, back1, colour("roof"), Self.tiles)
            }
            if full {
                for x in [Float(-12.5), -4.2, 4.2, 12.5] {
                    let yy = sign * (hy + 9.4)
                    box(x - 0.7, yy - 0.7, 0.8, x + 0.7, yy + 0.7, 7.4, colour("wall"), Self.plain)
                }
            }
        }
        // The lower eave: a tiled skirt round the building over the
        // arcade, its corners turned up.
        let (ringIn, nearIn) = Self.rectRing(hx, hy)
        let ringOut = ringIn.map { (x: $0.x * (hx + 4.2) / hx, y: $0.y * (hy + 4.2) / hy) }
        let up = nearIn.map { n -> Float in let t = 1 - min(n, 0.25) / 0.25; return 1.4 * t * t }
        band(ringOut, up.map { 8.6 + $0 }, ringIn, up.map { _ in 11.4 }, colour("roof"), Self.tiles)
        band(ringOut, up.map { 8.1 + $0 }, ringOut, up.map { 8.6 + $0 }, colour("trim"), Self.plain)
        band(ringIn, up.map { _ in 8.1 }, ringOut, up.map { 8.1 + $0 }, colour("soffit"), Self.plain)
        // The upper walls: cream pilasters every 3.6 m, pale glass strips;
        // to 18 m, so that the roof's top stands 30 m high (OSM way
        // 23641610: 30 m, its roof from the lower eave 18 m high).
        let ux = hx - 1.2, uy = hy - 1.2
        cap([(-ux, -uy), (ux, -uy), (ux, uy), (-ux, uy)], 11.4, colour("wall"), Self.plain)
        // Plaster between the pilasters, and above the belt a band of
        // square windows all the way round, which the pilasters divide.
        pilasters(ux, uy, 11.4, 18.0, step: 3.6, depth: 0.7, width: 1.3, colour("wall"), panel: colour("wall"), panelLayer: Self.floors)
        let windows: [P2] = [(-ux - 0.08, -uy - 0.08), (ux + 0.08, -uy - 0.08), (ux + 0.08, uy + 0.08), (-ux - 0.08, uy + 0.08)]
        wallBand(windows, 15.4, windows, 17.5, colour("stripGlass"), Self.curtain)
        let belt: [P2] = [(-ux - 0.3, -uy - 0.3), (ux + 0.3, -uy - 0.3), (ux + 0.3, uy + 0.3), (-ux - 0.3, uy + 0.3)]
        wallBand(belt, 14.4, belt, 15.0, colour("wall"), Self.plain)
        // The cornice: a white band and a bracket course.
        box(-ux - 0.9, -uy - 0.9, 18.0, ux + 0.9, uy + 0.9, 19.4, colour("trim"), Self.plain)
        box(-ux - 2.2, -uy - 2.2, 19.4, ux + 2.2, uy + 2.2, 20.2, colour("soffit"), Self.plain)
        // The great roof: from eaves 5 m out, concave, the corners swept
        // up, to the ridge round the flat middle.
        let ex = hx + 5.6, ey = hy + 5.6, rx: Float = 46.5, ry: Float = 29.5
        let steps = full ? 12 : 6
        let (unit, near) = Self.rectRing(1, 1, perSide: 16)
        var rings: [(points: [P2], heights: [Float])] = []
        for s in 0...steps {
            let t = Float(s) / Float(steps)
            let sx = ex - (ex - rx) * t, sy = ey - (ey - ry) * t
            let sweep = 2.6 * (1 - t) * (1 - t) * (1 - t)
            let heights = near.map { n -> Float in
                let corner = 1 - min(n, 0.3) / 0.3
                return 20.2 + 7.6 * powf(t, 1.7) + sweep * corner * corner
            }
            rings.append((unit.map { (x: $0.x * sx, y: $0.y * sy) }, heights))
        }
        for s in 0..<steps { band(rings[s].points, rings[s].heights, rings[s + 1].points, rings[s + 1].heights, colour("roof"), Self.tiles) }
        // The eave's edge, white, and its underside.
        let eave = rings[0]
        band(eave.points, eave.heights.map { $0 - 0.9 }, eave.points, eave.heights, colour("trim"), Self.plain)
        band(eave.points.map { (x: $0.x * (ux + 2.2) / ex, y: $0.y * (uy + 2.2) / ey) }, eave.heights.map { _ in 20.2 },
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
        band(ridge, top.map { _ in ztop - 0.3 }, ridge, top.map { _ in ztop + 1.0 }, colour("ridge"), Self.plain)
        band(ridge, top.map { _ in ztop + 1.0 }, top, top.map { _ in ztop + 1.0 }, colour("ridge"), Self.plain)
        // The flat middle a little below the ridge, with a skylight and
        // plant.
        let well = Array(top.reversed())
        band(well, well.map { _ in ztop - 2.2 }, well, well.map { _ in ztop + 1.0 }, colour("wellWall"), Self.plain)
        cap([(-rx, -ry), (rx, -ry), (rx, ry), (-rx, ry)], ztop - 2.2, colour("flatRoof"), Self.plain)
        // The hall's skylight: a long glass gable over the middle.
        let sz = ztop - 2.2, sh: Float = 2.4
        box(-29, -11, sz, 29, 11, sz + 0.6, colour("trim"), Self.plain, top: colour("trim"))
        quad((-28, -10, sz + 0.6), (28, -10, sz + 0.6), (28, 0, sz + 0.6 + sh), (-28, 0, sz + 0.6 + sh), colour("skylight"), Self.curtain,
             [(0, 0), (56, 0), (56, 10.3), (0, 10.3)])
        quad((28, 10, sz + 0.6), (-28, 10, sz + 0.6), (-28, 0, sz + 0.6 + sh), (28, 0, sz + 0.6 + sh), colour("skylight"), Self.curtain,
             [(0, 0), (56, 0), (56, 10.3), (0, 10.3)])
        tri((-28, 10, sz + 0.6), (-28, -10, sz + 0.6), (-28, 0, sz + 0.6 + sh), colour("skylight"), Self.curtain)
        tri((28, -10, sz + 0.6), (28, 10, sz + 0.6), (28, 0, sz + 0.6 + sh), colour("skylight"), Self.curtain)
        // Ornaments where the ridge turns, their tops the roof's 30 m.
        for (x, y) in [(-rx - 1.2, -ry - 1.2), (rx + 1.2, -ry - 1.2), (rx + 1.2, ry + 1.2), (-rx - 1.2, ry + 1.2)] {
            box(x - 1.0, y - 1.0, ztop + 1.0, x + 1.0, y + 1.0, ztop + 1.6, colour("ridge"), Self.plain)
            box(x - 1.4, y - 0.5, ztop + 1.6, x + 1.4, y + 0.5, ztop + 2.2, colour("ridge"), Self.plain)
        }
        if full {
            box(-28.4, -0.35, sz + 0.6 + sh - 0.2, 28.4, 0.35, sz + 0.6 + sh + 0.3, colour("trim"), Self.plain)
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
