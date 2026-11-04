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

/// Decision 370, 431, 457, 548, 550, 581: the landmarks, each built in its own metres (x right,
/// y back, z up, its middle at the origin), then stood where it is.
enum Map3DTaipeiLandmark: CaseIterable, Sendable {
    case taipei101, taipeiMainStation, kaohsiungMainStation, kaohsiung85SkyTower, shinKongLifeTower, changhuaRoundhouse
    // Decision 457: central Taipei's palace-style landmarks and old gates.
    case chiangKaiShekMemorialHall, libertySquareGate, nationalTheater, nationalConcertHall, presidentialOffice, ximenRedHouse
    case sunYatSenMemorialHall, grandHotel, northGate, eastGate, southGate, smallSouthGate

    /// Where the landmark's middle stands (`placement.json`), and how far
    /// it is turned about the up axis, degrees east of north as the
    /// preview's group is.
    var latitude: Double {
        switch self {
        case .taipei101: 25.033946307135494
        case .taipeiMainStation: 25.0477174
        case .kaohsiungMainStation: 22.6394462
        case .kaohsiung85SkyTower: 22.611616109117193
        case .shinKongLifeTower: 25.04598631427511
        case .changhuaRoundhouse: 24.0858608
        case .chiangKaiShekMemorialHall: 25.0346856
        case .libertySquareGate: 25.0366529
        case .nationalTheater: 25.0353161
        case .nationalConcertHall: 25.0369989
        case .presidentialOffice: 25.0399911
        case .ximenRedHouse: 25.0420801
        case .sunYatSenMemorialHall: 25.0400042
        case .grandHotel: 25.0785629
        case .northGate: 25.0477291
        case .eastGate: 25.0390241
        case .southGate: 25.0351268
        case .smallSouthGate: 25.0369095
        }
    }
    var longitude: Double {
        switch self {
        case .taipei101: 121.56455513294843
        case .taipeiMainStation: 121.51711425
        case .kaohsiungMainStation: 120.3025654
        case .kaohsiung85SkyTower: 120.3001601108381
        case .shinKongLifeTower: 121.51531117744537
        case .changhuaRoundhouse: 120.5401168
        case .chiangKaiShekMemorialHall: 121.5217163
        case .libertySquareGate: 121.5177174
        case .nationalTheater: 121.5182223
        case .nationalConcertHall: 121.5192192
        case .presidentialOffice: 121.5119850
        case .ximenRedHouse: 121.5065053
        case .sunYatSenMemorialHall: 121.5602918
        case .grandHotel: 121.5262637
        case .northGate: 121.5112235
        case .eastGate: 121.5176769
        case .southGate: 121.5150213
        case .smallSouthGate: 121.5080853
        }
    }
    var rotation: Float {
        switch self {
        case .taipei101: 89
        case .taipeiMainStation: 169.5
        case .kaohsiungMainStation: 0
        case .kaohsiung85SkyTower: 108.5
        case .shinKongLifeTower: 90.5
        case .changhuaRoundhouse: 0
        case .chiangKaiShekMemorialHall: 242
        case .libertySquareGate: 242
        case .nationalTheater: 152
        case .nationalConcertHall: 332
        case .presidentialOffice: 84
        case .ximenRedHouse: 165
        case .sunYatSenMemorialHall: 358
        case .grandHotel: 338
        case .northGate: 165
        case .eastGate: 75
        case .southGate: 352
        case .smallSouthGate: 335
        }
    }
    /// Half the length and width of the ground it clears of the city
    /// (`compose_play.py`), and of its body, which the player's track must
    /// keep clear of (the podium and canopy; the station's eaves and
    /// porches).
    var clearing: (x: Float, y: Float) {
        switch self {
        case .taipei101: (82, 82)
        case .taipeiMainStation: (92, 80)
        case .kaohsiungMainStation: (336, 170)
        case .kaohsiung85SkyTower: (78, 40)
        case .shinKongLifeTower: (48, 25)
        case .changhuaRoundhouse: (48, 30)
        case .chiangKaiShekMemorialHall: (66, 76)
        case .libertySquareGate: (39.5, 10.5)
        case .nationalTheater: (55, 52.5)
        case .nationalConcertHall: (52.5, 52.5)
        case .presidentialOffice: (67, 47.5)
        case .ximenRedHouse: (47.5, 25.5)
        case .sunYatSenMemorialHall: (56, 57.5)
        case .grandHotel: (57.5, 39)
        case .northGate: (8.1, 6.2)
        case .eastGate: (9.4, 7.3)
        case .southGate: (17.4, 10.3)
        case .smallSouthGate: (7.3, 6.8)
        }
    }
    var body: (x: Float, y: Float) {
        switch self {
        case .taipei101: (65.4, 69.2)
        case .taipeiMainStation: (78.4, 66.8)
        case .kaohsiungMainStation: (162, 142)
        case .kaohsiung85SkyTower: (71.5, 34.1)
        case .shinKongLifeTower: (42.5, 20.2)
        case .changhuaRoundhouse: (43, 25.5)
        case .chiangKaiShekMemorialHall: (62.2, 73.8)
        case .libertySquareGate: (37.4, 8.5)
        case .nationalTheater: (54, 51.7)
        case .nationalConcertHall: (51.5, 51.7)
        case .presidentialOffice: (65.9, 46.5)
        case .ximenRedHouse: (45.8, 23.9)
        case .sunYatSenMemorialHall: (54.4, 56.3)
        case .grandHotel: (55, 38.5)
        case .northGate: (7.6, 5.7)
        case .eastGate: (8.9, 6.8)
        case .southGate: (16.9, 9.8)
        case .smallSouthGate: (6.8, 6.3)
        }
    }

    /// The README's colours (`PALETTES[1.0]`), and Decision 431's pale
    /// canopy greens and Imperial Crown slate roof in the same look.
    static let palette: [String: UInt32] = [
        "podiumRoof": 0xEDEEF0, "glass": 0xC0DDEE, "glassTop": 0xCCE4F2, "frame": 0xF9F9F7, "podiumGlass": 0xDCEDFC,
        "coin": 0xD7E3EF, "spire": 0xDDE0E5, "ornament": 0xE9D6A6, "wall": 0xF5F1E9, "trim": 0xFBF9F4, "roof": 0xE2C4B6,
        "ridge": 0xF3EFE8, "wellWall": 0xF0EBE2, "skylight": 0xD8E2EA, "plinth": 0xE4E2DE, "groundGlass": 0xC9D8E2,
        "soffit": 0xE9E4DB, "stripGlass": 0xD3DEE6, "flatRoof": 0xE6E4E0, "plant": 0xDCDCDA,
        "canopyGrass": 0xCFE0C8, "canopyLawn": 0xDCE8D6, "crownRoof": 0xC6CFD6,
        // Decision 457: marble and blue tile, gold tile and red columns,
        // brick and slate, gate stone, in the same pale look.
        "stone": 0xF1EFEA, "hallWhite": 0xF8F7F3, "blueTile": 0x9DB4D6, "blueRidge": 0x86A0C6, "opening": 0xADAAA6,
        "finial": 0xE6C47A, "vermilion": 0xDC968A, "goldTile": 0xEACB80, "goldRidge": 0xD9B76C, "hallWall": 0xF0E8DD,
        "brick": 0xDDA996, "brickTrim": 0xF6F3EC, "slate": 0xAEB5BD, "cream": 0xF2EAD8,
        "column": 0xB5B6B2, "gateStone": 0xD9D2C6, "greenRidge": 0x98C4AE, "hallRed": 0xE8B9AE, "bracket": 0x70A09A, "doorway": 0x5E676D,
        // Each hall's parts keep their order of light to dark: roof, wall,
        // columns, brackets (the memorial hall: wall, roof, doorway).
        "hallColumn": 0xD08A7E, "hallGlass": 0xC0CBCC, "podium": 0xE0D8CA,
        // Decision 457 (later): Taipei Main Station's tiles a deeper
        // orange-brown, between the reference models' and the pale look.
        "stationRoof": 0xDDB19C,
    ].mapValues(Map3DColor.rgb)

    /// The model, in full close by, or without its small parts from afar.
    func model(full: Bool) -> LandmarkMesh {
        var mesh = LandmarkMesh(full: full)
        switch self {
        case .taipei101: mesh.taipei101()
        case .taipeiMainStation: mesh.station()
        case .kaohsiungMainStation: mesh.kaohsiungMainStation()
        case .kaohsiung85SkyTower: mesh.kaohsiung85SkyTower()
        case .shinKongLifeTower: mesh.shinKongLifeTower()
        case .changhuaRoundhouse: mesh.changhuaRoundhouse()
        case .chiangKaiShekMemorialHall: mesh.chiangKaiShekMemorialHall()
        case .libertySquareGate: mesh.libertySquareGate()
        case .nationalTheater: mesh.performingArtsHall(53.95, 48.65, kind: .hipped)
        case .nationalConcertHall: mesh.performingArtsHall(51.45, 48.65, kind: .hipGable)
        case .presidentialOffice: mesh.presidentialOffice()
        case .ximenRedHouse: mesh.ximenRedHouse()
        case .sunYatSenMemorialHall: mesh.sunYatSenMemorialHall()
        case .grandHotel: mesh.grandHotel()
        case .northGate: mesh.cityGate(7.55, 5.7, base: 7, top: 15.2, closed: true, double: false)
        case .eastGate: mesh.cityGate(8.85, 6.75, base: 7, top: 16.5, closed: false, double: true)
        case .southGate: mesh.cityGate(16.9, 9.8, base: 7.5, top: 19, closed: false, double: true)
        case .smallSouthGate: mesh.cityGate(6.75, 6.25, base: 6.5, top: 14.5, closed: false, double: false)
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

    mutating func cap(_ ring: [P2], _ z: Float, _ color: UInt32, _ layer: Float = Self.plain) {
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
            let v0 = glassLayer == Map3DVertex.towerGlass ? z0 - z1 : z0, v1 = glassLayer == Map3DVertex.towerGlass ? 0 : z1
            quad((a0.x, a0.y, z0), (b0.x, b0.y, z0), (b1.x, b1.y, z1), (a1.x, a1.y, z1), main ? glass : white, main ? glassLayer : Self.plain,
                 [(0, v0), (w, v0), (w, v1), (0, v1)])
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
        // Decision 457 (later): the canopy as OSM's roof part (way
        // 1339487734).
        box(-36.8, -69.1, 0, -24.4, -58.4, 9, white, Self.plain, top: white)
        box(-35.6, -69.6, 0, -25.6, -69.0, 7.5, glass, Self.curtain)
        let start = vertices.count
        // The base tower, 25-98 m, tapering a little; white corner strips,
        // and on each face the white frame with stacked bars under the
        // coin. Its plan is OSM's: 54 m square, each corner stepped in
        // twice (5.4 m).
        notchedBand(26.6, 5.4, 25, 26.0, 5.2, 98, glass: glass, white: white, glassLayer: Map3DVertex.towerGlass)
        if full {
            // The frame as wide as the coin and OSM's parts on the faces'
            // middles (ways 1339487718-1339487721: 14.4 m).
            var bars: [(Float, Float, Float, Float, Float)] = [(-7.2, -5.8, 25, 78, 0.5), (5.8, 7.2, 25, 78, 0.5)]
            bars += stride(from: Float(30), to: 78, by: 4).map { (-5.8, 5.8, $0, $0 + 0.9, 0.35) }
            faceBoxes(26.3, bars, white)
            coins(glass: glass, face: 26.15, z: 88)
        }
        // Eight flared modules of eight storeys, 98-386 m (OSM: the 89th
        // floor's roof at 386 m): the glass flares out with white corner
        // strips, and a white lip overhangs at the top as wide as OSM's
        // plan, its corners turned up a little (the ruyi).
        for k in 0..<8 {
            let z0 = 98 + 36 * Float(k)
            // Each section leans out 7° from foot to top (tan 7° × 34.4 m
            // = 4.2 m), so its foot sits well inside the lip below it.
            notchedBand(22.0, 4.5, z0, 26.2, 5.3, z0 + 34.4, glass: glass, white: white, glassLayer: Map3DVertex.towerGlass)
            // A white waist round the module's foot.
            wallBand(Self.notched(22.3, 4.55), z0, Self.notched(22.5, 4.6), z0 + 1.4, white, Self.plain)
            cap(Self.notched(22.5, 4.6), z0 + 1.4, white, Self.plain)
            let lip0 = Self.notched(26.8, 5.4), lip1 = Self.notched(27.2, 5.5)
            wallBand(Self.notched(26.2, 5.3), z0 + 34.4, lip0, z0 + 34.8, white, Map3DVertex.floodlit)
            wallBand(lip0, z0 + 34.8, lip1, z0 + 36.0, white, Map3DVertex.floodlit)
            cap(lip1, z0 + 36.0, white, Self.plain)
            // White strips up each corner's steps, flaring with it and lit
            // after dark: two close by, one from afar.
            let foot = Self.notched(22.0, 4.5), head = Self.notched(26.2, 5.3)
            for k in foot.indices where k % 5 == 1 || (full && k % 5 == 3) {
                fin(from: foot[k], z0 + 1.4, to: head[k], z0 + 34.4, width: 0.5, depth: 0.5, white)
            }
            guard full else { continue }
            // A ruyi on each corner under the lip, 8 m tall (the tower's
            // ruyi stand at least 8 m), facing out.
            for k in head.indices where k % 5 == 2 {
                ruyi(at: head[k], z: z0 + 26.6, height: 8, colour("ornament"))
            }
        }
        // The crown over the eighth module: a white platform a little wider
        // than its lip at the 89th floor's roof, its edge toothed; on it a
        // small glass box at each corner round a low middle stage; the top
        // floors (OSM: 90th-101st, 390.6-439 m) as one more module, much
        // narrower, flaring out to a white lip; the white stepped base of
        // the spire to the roof at 448 m; the spire to 508 m (OSM way
        // 615183623).
        // OSM's parts (ways 615183621, 1339487717, 615183622, 615184269):
        // the deck 49 m across, the top floors 21.5 m at their foot and 30 m
        // at their lip, the crown 21.5 then 14.3 m.
        let deck = Self.notched(24.5, 4.9)
        wallBand(deck, 386, deck, 388.4, white, Map3DVertex.floodlit)
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
        wallBand(Self.notched(12.4, 2.5), 388.4, Self.notched(12.4, 2.5), 391.0, white, Self.plain)
        cap(Self.notched(12.4, 2.5), 391.0, white, Self.plain)
        notchedBand(10.75, 2.15, 391.0, 15.0, 3.0, 430.6, glass: colour("glassTop"), white: white, glassLayer: Map3DVertex.towerGlass)
        wallBand(Self.notched(10.95, 2.2), 391.0, Self.notched(11.15, 2.25), 392.2, white, Self.plain)
        wallBand(Self.notched(15.0, 3.0), 430.6, Self.notched(15.6, 3.1), 431.2, white, Map3DVertex.floodlit)
        wallBand(Self.notched(15.6, 3.1), 431.2, Self.notched(15.8, 3.2), 433.0, white, Map3DVertex.floodlit)
        cap(Self.notched(15.8, 3.2), 433.0, white, Self.plain)
        if full {
            let foot = Self.notched(10.75, 2.15), head = Self.notched(15.0, 3.0)
            for k in foot.indices where k % 5 == 2 {
                fin(from: foot[k], 392.2, to: head[k], 430.6, width: 0.4, depth: 0.4, white)
            }
        }
        for (z0, z1, h, c) in [(Float(433), Float(439), Float(10.75), Float(2.7)), (439, 443.5, 8.4, 2.1), (443.5, 448, 7.15, 1.8)] {
            // The crown floodlit at night.
            wallBand(Self.chamfered(h, c), z0, Self.chamfered(h, c), z1, white, Map3DVertex.floodlit)
            cap(Self.chamfered(h, c), z1, white, Self.plain)
        }
        wallBand(Self.chamfered(3.2, 1.0), 448, Self.chamfered(2.6, 0.8), 456, white, Self.plain)
        cap(Self.chamfered(2.6, 0.8), 456, white, Self.plain)
        // The spire, its last 5 m a white light after dark.
        wallBand(Self.chamfered(1.3, 0.4), 456, Self.chamfered(0.324, 0.1), 503, white, Self.plain)
        wallBand(Self.chamfered(0.324, 0.1), 503, Self.chamfered(0.22, 0.07), 508, white, Map3DVertex.glowing)
        if full {
            for z in [Float(466), 478, 490] {
                let r = 1.3 - (z - 456) / 52 * 1.08 + 0.35
                wallBand(Self.chamfered(r, r * 0.3), z, Self.chamfered(r, r * 0.3), z + 0.9, white, Self.plain)
                cap(Self.chamfered(r, r * 0.3), z + 0.9, white, Self.plain)
            }
        }
        shift(from: start, by: Self.towerAt)
    }

    /// A ruyi (如意) `height` tall standing out from the corner point `p`
    /// (facing away from the middle) from `z` up: a stem under a three-
    /// lobed head, its face and its edge.
    mutating func ruyi(at p: P2, z: Float, height h: Float, _ color: UInt32) {
        let r = (p.x * p.x + p.y * p.y).squareRoot(), ux = p.x / r, uy = p.y / r
        let depth: Float = 0.6, out: Float = 0.3
        // Across and up, in eighths of its height: the stem, then the head.
        let outline: [P2] = [(0, 0), (0.06, 0.08), (0.07, 0.45), (0.2, 0.52), (0.24, 0.72), (0.12, 0.84), (0, 1),
                             (-0.12, 0.84), (-0.24, 0.72), (-0.2, 0.52), (-0.07, 0.45), (-0.06, 0.08)]
        func at(_ q: P2, _ d: Float) -> P3 {
            (p.x + ux * (out + d) - uy * q.x * h, p.y + uy * (out + d) + ux * q.x * h, z + q.y * h)
        }
        let middle: P2 = (0, 0.6)
        for k in outline.indices {
            let a = outline[k], b = outline[(k + 1) % outline.count]
            tri(at(middle, depth), at(b, depth), at(a, depth), color, Self.plain)
            quad(at(a, 0), at(a, depth), at(b, depth), at(b, 0), color, Self.plain)
        }
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
    /// corner strips run up its steps, floodlit after dark.
    mutating func fin(from a: P2, _ za: Float, to b: P2, _ zb: Float, width: Float, depth: Float, _ color: UInt32) {
        func ring(_ p: P2) -> [P2] {
            let r = (p.x * p.x + p.y * p.y).squareRoot(), ux = p.x / r, uy = p.y / r, w = width / 2
            return [(p.x - uy * w, p.y + ux * w), (p.x + uy * w, p.y - ux * w),
                    (p.x + uy * w + ux * depth, p.y - ux * w + uy * depth), (p.x - uy * w + ux * depth, p.y + ux * w + uy * depth)]
        }
        let ra = ring(a), rb = ring(b)
        for k in 0..<4 {
            let j = (k + 1) % 4
            quad((ra[k].x, ra[k].y, za), (ra[j].x, ra[j].y, za), (rb[j].x, rb[j].y, zb), (rb[k].x, rb[k].y, zb), color, Map3DVertex.floodlit)
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
                quad(front0, front1, back1, back0, colour("stationRoof"), Self.tiles, [(0, 0), (28.8, 0), (24.4, 11.4), (4.4, 11.4)])
                tri(foot0, front0, back0, colour("stationRoof"), Self.tiles)
                tri(front1, foot1, back1, colour("stationRoof"), Self.tiles)
            } else {
                quad(front1, front0, back0, back1, colour("stationRoof"), Self.tiles, [(0, 0), (28.8, 0), (24.4, 11.4), (4.4, 11.4)])
                tri(front0, foot0, back0, colour("stationRoof"), Self.tiles)
                tri(foot1, front1, back1, colour("stationRoof"), Self.tiles)
            }
            if full {
                for x in [Float(-12.5), -4.2, 4.2, 12.5] {
                    let yy = sign * (hy + 9.4)
                    box(x - 0.7, yy - 0.7, 0.8, x + 0.7, yy + 0.7, 7.4, colour("wall"), Self.plain)
                }
            }
        }
        // Decision 457 (later): the roofs are the Chinese roof part. The
        // lower eave, a tiled skirt over the arcade, its corners turned up.
        let colours = ChineseRoofColours(tile: colour("stationRoof"), ridge: colour("ridge"), underside: colour("soffit"), gable: nil,
                                         wall: colour("wall"))
        skirtRoof(hx, hy, eaves: 8.6, wall: 11.4, over: 4.2, sweep: 1.4, lip: 0.5, tile: colours.tile, edge: colours.ridge,
                  underside: colours.underside)
        // The upper walls: cream pilasters every 3.6 m, a belt, and between
        // the pilasters tall windows all the way round (the Blender model's
        // upright windows); to 18 m, the cornice to 20.2 m, so that the
        // roof's ridge stands 28.8 m high and its ornaments 30 m (OSM way
        // 23641610: 30 m, its roof from the lower eave 18 m high).
        let ux = hx - 1.2, uy = hy - 1.2
        cap([(-ux, -uy), (ux, -uy), (ux, uy), (-ux, uy)], 11.4, colour("wall"), Self.plain)
        pilasters(ux, uy, 11.4, 18.0, step: 3.6, depth: 0.7, width: 1.3, colour("wall"), panel: colour("wall"), panelLayer: Self.floors)
        let windows: [P2] = [(-ux - 0.08, -uy - 0.08), (ux + 0.08, -uy - 0.08), (ux + 0.08, uy + 0.08), (-ux - 0.08, uy + 0.08)]
        wallBand(windows, 12.6, windows, 17.4, colour("stripGlass"), Self.curtain)
        let belt: [P2] = [(-ux - 0.3, -uy - 0.3), (ux + 0.3, -uy - 0.3), (ux + 0.3, uy + 0.3), (-ux - 0.3, uy + 0.3)]
        wallBand(belt, 11.9, belt, 12.4, colour("wall"), Self.plain)
        // The cornice: a white band and a bracket course.
        box(-ux - 0.9, -uy - 0.9, 18.0, ux + 0.9, uy + 0.9, 19.4, colour("trim"), Self.plain)
        box(-ux - 2.2, -uy - 2.2, 19.4, ux + 2.2, uy + 2.2, 20.2, colour("soffit"), Self.plain)
        // The great roof (盝頂): from eaves 5.9 m out, concave, the corners
        // swept up, to the ridge round the flat middle.
        let rx: Float = 46.5, ry: Float = 29.5
        chineseRoof(ux + 0.9, uy + 0.9, eaves: 20.7, over: 5.0, rise: 8.1, sweep: 2.6, kind: .flat(x: rx, y: ry), colours: colours)
        let ztop: Float = 27.8
        // The flat middle a little below the ridge, with a skylight and
        // plant.
        let well = LandmarkMesh.rectRing(rx, ry, perSide: full ? 10 : 6).points.reversed().map { $0 }
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

    // MARK: Kaohsiung Main Station

    /// An ellipse's outline centred at `(cx, cy)` with radii `rx` and `ry`,
    /// turned `angle` degrees counter-clockwise.
    static func ovalRing(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, angle: Float = 0, segments: Int = 12) -> [P2] {
        let a = angle * .pi / 180, ca = cos(a), sa = sin(a)
        return (0..<segments).map { s in
            let t = 2 * Float.pi * Float(s) / Float(segments)
            let lx = rx * cos(t), ly = ry * sin(t)
            return (cx + lx * ca - ly * sa, cy + lx * sa + ly * ca)
        }
    }

    /// The undulating height of Kaohsiung Main Station's green canopy
    /// (OSM relation 14940189, way 1298938821), peaking at 23 m over the
    /// central plaza and sloping to 19.1-20.8 m along the arms.
    static func canopyHeight(_ x: Float, _ y: Float) -> Float {
        let dx = (x - 12) / 140, dy = (y + 2) / 135, r2 = dx * dx + dy * dy
        let dome: Float = 3.4 / (1 + 0.85 * r2 + 0.36 * r2 * r2)
        let wave: Float = 0.25 * cos(x / 55) * cos(y / 48)
        return min(22.6, max(19.1, 19.25 + dome + wave))
    }

    /// A curved canopy arm or green bikeway wing along `spine`
    /// (`(x, y, halfWidth)`), arched in cross-section with a planted top,
    /// white soffit and white edge fascia.
    mutating func canopyArm(_ spine: [(x: Float, y: Float, halfWidth: Float)], along: Int, across: Int) {
        let m = spine.count - 1
        let normals: [P2] = (0...m).map { k in
            let prev = spine[max(0, k - 1)], next = spine[min(m, k + 1)]
            let tx = next.x - prev.x, ty = next.y - prev.y
            let length = (tx * tx + ty * ty).squareRoot()
            return (-ty / length, tx / length)
        }
        var stations: [(top: [P3], bot: [P3])] = []
        for i in 0...along {
            let u = Float(i) / Float(along) * Float(m)
            let k = min(m - 1, Int(u)), f = u - Float(k)
            let x = spine[k].x + (spine[k + 1].x - spine[k].x) * f
            let y = spine[k].y + (spine[k + 1].y - spine[k].y) * f
            let hw = spine[k].halfWidth + (spine[k + 1].halfWidth - spine[k].halfWidth) * f
            let rawNx = normals[k].x * (1 - f) + normals[k + 1].x * f
            let rawNy = normals[k].y * (1 - f) + normals[k + 1].y * f
            let nl = (rawNx * rawNx + rawNy * rawNy).squareRoot()
            let nx = rawNx / nl, ny = rawNy / nl
            var rowTop: [P3] = [], rowBot: [P3] = []
            for j in 0...across {
                let s = Float(j) / Float(across) * 2 - 1
                let px = x + nx * hw * s, py = y + ny * hw * s
                let baseZ = Self.canopyHeight(px, py), arch = 0.85 * (1 - s * s)
                let zt = min(22.5, baseZ + arch * 0.35), zb = zt - (1.05 + 0.65 * (1 - s * s))
                rowTop.append((px, py, zt))
                rowBot.append((px, py, zb))
            }
            stations.append((rowTop, rowBot))
        }
        let grass = colour("canopyGrass"), lawn = colour("canopyLawn"), soffit = colour("soffit"), frame = colour("frame")
        for i in 0..<along {
            let (rt0, rb0) = stations[i], (rt1, rb1) = stations[i + 1]
            for j in 0..<across {
                let topColour = (across >= 4 && (j == 1 || j == 2)) ? lawn : grass
                quad(rt0[j], rt1[j], rt1[j + 1], rt0[j + 1], topColour, Self.plain)
                quad(rb0[j], rb0[j + 1], rb1[j + 1], rb1[j], soffit, Self.plain)
            }
            quad(rb0[0], rb1[0], rt1[0], rt0[0], frame, Self.plain)
            quad(rb1[across], rb0[across], rt0[across], rt1[across], frame, Self.plain)
        }
        let (rtEnd, rbEnd) = stations[along]
        for j in 0..<across {
            quad(rbEnd[j], rbEnd[j + 1], rtEnd[j + 1], rtEnd[j], frame, Self.plain)
        }
    }

    /// A white branching tree-column under the canopy, flaring into a
    /// funnel capital where it meets the soffit.
    mutating func treeColumn(_ cx: Float, _ cy: Float, top zTop: Float) {
        let frame = colour("frame"), segs = full ? 6 : 4
        let r0 = Self.ovalRing(cx, cy, 0.75, 0.75, segments: segs), zFork = zTop - 4.8
        wallBand(r0, 0, r0, zFork, frame, Self.plain)
        if full {
            let rMid = Self.ovalRing(cx, cy, 1.7, 1.7, segments: segs)
            let rCap = Self.ovalRing(cx, cy, 3.4, 3.4, segments: segs)
            wallBand(r0, zFork, rMid, zTop - 2.0, frame, Self.plain)
            wallBand(rMid, zTop - 2.0, rCap, zTop, frame, Self.plain)
        } else {
            let rCap = Self.ovalRing(cx, cy, 2.8, 2.8, segments: segs)
            wallBand(r0, zFork, rCap, zTop, frame, Self.plain)
        }
    }

    /// An elliptical skylight well (OSM relation 14940189 inner ways) or
    /// raised rooftop glass pavilion (`building:part` ways).
    mutating func skylightWell(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, angle: Float, base zBase: Float, pavilion: Bool) {
        let segs = full ? 12 : 8
        let rIn = Self.ovalRing(cx, cy, rx * 0.84, ry * 0.84, angle: angle, segments: segs)
        let rOut = Self.ovalRing(cx, cy, rx, ry, angle: angle, segments: segs)
        let frame = colour("frame"), sky = colour("skylight"), glass = colour("glass")
        if pavilion {
            let zb = min(20.8, zBase), zTop = zb + 1.8
            wallBand(rOut, zb - 0.3, rOut, zb + 0.4, frame, Self.plain)
            wallBand(rIn, zb + 0.4, rIn, zTop - 0.35, glass, Self.curtain)
            wallBand(rOut, zTop - 0.35, rOut, zTop, frame, Self.plain)
            cap(rOut, zTop, sky, Self.curtain)
        } else {
            let zRim = min(22.6, zBase + 0.35)
            wallBand(rOut, zRim - 1.2, rOut, zRim, frame, Self.plain)
            band(rOut, [Float](repeating: zRim, count: segs), rIn, [Float](repeating: zRim, count: segs), frame, Self.plain)
            let revIn = Array(rIn.reversed())
            wallBand(revIn, zRim - 0.4, revIn, zRim, frame, Self.plain)
            cap(rIn, zRim - 0.4, sky, Self.curtain)
        }
    }

    /// Decision 431: Kaohsiung Main Station — the curved green cloud canopy
    /// and station halls (OSM relation 14940189, outer way 1298938821,
    /// inner skylight ways and building:part pavilions) and the preserved
    /// Imperial Crown old station (OSM way 257770396).
    mutating func kaohsiungMainStation() {
        let polarRadii: [(angle: Float, radius: Float)] = [
            (-90, 104), (-75, 108), (-60, 96), (-45, 68), (-30, 46), (-15, 48),
            (0, 72), (15, 88), (30, 82), (45, 78), (60, 92), (75, 98),
            (90, 92), (105, 96), (120, 86), (135, 68), (150, 66), (165, 84),
            (180, 76), (195, 48), (210, 42), (225, 58), (240, 88), (255, 106),
        ]
        let subdiv = full ? 2 : 1, nCtrl = polarRadii.count
        var outerPts: [P2] = [], innerPts: [P2] = []
        for k in 0..<nCtrl {
            let r0 = polarRadii[(k + nCtrl - 1) % nCtrl].radius, r1 = polarRadii[k].radius
            let r2 = polarRadii[(k + 1) % nCtrl].radius, r3 = polarRadii[(k + 2) % nCtrl].radius
            let a1 = polarRadii[k].angle
            for s in 0..<subdiv {
                let t = Float(s) / Float(subdiv), t2 = t * t, t3 = t2 * t
                let r = 0.5 * ((2 * r1) + (-r0 + r2) * t + (2 * r0 - 5 * r1 + 4 * r2 - r3) * t2 + (-r0 + 3 * r1 - 3 * r2 + r3) * t3)
                let ang = (a1 + 15 * t) * .pi / 180, ca = cos(ang), sa = sin(ang)
                outerPts.append((2.0 + r * ca, 2.0 + r * sa))
                innerPts.append((2.0 + 16.5 * ca, 2.0 + 21.5 * sa))
            }
        }
        let steps = full ? 6 : 3
        var rings: [(points: [P2], top: [Float], bot: [Float])] = []
        for s in 0...steps {
            let t = Float(s) / Float(steps)
            let archT = sin(t * .pi), dipInner = 2.4 * powf(t, 2.2)
            var pts: [P2] = [], zTop: [Float] = [], zBot: [Float] = []
            for k in outerPts.indices {
                let x = outerPts[k].x * (1 - t) + innerPts[k].x * t
                let y = outerPts[k].y * (1 - t) + innerPts[k].y * t
                let zt = min(22.9, Self.canopyHeight(x, y) + 1.05 * archT - dipInner)
                let zb = zt - (1.10 + 0.70 * archT)
                pts.append((x, y))
                zTop.append(zt)
                zBot.append(zb)
            }
            if s == steps / 2, let maxIdx = zTop.indices.max(by: { zTop[$0] < zTop[$1] }) {
                zTop[maxIdx] = 23.0
            }
            rings.append((pts, zTop, zBot))
        }
        let grass = colour("canopyGrass"), lawn = colour("canopyLawn"), soffit = colour("soffit"), frame = colour("frame")
        for s in 0..<steps {
            let topColour = (s == 2 || s == 3) ? lawn : grass
            band(rings[s].points, rings[s].top, rings[s + 1].points, rings[s + 1].top, topColour, Self.plain)
            band(rings[s + 1].points, rings[s + 1].bot, rings[s].points, rings[s].bot, soffit, Self.plain)
        }
        band(rings[0].points, rings[0].bot, rings[0].points, rings[0].top, frame, Self.plain)
        let revIn = Array(rings[steps].points.reversed())
        let revTop = Array(rings[steps].top.reversed()), revBot = Array(rings[steps].bot.reversed())
        band(revIn, revBot, revIn, revTop, frame, Self.plain)

        // Seven radial canopy arms and green corridor wings (OSM way 1298938821: 664.78 m × 333.87 m).
        canopyArm([(72, 21, 23), (110, 19.5, 22), (150, 16, 20), (200, 11, 14), (260, 5, 8.2), (332.39, -1.3, 3.3)],
                  along: full ? 9 : 4, across: full ? 4 : 2)
        canopyArm([(-72, 26, 20), (-110, 34, 22), (-155, 38.5, 20.5), (-200, 42, 13.5), (-265, 46, 7.8), (-332.39, 49.3, 2.8)],
                  along: full ? 9 : 4, across: full ? 4 : 2)
        canopyArm([(28, 90, 14), (34, 116, 9.5), (38, 138, 11.5), (41, 156, 14.5), (39.5, 166.93, 6.0)],
                  along: full ? 5 : 3, across: full ? 4 : 2)
        canopyArm([(-32, 84, 10), (-48, 101, 7.5), (-60, 112, 9.5), (-64.5, 116.5, 4.5)],
                  along: full ? 4 : 2, across: 2)
        canopyArm([(-28, -96, 11), (-42, -124, 9), (-53, -148, 13.5), (-55, -159.5, 6.0)],
                  along: full ? 4 : 2, across: full ? 4 : 2)
        canopyArm([(26, -94, 11), (35, -124, 8.5), (41, -150, 12.5), (43, -166.93, 5.5)],
                  along: full ? 4 : 2, across: full ? 4 : 2)
        canopyArm([(38, -78, 8.5), (55, -92, 6.5), (68, -99, 8.0), (74.5, -101.5, 4.0)],
                  along: full ? 3 : 2, across: 2)

        // Skylight wells (OSM inner ways 1298938824, 1298938825, 1298938827, 1298938831, 1298938832).
        for (cx, cy, rx, ry, ang) in [(Float(7.4), Float(70.0), Float(15.0), Float(11.5), Float(0)),
                                      (58.0, 22.5, 13.5, 11.5, -10), (84.0, 21.5, 10.5, 9.0, 10),
                                      (-0.5, -54.4, 7.6, 9.5, 15), (-39.8, 29.0, 6.5, 7.0, -20),
                                      (-89.3, 28.8, 8.8, 6.1, -10)] {
            skylightWell(cx, cy, rx, ry, angle: ang, base: Self.canopyHeight(cx, cy) + 0.4, pavilion: false)
        }
        // Rooftop glass pavilions (OSM building:part ways 1298938822, 1298938826, 1298938828, 1298938823, 1298938829).
        for (cx, cy, rx, ry, ang) in [(Float(-146.1), Float(37.8), Float(12.8), Float(11.3), Float(0)),
                                      (128.4, 18.0, 12.6, 11.6, 0), (-18.4, -74.2, 4.3, 4.3, 0),
                                      (-107.9, 42.1, 4.2, 4.2, 0), (10.5, -37.9, 4.1, 4.1, 0)] where full || rx > 8 {
            skylightWell(cx, cy, rx, ry, angle: ang, base: Self.canopyHeight(cx, cy) + 0.3, pavilion: true)
        }

        // Curved glass station concourse halls under the central canopy.
        let plinth = colour("plinth"), wall = colour("wall"), groundGlass = colour("groundGlass")
        let hallSegs = full ? 12 : 8
        for (cx, cy, rx, ry, ang) in [(Float(-21), Float(12), Float(11.5), Float(28), Float(12)),
                                      (25, 10, 12, 29, -12), (2, 46, 20, 9.5, 0)] {
            let rPlinth = Self.ovalRing(cx, cy, rx + 0.8, ry + 0.8, angle: ang, segments: hallSegs)
            let rHall = Self.ovalRing(cx, cy, rx, ry, angle: ang, segments: hallSegs)
            wallBand(rPlinth, 0, rPlinth, 0.8, plinth, Self.plain)
            cap(rPlinth, 0.8, plinth, Self.plain)
            wallBand(rHall, 0.8, rHall, 5.2, groundGlass, Self.curtain)
            wallBand(rHall, 5.2, rHall, 6.4, wall, Self.floors)
            wallBand(rHall, 6.4, rHall, 11.2, groundGlass, Self.curtain)
            wallBand(rHall, 11.2, rHall, 12.6, wall, Self.floors)
            cap(rHall, 12.6, colour("flatRoof"), Self.plain)
        }

        // Supporting white tree-columns across the plaza, lobes and wings.
        let columns: [P2] = [
            (40.6, -162.1), (-54.0, -152.0), (-42.5, -137.8), (33.4, -139.2),
            (26.2, -116.3), (-26.7, -107.7), (-3.8, -100.6), (68.0, -99.0),
            (19.1, -93.4), (-18.2, -54.8), (11.9, -70.5), (89.2, 4.0),
            (165.0, 12.0), (240.9, 5.0), (312.0, 0.0), (-115.6, 28.0),
            (-168.6, 38.0), (-245.0, 45.0), (-312.0, 48.5), (-1.1, 51.2),
            (-8.2, 74.1), (37.6, 88.4), (34.0, 118.0), (42.0, 148.0),
            (-52.0, 106.0), (52.0, 42.6), (-46.9, 36.9), (112.1, 18.0),
        ]
        for (idx, col) in columns.enumerated() where full || idx.isMultiple(of: 2) {
            treeColumn(col.x, col.y, top: Self.canopyHeight(col.x, col.y) - 1.1)
        }

        // Decision 457 (later): the joint-development towers on OSM's plans
        // (way 1298938833 the offices, 1298938834 the hotel; OSM has no
        // height): 10 and 11 floors by the news, 3.5 m a floor (estimated).
        jointTower(Self.kaohsiungOffices, height: 35)
        jointTower(Self.kaohsiungHotel, height: 38.5)

        oldKaohsiungStation()
    }

    /// The offices' and the hotel's plans (OSM ways 1298938833 and
    /// 1298938834), counter-clockwise.
    static let kaohsiungOffices: [P2] = Array([
        (-29.8, -19.5), (-33.1, -62.4), (-33.7, -71.2), (-34.8, -84.6), (-35.9, -99.1), (-36.2, -102.1), (-37.3, -104.8), (-39.3, -107.1),
        (-41.8, -108.7), (-44.7, -109.4), (-47.7, -109.2), (-77.9, -106.9), (-80.9, -106.6), (-83.7, -105.5), (-86.0, -103.5),
        (-87.5, -101.0), (-88.3, -98.1), (-88.1, -95.1), (-81.9, -15.5), (-81.7, -12.5), (-80.5, -9.7), (-78.6, -7.5), (-76.0, -5.9),
        (-73.1, -5.2), (-70.1, -5.4), (-39.9, -7.7), (-36.9, -8.0), (-34.1, -9.1), (-31.9, -11.1), (-30.3, -13.6), (-29.6, -16.5)
    ].reversed())
    static let kaohsiungHotel: [P2] = Array([
        (42.3, -16.0), (57.8, -17.1), (61.0, -18.2), (64.1, -20.2), (67.5, -23.5), (69.5, -26.2), (71.7, -29.6), (72.5, -33.0),
        (72.7, -38.9), (71.1, -57.6), (69.8, -61.6), (68.0, -64.9), (65.9, -67.8), (63.0, -70.3), (59.9, -72.0), (56.4, -73.0),
        (51.3, -73.5), (37.8, -72.9), (33.3, -71.8), (31.5, -71.3), (27.6, -69.2), (24.3, -66.3), (21.9, -63.4), (20.1, -59.9),
        (19.1, -54.7), (18.8, -50.3), (18.5, -44.9), (19.6, -35.5), (21.4, -29.0), (24.1, -24.0), (28.6, -19.9), (31.8, -18.0),
        (35.8, -17.0), (39.3, -16.4)
    ].reversed())

    /// A plain glass tower `height` high on `plan`, in the pale look: glass
    /// with white floor bands every third floor close by, a white parapet
    /// and a flat roof; every second corner from afar.
    mutating func jointTower(_ plan: [P2], height h: Float) {
        let ring = full ? plan : plan.indices.filter { $0.isMultiple(of: 2) }.map { plan[$0] }
        wallBand(ring, 0, ring, h - 1.2, colour("glass"), Self.curtain)
        if full {
            for z in stride(from: Float(10.5), to: h - 1.5, by: 10.5) {
                wallBand(ring, z, ring, z + 0.5, colour("frame"), Self.plain)
            }
        }
        wallBand(ring, h - 1.2, ring, h, colour("frame"), Self.plain)
        cap(ring, h, colour("flatRoof"), Self.plain)
    }

    /// The preserved 1941 Imperial Crown station building on the south
    /// plaza (OSM way 257770396: 25.30 m × 30.36 m, building:levels = 3).
    mutating func oldKaohsiungStation() {
        let cx: Float = -5.11, cy: Float = -121.60, hx: Float = 12.25, hy: Float = 10.88
        let plinth = colour("plinth"), wall = colour("wall"), trim = colour("trim"), soffit = colour("soffit")
        let glass = colour("groundGlass"), strip = colour("stripGlass")
        let roof = colour("roof"), crown = colour("crownRoof"), ridge = colour("ridge"), flatRoof = colour("flatRoof")

        let rBody: [P2] = [(cx - hx, cy - hy), (cx + hx, cy - hy), (cx + hx, cy + hy), (cx - hx, cy + hy)]
        for (z0, z1, col, lay) in [(Float(0), Float(0.8), plinth, Self.plain), (0.8, 2.2, wall, Self.floors),
                                   (2.2, 4.4, glass, Self.curtain), (4.4, 5.2, wall, Self.floors),
                                   (5.2, 5.8, trim, Self.plain), (5.8, 6.8, wall, Self.floors),
                                   (6.8, 9.2, strip, Self.curtain), (9.2, 11.4, wall, Self.floors),
                                   (11.4, 12.0, trim, Self.plain)] {
            wallBand(rBody, z0, rBody, z1, col, lay)
        }
        cap(rBody, 12.0, flatRoof, Self.plain)
        if full {
            for s in 0..<6 {
                let x = (cx - hx + 1.8) + (2 * hx - 3.6) * Float(s) / 5
                for ySide in [cy - hy - 0.25, cy + hy + 0.25] {
                    box(x - 0.35, ySide - 0.22, 0.8, x + 0.35, ySide + 0.22, 11.4, wall, Self.plain)
                }
            }
        }

        // South entrance portico (extending south to y = -140.68).
        let px0: Float = -15.05, px1: Float = 2.85, py0: Float = -140.28, py1: Float = cy - hy
        let pRing: [P2] = [(px0, py0), (px1, py0), (px1, py1), (px0, py1)]
        for (z0, z1, col, lay) in [(Float(0), Float(0.8), plinth, Self.plain), (0.8, 2.0, wall, Self.floors),
                                   (2.0, 4.6, glass, Self.curtain), (4.6, 8.2, wall, Self.floors),
                                   (8.2, 8.8, trim, Self.plain)] {
            wallBand(pRing, z0, pRing, z1, col, lay)
        }
        cap(pRing, 8.8, flatRoof, Self.plain)
        let pOut: [P2] = [(px0 - 0.4, py0 - 0.4), (px1 + 0.4, py0 - 0.4), (px1 + 0.4, py1), (px0 - 0.4, py1)]
        let pIn: [P2] = [(px0 + 1.8, py0 + 1.8), (px1 - 1.8, py0 + 1.8), (px1 - 1.8, py1), (px0 + 1.8, py1)]
        band(pOut, [Float](repeating: 8.8, count: 4), pIn, [Float](repeating: 10.3, count: 4), roof, Self.tiles)
        cap(pIn, 10.3, flatRoof, Self.plain)
        if full {
            for s in 0..<4 {
                let x = (px0 + 2.2) + (px1 - px0 - 4.4) * Float(s) / 3
                box(x - 0.32, py0 - 0.32, 0.8, x + 0.32, py0 + 0.15, 8.2, trim, Self.plain)
            }
        }

        // Lower tiled hip skirt round the two-storey hall (12.0-13.4 m).
        let rEave: [P2] = [(cx - hx - 0.4, cy - hy - 0.4), (cx + hx + 0.4, cy - hy - 0.4),
                           (cx + hx + 0.4, cy + hy + 0.4), (cx - hx - 0.4, cy + hy + 0.4)]
        let rDeck: [P2] = [(cx - hx + 2.2, cy - hy + 2.2), (cx + hx - 2.2, cy - hy + 2.2),
                           (cx + hx - 2.2, cy + hy - 2.2), (cx - hx + 2.2, cy + hy - 2.2)]
        band(rEave, [Float](repeating: 12.0, count: 4), rDeck, [Float](repeating: 13.4, count: 4), roof, Self.tiles)
        cap(rDeck, 13.4, flatRoof, Self.plain)

        // Central Imperial Crown tower (12.0-16.86 m).
        let tcx: Float = -1.6, tcy: Float = -125.9, th: Float = 5.1
        let tRing: [P2] = [(tcx - th, tcy - th), (tcx + th, tcy - th), (tcx + th, tcy + th), (tcx - th, tcy + th)]
        for (z0, z1, col, lay) in [(Float(12.0), Float(12.3), wall, Self.floors),
                                   (12.3, 13.1, strip, Self.curtain), (13.1, 13.5, wall, Self.floors)] {
            wallBand(tRing, z0, tRing, z1, col, lay)
        }
        box(tcx - th - 0.35, tcy - th - 0.35, 13.5, tcx + th + 0.35, tcy + th + 0.35, 13.85, soffit, Self.plain)

        let cSteps = full ? 5 : 3, perSide = full ? 5 : 3
        let (unitPts, unitNear) = Self.rectRing(1, 1, perSide: perSide)
        let eHalf: Float = 5.8, rHalf: Float = 1.35
        var cRings: [(points: [P2], heights: [Float])] = []
        for s in 0...cSteps {
            let t = Float(s) / Float(cSteps)
            let sh = eHalf - (eHalf - rHalf) * t
            let sweep = 0.85 * (1 - t) * (1 - t) * (1 - t)
            let zs = unitNear.map { n -> Float in
                let corner = 1 - min(n, 0.35) / 0.35
                return 13.85 + 2.55 * powf(t, 1.55) + sweep * corner * corner
            }
            cRings.append((unitPts.map { (tcx + $0.x * sh, tcy + $0.y * sh) }, zs))
        }
        for s in 0..<cSteps {
            band(cRings[s].points, cRings[s].heights, cRings[s + 1].points, cRings[s + 1].heights, crown, Self.tiles)
        }
        let e0 = cRings[0]
        band(e0.points, e0.heights.map { $0 - 0.35 }, e0.points, e0.heights, trim, Self.plain)
        let topPts = cRings[cSteps].points, zTopCrown = cRings[cSteps].heights[0]
        cap(topPts, zTopCrown, ridge, Self.plain)
        box(tcx - 1.45, tcy - 1.45, zTopCrown, tcx + 1.45, tcy + 1.45, 16.86, ridge, Self.plain, top: ridge)

        if full {
            for k in [0, perSide, perSide * 2, perSide * 3] {
                for s in 0..<cSteps {
                    let a = cRings[s].points[k], b = cRings[s + 1].points[k]
                    let za = cRings[s].heights[k], zb = cRings[s + 1].heights[k]
                    let d = Self.distance(a, b)
                    let nx = -(b.y - a.y) / d * 0.24, ny = (b.x - a.x) / d * 0.24
                    quad((a.x - nx, a.y - ny, za + 0.18), (a.x + nx, a.y + ny, za + 0.18),
                         (b.x + nx, b.y + ny, zb + 0.18), (b.x - nx, b.y - ny, zb + 0.18), ridge, Self.plain)
                }
            }
            for ySign in [Float(-1), 1] {
                let gy = tcy + ySign * (th + 0.55)
                box(tcx - 2.1, gy - 0.35, 13.4, tcx + 2.1, gy + 0.35, 14.55, trim, Self.plain, top: ridge)
            }
        }
    }

    /// A rectangle centered at `(cx, cy)` of half-sides `hx` and `hy`, with
    /// corners chamfered by `cut`, counter-clockwise from the front (-y) face.
    static func chamferRing(_ cx: Float, _ cy: Float, _ hx: Float, _ hy: Float, _ cut: Float) -> [P2] {
        [(cx - hx + cut, cy - hy), (cx + hx - cut, cy - hy),
         (cx + hx, cy - hy + cut), (cx + hx, cy + hy - cut),
         (cx + hx - cut, cy + hy), (cx - hx + cut, cy + hy),
         (cx - hx, cy + hy - cut), (cx - hx, cy - hy + cut)]
    }

    mutating func chamferBand(_ cx: Float, _ cy: Float, _ hx: Float, _ hy: Float, _ cut: Float, _ z0: Float, _ z1: Float,
                              _ color: UInt32, _ layer: Float, top: UInt32? = nil) {
        let r = Self.chamferRing(cx, cy, hx, hy, cut)
        wallBand(r, z0, r, z1, color, layer)
        if let top { cap(r, z1, top, Self.plain) }
    }

    mutating func soffitQuad(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ z: Float, _ color: UInt32) {
        quad((x0, y1, z), (x1, y1, z), (x1, y0, z), (x0, y0, z), color, Self.plain)
    }

    /// A rectangle centered at `(cx, cy)` of half-sides `hx` and `hy`, with
    /// corner rectangular notches of `(nx, ny)` at all four corners.
    static func notchedRing(_ cx: Float, _ cy: Float, _ hx: Float, _ hy: Float, _ nx: Float, _ ny: Float) -> [P2] {
        [(cx - hx + nx, cy - hy), (cx + hx - nx, cy - hy),
         (cx + hx - nx, cy - hy + ny), (cx + hx, cy - hy + ny),
         (cx + hx, cy + hy - ny), (cx + hx - nx, cy + hy - ny),
         (cx + hx - nx, cy + hy), (cx - hx + nx, cy + hy),
         (cx - hx + nx, cy + hy - ny), (cx - hx, cy + hy - ny),
         (cx - hx, cy - hy + ny), (cx - hx + nx, cy - hy + ny)]
    }

    static func cornerRing(_ hx: Float, _ hy: Float, x0: Float = 0, y0: Float = 0) -> [P2] {
        [(x0 - hx, y0 - hy), (x0 + hx, y0 - hy), (x0 + hx, y0 + hy), (x0 - hx, y0 + hy)]
    }

    mutating func box(hx: Float, hy: Float, z0: Float, z1: Float, _ color: UInt32, _ layer: Float,
                      top: UInt32? = nil, x0: Float = 0, y0: Float = 0) {
        box(x0 - hx, y0 - hy, z0, x0 + hx, y0 + hy, z1, color, layer, top: top)
    }

    /// Decision 548: Kaohsiung 85 Sky Tower (OSM way 34170948 podium
    /// 143.00 m × 68.21 m, height = 50 m; twin wings ways 344740871 &
    /// 344740872 height = 190 m flanking the central hollow portal;
    /// central bridging tower way 344740874 height = 330 m; pyramidal
    /// crown way 345038766 height = 347.5 m; spire way 345038767
    /// height = 378 m).
    mutating func kaohsiung85SkyTower() {
        let podium = colour("podium"), hallWall = colour("hallWall"), roof = colour("roof")
        let trim = colour("trim"), frame = colour("frame"), plinth = colour("plinth")
        let flatRoof = colour("flatRoof"), podiumRoof = colour("podiumRoof"), soffit = colour("soffit")
        let glass = colour("glass"), glassTop = colour("glassTop"), groundGlass = colour("groundGlass")
        let stripGlass = colour("stripGlass"), skylight = colour("skylight")
        let greenRidge = colour("greenRidge"), crownRoof = colour("crownRoof"), doorway = colour("doorway")
        let ornament = colour("ornament"), vermilion = colour("vermilion"), spire = colour("spire")
        let towerGlass = Map3DVertex.towerGlass, floodlit = Map3DVertex.floodlit, glowing = Map3DVertex.glowing

        // 1. Outer Podium Base (OSM way 34170948: 143.00 × 68.21 m, height = 50 m)
        box(-71.5, -34.1, 0, 71.5, 34.1, 2.8, plinth, Self.plain, top: podiumRoof)
        box(-70.8, -33.6, 2.8, 70.8, 33.6, 32, hallWall, Self.floors, top: podiumRoof)
        box(-56, -33.75, 2.8, 56, 33.75, 9.2, groundGlass, Self.curtain)
        box(-70.95, -22, 2.8, 70.95, 22, 9.2, groundGlass, Self.curtain)
        for z: Float in (full ? [9.2, 16.5, 24, 31.4] : [9.2, 31.4]) {
            box(-71.2, -33.9, z, 71.2, 33.9, z + 0.6, podium, Self.plain, top: trim)
        }
        if full {
            for k in -5...5 {
                let x = Float(k) * 12
                box(x - 0.85, -34, 2.8, x + 0.85, 34, 31.4, roof, Self.plain)
            }
            for y: Float in [-22, -11, 0, 11, 22] {
                box(-71.1, y - 0.85, 2.8, 71.1, y + 0.85, 31.4, roof, Self.plain)
            }
        }

        // Upper podium transition (32..50 m, OSM way 34170948 height = 50 m)
        for sx: Float in [-1, 1] {
            let cx = sx * 42
            box(cx - 26, -30, 32, cx + 26, 30, 50, roof, Self.floors, top: podiumRoof)
            box(cx - 26.4, -30.4, 49.2, cx + 26.4, 30.4, 50, trim, Self.plain, top: podiumRoof)
        }
        // Central podium atrium bridge (OSM way 344740873: min_height = 50, height = 70 m)
        box(-16.5, -28.5, 32, 16.5, 28.5, 44, hallWall, Self.floors, top: podiumRoof)
        box(-11.5, -26.5, 44, 11.5, 26.5, 50, podium, Self.floors, top: podiumRoof)
        box(-9, -18, 50, 9, 18, 52, skylight, Self.curtain, top: skylight)

        // 2. Twin Wings (OSM ways 344740871 & 344740872: min_height = 50, height = 190 m, shoulder crown to 214 m)
        for sx: Float in [-1, 1] {
            let wcx = sx * 41.5
            chamferBand(wcx, 0, 23.3, 26.2, 2.8, 50, 190, glass, towerGlass, top: flatRoof)

            // Projecting curtain-wall bay on N/S/outer wing facades (56..148 m)
            box(wcx - 17.2, -27.4, 56, wcx + 17.2, 27.4, 148, glassTop, Self.curtain, top: trim)
            soffitQuad(wcx - 17.2, -27.4, wcx + 17.2, 27.4, 56, trim)
            let ox0 = min(wcx + sx * 19.5, wcx + sx * 24.3), ox1 = max(wcx + sx * 19.5, wcx + sx * 24.3)
            box(ox0, -16.8, 56, ox1, 16.8, 148, glassTop, Self.curtain, top: trim)
            soffitQuad(ox0, -16.8, ox1, 16.8, 56, trim)

            // Warm rose-taupe stone corner piers framing the wing bays
            for px in [wcx - 17.8, wcx + 17.8] {
                box(px - 1.5, -27.7, 50, px + 1.5, 27.7, 190, roof, Self.floors, top: trim)
            }
            let ipx = sx * 19.3
            box(ipx - 1.2, -26.5, 50, ipx + 1.2, 26.5, 190, podium, Self.floors, top: trim)

            if full {
                for k in -2...2 {
                    let bx = wcx + Float(k) * 6.75
                    box(bx - 0.6, -27.5, 52.5, bx + 0.6, 27.5, 56, roof, Self.plain)
                    box(bx - 0.25, -27.65, 56, bx + 0.25, 27.65, 148, frame, Self.plain)
                }
                for step in 0..<9 {
                    let z = 64 + Float(step) * 14
                    chamferBand(wcx, 0, 23.55, 26.45, 2.8, z, z + 0.55, frame, Self.plain)
                }
            }

            // Wing Upper Setback & Stepped Shoulder Crown (190..214 m)
            let icx = sx * 35.6
            box(icx - 10.4, -24.8, 190, icx + 10.4, 24.8, 198, glass, towerGlass, top: flatRoof)
            box(icx - 10.6, -25, 197.2, icx + 10.6, 25, 198, roof, Self.plain, top: trim)
            let scx = sx * 50.1
            chamferBand(scx, 0, 14.1, 24.8, 2.2, 190, 208, glass, towerGlass, top: flatRoof)
            chamferBand(scx, 0, 14.3, 25, 2.2, 200.5, 204.5, doorway, Self.plain)
            chamferBand(scx, 0, 14.4, 25.1, 2.2, 208, 210.8, roof, Self.plain, top: trim)
            box(scx - 8.8, -25.3, 210.8, scx + 8.8, 25.3, 214, hallWall, Self.plain, top: greenRidge)
            if full {
                for cySign: Float in [-1, 1] {
                    for cxOff: Float in [-12.5, 12.5] {
                        box(scx + cxOff - 1.7, cySign * 23.4 - 1.7, 190,
                            scx + cxOff + 1.7, cySign * 23.4 + 1.7, 214.8, roof, Self.plain, top: trim)
                    }
                }
            }
        }

        // 3. Central Sky-Bridge Lintel over the Hollow Portal (148..168 m, OSM way 344740874 lower part)
        soffitQuad(-19.5, -26.2, 19.5, 26.2, 148, soffit)
        box(-19.5, -26.2, 148, 19.5, 26.2, 150, podium, Self.plain)
        box(-25.3, -26.5, 150, 25.3, 26.5, 168, roof, Self.floors, top: trim)
        for (z0, z1): (Float, Float) in [(152.2, 157.8), (160.6, 166)] {
            box(-17.8, -26.75, z0, 17.8, 26.75, z1, groundGlass, Self.curtain)
        }
        if full {
            for k in 0..<6 {
                let x = -14.5 + Float(k) * 5.8
                box(x - 0.55, -26.85, 151.2, x + 0.55, 26.85, 166.8, roof, Self.plain)
            }
        }

        // 4. Central Main Tower (OSM way 344740874: 168..330 m)
        let towerRing = Self.chamferRing(0, 0, 25.3, 24.7, 3)
        wallBand(towerRing, 168, towerRing, 198, glass, towerGlass)
        wallBand(towerRing, 198, towerRing, 330, glassTop, towerGlass)
        cap(towerRing, 330, flatRoof, Self.plain)

        box(-14.2, -25, 198, 14.2, 25, 326, hallWall, Self.floors)
        box(-25.6, -13.8, 198, 25.6, 13.8, 326, hallWall, Self.floors)
        box(-12.2, -25.15, 200, 12.2, 25.15, 323, stripGlass, Self.curtain)
        box(-25.75, -11.8, 200, 25.75, 11.8, 323, stripGlass, Self.curtain)
        for s: Float in [-1, 1] {
            box(s * 13.5 - 1.2, -25.3, 168, s * 13.5 + 1.2, 25.3, 330, roof, Self.floors, top: trim)
            box(-25.9, s * 13.1 - 1.2, 168, 25.9, s * 13.1 + 1.2, 330, roof, Self.floors, top: trim)
        }

        for z0: Float in [255, 299] {
            chamferBand(0, 0, 25.6, 25, 3, z0, z0 + 4.2, doorway, Self.plain)
            chamferBand(0, 0, 25.8, 25.2, 3, z0 - 0.7, z0, roof, Self.plain)
            chamferBand(0, 0, 25.8, 25.2, 3, z0 + 4.2, z0 + 4.9, roof, Self.plain)
        }

        for z: Float in [198, 203.5, 209, 311.5, 317, 322.5] {
            chamferBand(0, 0, 25.7, 25.1, 3, z, z + 1.2, roof, Self.plain)
        }

        if full {
            for z: Float in [174, 185, 220, 231, 242, 266, 277, 288] {
                chamferBand(0, 0, 25.55, 24.95, 3, z, z + 0.5, roof, Self.plain)
            }
            for m: Float in [-8, -2.7, 2.7, 8] {
                box(m - 0.35, -25.25, 198, m + 0.35, 25.25, 324, roof, Self.plain)
                box(-25.85, m - 0.35, 198, 25.85, m + 0.35, 324, roof, Self.plain)
            }
        }

        chamferBand(0, 0, 25.8, 25.2, 3, 326, 330, roof, Self.plain, top: trim)
        box(-14.5, -25.5, 330, 14.5, 25.5, 332.8, hallWall, floodlit, top: greenRidge)
        box(-26.1, -14, 330, 26.1, 14, 332.8, hallWall, floodlit, top: greenRidge)
        if full {
            for sx: Float in [-1, 1] {
                for sy: Float in [-1, 1] {
                    box(sx * 22.8 - 2.1, sy * 22.2 - 2.1, 326,
                        sx * 22.8 + 2.1, sy * 22.2 + 2.1, 333.2, roof, floodlit, top: trim)
                }
            }
        }

        // 5. Pyramidal Crown (OSM way 345038766: min_height = 330, height = 347.5 m, roof:shape = pyramidal)
        let crownBase = Self.chamferRing(0, 0, 17.5, 17, 3)
        wallBand(crownBase, 330, crownBase, 335, crownRoof, floodlit)
        let crownMid = Self.chamferRing(0, 0, 11.8, 11.5, 2.2)
        let crownTop = Self.chamferRing(0, 0, 4.2, 4.2, 1)
        wallBand(crownBase, 335, crownMid, 341.5, greenRidge, floodlit)
        wallBand(crownMid, 341.5, crownTop, 347.5, greenRidge, floodlit)
        cap(crownTop, 347.5, trim, floodlit)
        if full {
            wallBand(crownMid, 341.2, crownMid, 341.8, ornament, floodlit)
        }

        // 6. Spire & Antenna Mast (OSM way 345038767: height = 378 m)
        let drum0 = Self.chamferRing(0, 0, 2.2, 2.2, 0.6)
        let drum1 = Self.chamferRing(0, 0, 1.5, 1.5, 0.4)
        wallBand(drum0, 347.5, drum1, 354.5, trim, floodlit)
        cap(drum1, 354.5, trim, floodlit)
        if full {
            for rz: Float in [349.5, 352.2] {
                let ringC = Self.chamferRing(0, 0, 2, 2, 0.5)
                wallBand(ringC, rz, ringC, rz + 0.65, vermilion, floodlit)
            }
        }

        let s0 = Self.chamferRing(0, 0, 0.85, 0.85, 0.25)
        let s1 = Self.chamferRing(0, 0, 0.35, 0.35, 0.1)
        let s2 = Self.chamferRing(0, 0, 0.16, 0.16, 0.05)
        wallBand(s0, 354.5, s1, 374, spire, floodlit)
        wallBand(s1, 374, s2, 378, ornament, glowing)
        cap(s2, 378, ornament, glowing)
    }

    /// Decision 550: Taipei Shin Kong Life Tower (OSM way 204711206:
    /// 84.90 m × 40.26 m, height = 244.15 m; stepped podium ways 644774205..644774218
    /// height = 46.56 m & 63.20 m, way 644774201 height = 78.56 m, north 18F
    /// turret way 644774185 height = 86.24 m; main shaft way 644774181 height =
    /// 211.04 m with 44F/46F/48F setbacks ways 644774184..644774200 at 187.36 m,
    /// 195.68 m & 203.36 m; crown collar way 644774173 height = 214.88 m &
    /// stepped crown penthouse way 644774171 height = 237.67 m).
    mutating func shinKongLifeTower() {
        let rose = colour("roof")
        let brick = colour("brick")
        let crownSlope = colour("stationRoof")
        let podium = colour("podium")
        let trim = colour("trim")
        let plinth = colour("plinth")
        let flatRoof = colour("flatRoof")
        let podiumRoof = colour("podiumRoof")
        let glass = colour("glass")
        let glassTop = colour("glassTop")
        let groundGlass = colour("groundGlass")
        let louver = colour("doorway")
        let ornament = colour("ornament")
        let vermilion = colour("vermilion")
        let spire = colour("spire")

        let towerGlass = Map3DVertex.towerGlass, floodlit = Map3DVertex.floodlit, glowing = Map3DVertex.glowing

        // 1. Ground Plinth & North Semicircular Entrance Plaza (OSM way 204711206:
        //    84.90 m × 40.26 m, x in [-42.45, 42.45], y in [-20.13, 20.13];
        //    north entrance ways 616097083, 644774202, 644774176, 644774178;
        //    west 4F arcade strip way 644774180 height = 19.68 m).
        let baseRing = Self.cornerRing(42.45, 20.13)
        wallBand(baseRing, 0, baseRing, 4.5, plinth, Self.floors)
        cap(baseRing, 4.5, flatRoof, Self.plain)

        // Flanking 2-level north plaza wings (ways 644774176 & 644774178)
        for sy: Float in [-1, 1] {
            box(hx: 2.49, hy: 4.64, z0: 4.5, z1: 9.6, rose, Self.floors, top: flatRoof, x0: 34.36, y0: sy * 11.81)
            if full {
                box(hx: 2.55, hy: 4.70, z0: 9.1, z1: 9.7, podium, Self.floors, top: flatRoof, x0: 34.36, y0: sy * 11.81)
            }
        }

        // North 3-level semicircular entrance rotunda (way 644774202) & 2-level porch (way 616097083)
        let archSegs = full ? 8 : 4
        var archRing: [P2] = [(31.87, -7.0)]
        for i in 0...archSegs {
            let ang = -Float.pi / 2 + Float.pi * Float(i) / Float(archSegs)
            archRing.append((31.87 + 7.05 * cos(ang), 7.0 * sin(ang)))
        }
        archRing.append((31.87, 7.0))
        wallBand(archRing, 4.5, archRing, 14.0, rose, Self.floors)
        cap(archRing, 14.0, flatRoof, Self.plain)

        var glassArch: [P2] = [(32.0, -5.6)]
        for i in 0...archSegs {
            let ang = -Float.pi / 2 + Float.pi * Float(i) / Float(archSegs)
            glassArch.append((32.0 + 7.02 * cos(ang), 5.6 * sin(ang)))
        }
        glassArch.append((32.0, 5.6))
        wallBand(glassArch, 5.2, glassArch, 12.6, groundGlass, Self.curtain)
        box(hx: 1.975, hy: 4.99, z0: 0.0, z1: 9.2, podium, Self.floors, top: flatRoof, x0: 40.475, y0: 0.0)
        box(hx: 2.00, hy: 3.6, z0: 0.8, z1: 7.8, groundGlass, Self.curtain, x0: 40.45, y0: 0.0)

        if full {
            box(hx: 9.47, hy: 0.12, z0: 4.5, z1: 19.68, brick, Self.floors, top: flatRoof, x0: -5.63, y0: 20.01)
        }

        // 2. Stepped Department Store Podium (Shin Kong Mitsukoshi Taipei Station Store):
        //    - 10F lower podium (ways 644774205, 644774211, 644774215, 644774218: height = 46.56 m,
        //      x in [-42.45, 31.87], y in [-20.13, 20.13], 74.32 m × 40.26 m)
        //    - 13F middle stepped podium (ways 644774203..644774217: height = 63.20 m, stepped in to
        //      notched ring and side setback)
        //    - 16F upper stepped podium (way 644774201: height = 78.56 m on rear/sides, stepping to 71.0 m on North shoulders)
        let podX0: Float = -5.29
        let podHX: Float = 37.16
        let podHY: Float = 20.13

        let pod10Ring = Self.cornerRing(podHX - 0.16, podHY - 0.16, x0: podX0, y0: 0)
        wallBand(pod10Ring, 4.5, pod10Ring, 46.56, brick, Self.floors)
        cap(Self.cornerRing(podHX, podHY, x0: podX0, y0: 0), 46.56, flatRoof, Self.plain)

        // Alternating warm-beige stone bands on 1F-10F podium (proud of brick wall)
        let podBands: [Float] = full ? [8.5, 13.0, 17.5, 22.0, 26.5, 31.0, 35.5, 40.0, 44.8] : [14.0, 28.0, 44.8]
        for bz in podBands {
            let bRing = Self.cornerRing(podHX, podHY, x0: podX0, y0: 0)
            wallBand(bRing, bz, bRing, bz + 1.25, podium, Self.floors)
        }

        // 8F-10F wide horizontal blue-glass window bands on North podium face (seen in lead photo above golden logo)
        let windowBands: [Float] = full ? [32.6, 37.1, 41.6] : [33.5, 40.5]
        for wz in windowBands {
            box(hx: 0.18, hy: 13.2, z0: wz, z1: wz + 2.5, glass, Self.curtain, x0: 31.74, y0: 0.0)
        }
        // Lower central window strips (4F-6F) & Golden oval Shin Kong emblem (7F, z ~ 28.0..30.6 m)
        box(hx: 0.18, hy: 5.2, z0: 15.0, z1: 26.0, groundGlass, Self.curtain, x0: 31.74, y0: 0.0)
        box(hx: 0.22, hy: 2.5, z0: 28.0, z1: 30.6, ornament, glowing, x0: 31.76, y0: 0.0)

        // 11F-13F First Wedding-Cake Podium Setback (z = 46.56 .. 63.20 m, OSM ways 644774203..644774217)
        let pod13Ring = Self.notchedRing(podX0, 0, podHX - 2.95, podHY - 3.15, 3.0, 3.1)
        wallBand(pod13Ring, 46.56, pod13Ring, 63.20, brick, Self.floors)
        cap(Self.notchedRing(podX0, 0, podHX - 2.80, podHY - 3.00, 3.0, 3.1), 63.20, flatRoof, Self.plain)
        // Corner 13F shoulders
        box(hx: podHX - 2.95, hy: podHY - 0.15, z0: 46.56, z1: 54.8, rose, Self.floors, top: flatRoof, x0: podX0, y0: 0)
        box(hx: podHX - 0.15, hy: podHY - 3.15, z0: 46.56, z1: 54.8, rose, Self.floors, top: flatRoof, x0: podX0, y0: 0)
        if full {
            for bz: Float in [51.2, 56.5, 61.8] {
                let bRing = Self.notchedRing(podX0, 0, podHX - 2.80, podHY - 3.00, 3.0, 3.1)
                wallBand(bRing, bz, bRing, bz + 1.1, podium, Self.floors)
            }
            // 11F dark mechanical louver openings on North face (3 dark slots seen in lead photo)
            box(hx: 0.22, hy: 9.5, z0: 47.6, z1: 50.4, louver, Self.plain, x0: 28.92, y0: 0.0)
        }

        // 14F-16F Second Wedding-Cake Podium Setback (z = 63.20 .. 78.56 m, OSM way 644774201: height = 78.56 m)
        let pod16Ring = Self.notchedRing(-9.4, 0, 29.95, 13.90, 3.2, 3.0)
        wallBand(pod16Ring, 63.20, pod16Ring, 78.56, brick, Self.floors)
        cap(Self.notchedRing(-9.4, 0, 30.10, 14.05, 3.2, 3.0), 78.56, podiumRoof, Self.plain)
        // North 15F intermediate shoulder (z = 63.20 .. 71.5 m) flanking the 18F turret
        box(hx: 5.6, hy: 12.4, z0: 63.20, z1: 71.5, rose, Self.floors, top: flatRoof, x0: 21.5, y0: 0)
        if full {
            for bz: Float in [67.8, 72.8, 77.4] {
                let bRing = Self.notchedRing(-9.4, 0, 30.10, 14.05, 3.2, 3.0)
                wallBand(bRing, bz, bRing, bz + 1.0, podium, Self.floors)
            }
        }

        // 3. North 18-Level Stepped Front Turret (OSM way 644774185:
        //    building:levels = 18, height = 86.24 m, x in [17.43, 31.05], y in [-7.16, 7.17])
        let turretX0: Float = 24.24
        let turretRing = Self.notchedRing(turretX0, 0, 6.68, 7.04, 1.42, 1.35)
        wallBand(turretRing, 63.20, turretRing, 86.24, brick, Self.floors)
        cap(Self.notchedRing(turretX0, 0, 6.81, 7.16, 1.42, 1.35), 86.24, podiumRoof, Self.plain)
        box(hx: 0.22, hy: 4.8, z0: 65.5, z1: 83.0, glassTop, Self.curtain, x0: 30.82, y0: 0.0)
        if full {
            for tz: Float in [67.5, 72.5, 77.5, 84.8] {
                let tRing = Self.notchedRing(turretX0, 0, 6.81, 7.16, 1.42, 1.35)
                wallBand(tRing, tz, tRing, tz + 0.9, podium, Self.floors)
            }
        }

        // 4. Main Tower Shaft & Stepped Upper Setbacks (OSM ways 644774181..644774200):
        //    Tower center X0 = -5.55 m, Y0 = 0.0 m:
        //    - Outer tower span (ways 644774192 & 644774197 + 44F/46F/48F setbacks):
        //      x in [-28.65, 17.45] (46.10 m, hx = 23.05), y in [-17.05, 17.05] (34.10 m, hy = 17.05)
        //    - 44F corner setback top: z = 187.36 m (ways 644774188, 644774191, 644774195, 644774199)
        //    - 46F setback top: z = 195.68 m (ways 644774187, 644774189, 644774196, 644774198)
        //    - 48F N/S & E/W shoulders top: z = 203.36 m (ways 644774184, 644774192..644774194, 644774197, 644774200)
        //    - 50F main shaft core top: z = 211.04 m (way 644774181: 40.74 m × 34.11 m, x in [-25.88, 14.86])
        let tx0: Float = -5.55
        let shaftGlassRing = Self.notchedRing(tx0, 0, 22.75, 16.75, 3.0, 3.0)
        for (z0_s, z1_s): (Float, Float) in [(78.56, 105.76), (105.76, 132.96), (132.96, 160.16), (160.16, 187.36)] {
            wallBand(shaftGlassRing, z0_s, shaftGlassRing, z1_s, glass, towerGlass)
        }

        // Notched rose-granite corner pier clusters (44F ways -> 187.36 m, 46F ways -> 195.68 m, 48F ways -> 203.36 m)
        for sx: Float in [-1, 1] {
            for sy: Float in [-1, 1] {
                box(hx: 1.52, hy: 1.52, z0: 78.56, z1: 187.36, brick, Self.floors, top: flatRoof, x0: tx0 + sx * 21.53, y0: sy * 12.55)
                box(hx: 1.52, hy: 1.52, z0: 78.56, z1: 195.68, brick, Self.floors, top: flatRoof, x0: tx0 + sx * 21.53, y0: sy * 9.55)
                box(hx: 1.52, hy: 1.52, z0: 78.56, z1: 203.36, brick, Self.floors, top: flatRoof, x0: tx0 + sx * 18.53, y0: sy * 15.53)
            }
        }

        // Horizontal rose-granite + warm-stone spandrel bands wrapping all 4 sides of the main shaft (78.56 .. 187.36 m)
        let shaftStep: Float = full ? 4.35 : 13.05
        var z: Float = 81.8
        var idxBand = 0
        while z < 186.5 {
            let sRing = Self.notchedRing(tx0, 0, 23.05, 17.05, 3.0, 3.0)
            let col = (idxBand % 2 == 0) ? rose : podium
            wallBand(sRing, z, sRing, z + 1.35, col, Self.floors)
            z += shaftStep
            idxBand += 1
        }
        cap(Self.notchedRing(tx0, 0, 23.05, 17.05, 3.0, 3.0), 187.36, flatRoof, Self.plain)

        // Slender vertical window mullions (proud of glass 22.75/16.75, recessed behind horizontal spandrel bands 23.05/17.05)
        if full {
            for my: Float in [-4.0, 4.0] {
                for sx: Float in [-1, 1] {
                    box(hx: 0.14, hy: 0.34, z0: 78.56, z1: 203.36, brick, Self.floors, x0: tx0 + sx * 22.84, y0: my)
                }
            }
            for mx: Float in [-11.4, -5.7, 0.0, 5.7, 11.4] {
                for sy: Float in [-1, 1] {
                    box(hx: 0.34, hy: 0.14, z0: 78.56, z1: 211.04, brick, Self.floors, x0: tx0 + mx, y0: sy * 16.84)
                }
            }
        }

        // 46F & 48F Upper Setback Tiers (z = 187.36 .. 203.36 m, ways 644774192 & 644774197)
        let tier46Glass = Self.notchedRing(tx0, 0, 22.80, 15.35, 2.85, 4.40)
        let tier46Band = Self.notchedRing(tx0, 0, 23.05, 15.60, 2.85, 4.40)
        wallBand(tier46Glass, 187.36, tier46Glass, 195.68, glassTop, towerGlass)
        cap(tier46Band, 195.68, flatRoof, Self.plain)
        let t46Bands: [Float] = full ? [189.6, 192.4, 194.8] : [191.2, 194.8]
        for tz in t46Bands {
            wallBand(tier46Band, tz, tier46Band, tz + 0.85, brick, Self.floors)
        }

        let tier48Glass = Self.notchedRing(tx0, 0, 22.80, 13.95, 5.80, 6.20)
        let tier48Band = Self.notchedRing(tx0, 0, 23.05, 14.20, 5.80, 6.20)
        wallBand(tier48Glass, 195.68, tier48Glass, 203.36, glassTop, towerGlass)
        cap(tier48Band, 203.36, flatRoof, Self.plain)
        let t48Bands: [Float] = full ? [197.8, 200.4, 202.5] : [199.4, 202.5]
        for tz in t48Bands {
            wallBand(tier48Band, tz, tier48Band, tz + 0.85, brick, Self.floors)
        }

        // 50F Main Tower Top Core (OSM way 644774181: height = 211.04 m,
        // x in [-25.88, 14.86] -> width 40.74 m (hx = 20.37), y in [-17.05, 17.05] -> depth 34.10 m)
        let tier50Ring = Self.notchedRing(tx0, 0, 20.37, 14.20, 4.20, 3.80)
        wallBand(tier50Ring, 203.36, tier50Ring, 211.04, brick, Self.floors)
        cap(tier50Ring, 211.04, podiumRoof, Self.plain)
        box(hx: 15.8, hy: 10.0, z0: 204.6, z1: 209.4, glassTop, towerGlass, x0: tx0, y0: 0.0)
        if full {
            box(hx: 16.0, hy: 10.2, z0: 206.4, z1: 207.8, louver, Self.plain, x0: tx0, y0: 0.0)
        }

        // 5. Stepped Art-Deco Ziggurat Crown (OSM way 644774173 height = 214.88 m & way 644774171 height = 237.67 m):
        let collar51Ring = Self.notchedRing(tx0, 0, 11.55, 11.56, 2.4, 2.4)
        wallBand(collar51Ring, 211.04, collar51Ring, 214.88, brick, floodlit)
        cap(Self.notchedRing(tx0, 0, 11.69, 11.70, 2.4, 2.4), 214.88, flatRoof, floodlit)

        let drumRing = Self.notchedRing(tx0, 0, 9.28, 9.38, 2.0, 2.0)
        wallBand(drumRing, 214.88, drumRing, 222.0, brick, floodlit)
        cap(Self.notchedRing(tx0, 0, 9.42, 9.52, 2.0, 2.0), 222.0, flatRoof, floodlit)

        let pentRing0 = Self.notchedRing(tx0, 0, 6.90, 7.06, 1.6, 1.6)
        wallBand(pentRing0, 222.0, pentRing0, 231.0, brick, floodlit)
        cap(Self.notchedRing(tx0, 0, 7.02, 7.18, 1.6, 1.6), 231.0, flatRoof, floodlit)

        let pentRing1 = Self.notchedRing(tx0, 0, 4.98, 5.08, 1.2, 1.2)
        wallBand(pentRing1, 231.0, pentRing1, 237.67, brick, floodlit)
        cap(Self.notchedRing(tx0, 0, 5.10, 5.20, 1.2, 1.2), 237.67, flatRoof, floodlit)

        if full {
            let crownBands: [(cz: Float, hx: Float, hy: Float, n: Float)] = [
                (213.5, 11.69, 11.70, 2.4),
                (218.2, 9.42, 9.52, 2.0),
                (220.9, 9.42, 9.52, 2.0),
                (226.2, 7.02, 7.18, 1.6),
                (229.8, 7.02, 7.18, 1.6),
                (234.2, 5.10, 5.20, 1.2),
                (236.8, 5.10, 5.20, 1.2),
            ]
            for (cz, hx_c, hy_c, n_c) in crownBands {
                let cRing = Self.notchedRing(tx0, 0, hx_c, hy_c, n_c, n_c)
                wallBand(cRing, cz, cRing, cz + 0.70, podium, floodlit)
            }
            // Dark observation/mechanical window slots on the crown tiers (seen in both real photos)
            box(hx: 4.6, hy: 9.50, z0: 216.0, z1: 218.0, louver, Self.plain, x0: tx0, y0: 0.0)
            box(hx: 9.40, hy: 4.6, z0: 216.0, z1: 218.0, louver, Self.plain, x0: tx0, y0: 0.0)
            box(hx: 3.4, hy: 7.16, z0: 223.8, z1: 225.8, louver, Self.plain, x0: tx0, y0: 0.0)
            box(hx: 7.00, hy: 3.4, z0: 223.8, z1: 225.8, louver, Self.plain, x0: tx0, y0: 0.0)
        }

        // 6. Pyramidal Cap & Lightning Spire (z = 237.67 .. 244.15 m, OSM way 204711206 height = 244.15 m)
        let capBase = Self.chamferRing(tx0, 0, 3.80, 3.88, 0.70)
        let capTop = Self.chamferRing(tx0, 0, 1.15, 1.18, 0.25)
        wallBand(capBase, 237.67, capTop, 241.2, crownSlope, floodlit)
        cap(capTop, 241.2, trim, floodlit)

        let s0 = Self.chamferRing(tx0, 0, 0.45, 0.45, 0.12)
        let s1 = Self.chamferRing(tx0, 0, 0.22, 0.22, 0.06)
        let s2 = Self.chamferRing(tx0, 0, 0.12, 0.12, 0.03)
        wallBand(s0, 241.2, s1, 243.4, spire, floodlit)
        wallBand(s1, 243.4, s2, 244.15, ornament, glowing)
        cap(s2, 244.15, vermilion, glowing)
    }

    // MARK: - Decision 581: Changhua Roundhouse

    /// Decision 581: Changhua Roundhouse (OSM way 220285047: 85.03 m × 49.79 m,
    /// railway = roundhouse, building = garages, building:levels = 1; turntable
    /// way 220285048; 12 radial stall tracks ways 307329549..307329565 &
    /// 966441326, ODbL), centered at the bounding-box midpoint (24.0858608°N,
    /// 120.5401168°E), rotation 0°. Rebuilt procedurally from the reference
    /// proportions (`historic-buildings-v2/changhua-roundhouse/model.json` and
    /// `tw3d-reference-clean/source/js/cities/changhua/landmarks/catalog.json`):
    /// 12 radiating fan stalls with stepped rear walls, 13 concrete portal
    /// piers with corner haunches, twin blue-framed transom windows over each
    /// open stall doorway, sloped radial roof with raised clerestory monitor
    /// roof (8.85 m), 12 cylindrical roof smokejacks with rain caps (10.28 m),
    /// east and west brick service wings, curved wooden pedestrian boardwalk,
    /// and 12 radial stall and approach tracks with inspection pits meeting
    /// Decision 441's turntable rim in the south courtyard.
    mutating func changhuaRoundhouse() {
        let stone = colour("stone")
        let podium = colour("podium")
        let hallWall = colour("hallWall")
        let brick = colour("brick")
        let gateStone = colour("gateStone")
        let trim = colour("trim")
        let slate = colour("slate")
        let crownRoof = colour("crownRoof")
        let flatRoof = colour("flatRoof")
        let glass = colour("glass")
        let blueRidge = colour("blueRidge")
        let doorway = colour("doorway")
        let column = colour("column")
        let spire = colour("spire")
        let ornament = colour("ornament")
        let floodlit = Map3DVertex.floodlit

        // Focal center of the 12 radiating stalls (OSM turntable way 220285048
        // relative to way 220285047's bounding-box midpoint) and Decision 441's
        // turntable center in the courtyard (`Map3DDepotFacilities.turntablePlace`).
        let fx: Float = 6.64, fy: Float = -32.91
        let ttx: Float = 3.47, tty: Float = -19.53

        func polar(_ r: Float, _ deg: Float) -> P2 {
            let rad = deg * .pi / 180
            return (fx + r * cos(rad), fy + r * sin(rad))
        }

        func octRing(_ cx: Float, _ cy: Float, _ r: Float) -> [P2] {
            (0..<8).map { k in
                let a = Float(k) * .pi / 4
                return (cx + r * cos(a), cy + r * sin(a))
            }
        }

        func orientedRect(_ p0: P2, _ p1: P2, _ halfW: Float) -> [P2] {
            let dx = p1.x - p0.x, dy = p1.y - p0.y
            let len = max(0.001, (dx * dx + dy * dy).squareRoot())
            let nx = -dy / len * halfW, ny = dx / len * halfW
            return [
                (p0.x - nx, p0.y - ny),
                (p1.x - nx, p1.y - ny),
                (p1.x + nx, p1.y + ny),
                (p0.x + nx, p0.y + ny),
            ]
        }

        // 13 pier angles (degrees around (fx, fy)) bounding Stalls 1..12 (East to West),
        // aligned with the stepped outer rear wall of OSM way 220285047:
        let stallBounds: [Float] = [
            55.65, 64.10, 72.55, 81.00, 91.72,
            98.42, 105.12, 111.82, 118.52,
            123.72, 134.98, 146.24, 157.50,
        ]
        let stallRIn: [Float] = [
            28.60, 28.65, 28.85, 28.95,
            29.10, 29.20, 29.40, 29.55,
            29.50, 29.65, 29.95, 30.35,
        ]
        // Stepped outer rear wall radii from OSM way 220285047:
        //   Stalls 1–4 (v12..v16): ~52.4 m
        //   Stalls 5–8 (v07..v11): ~58.4 m (reaching y = +24.895 m)
        //   Stall 9 (v05..v06):    ~55.9 m
        //   Stalls 10–12 (v00..v04): ~52.9 m (reaching x = -42.515 m)
        let stallROut: [Float] = [
            52.20, 52.35, 52.48, 52.60,
            57.76, 58.44, 58.65, 58.40,
            55.90,
            52.72, 52.90, 53.20,
        ]

        // 1. 12 Radiating Fan Stalls (Stalls 1..12)
        let rMid: Float = 39.50
        for i in 0..<12 {
            let a0 = stallBounds[i], a1 = stallBounds[i + 1]
            let aMid = 0.5 * (a0 + a1)
            let rIn = stallRIn[i], rOut = stallROut[i]

            let fe = polar(rIn, a0), be = polar(rOut, a0)
            let bw = polar(rOut, a1), fw = polar(rIn, a1)
            let feIn = polar(rIn + 0.35, a0), fwIn = polar(rIn + 0.35, a1)
            let lowerRing: [P2] = [feIn, be, bw, fwIn]
            let upperRing: [P2] = [fe, be, bw, fw]

            // Plinth base (z = 0.00 .. 0.46 m), lower brick dado (0.46 .. 1.80 m) & mid wall (1.80 .. 4.55 m)
            wallBand(lowerRing, 0.00, lowerRing, 0.46, gateStone, Self.plain)
            wallBand(lowerRing, 0.46, lowerRing, 1.80, brick, Self.floors)
            wallBand(lowerRing, 1.80, lowerRing, 4.55, hallWall, Self.floors)

            // Dark stall doorway opening at the front entrance arc (z = 0.00 .. 4.55 m)
            let doorRing: [P2] = [fe, feIn, fwIn, fw]
            wallBand(doorRing, 0.00, doorRing, 4.55, doorway, Self.plain)

            // Upper spandrel wall above doorway (z = 4.55 .. 6.80 m)
            wallBand(upperRing, 4.55, upperRing, 6.80, hallWall, Self.floors)

            // Sloped radial roof in two pitches (rIn at 6.80 m -> rMid at 8.00 m -> rOut at 6.80 m)
            let me = polar(rMid, a0), mw = polar(rMid, a1)
            let frontRoof: [P2] = [fe, me, mw, fw]
            let rearRoof: [P2] = [me, be, bw, mw]
            band(frontRoof, [6.60, 6.60, 6.60, 6.60], frontRoof, [6.80, 8.00, 8.00, 6.80], hallWall, Self.floors)
            band(rearRoof, [6.60, 6.60, 6.60, 6.60], rearRoof, [8.00, 6.80, 6.80, 8.00], hallWall, Self.floors)
            quad((fe.x, fe.y, 6.80), (me.x, me.y, 8.00), (mw.x, mw.y, 8.00), (fw.x, fw.y, 6.80),
                 slate, Self.tiles, [fe, me, mw, fw])
            quad((me.x, me.y, 8.00), (be.x, be.y, 6.80), (bw.x, bw.y, 6.80), (mw.x, mw.y, 8.00),
                 slate, Self.tiles, [me, be, bw, mw])

            // Front continuous concrete lintel (z = 4.50 .. 4.78 m) & top cornice (z = 6.54 .. 7.06 m)
            let cRing: [P2] = [
                polar(rIn - 0.24, a0),
                polar(rIn + 0.12, a0),
                polar(rIn + 0.12, a1),
                polar(rIn - 0.24, a1),
            ]
            wallBand(cRing, 4.50, cRing, 4.78, stone, Self.floors)
            wallBand(cRing, 6.54, cRing, 7.06, trim, floodlit)
            cap(cRing, 7.06, trim, floodlit)

            // Twin blue-framed transom windows above each doorway (z = 4.82 .. 6.40 m)
            if full {
                for (wt0, wt1): (Float, Float) in [(0.16, 0.46), (0.54, 0.84)] {
                    let wa0 = a0 + wt0 * (a1 - a0), wa1 = a0 + wt1 * (a1 - a0)
                    let fRing: [P2] = [
                        polar(rIn - 0.16, wa0),
                        polar(rIn + 0.02, wa0),
                        polar(rIn + 0.02, wa1),
                        polar(rIn - 0.16, wa1),
                    ]
                    wallBand(fRing, 4.82, fRing, 6.40, blueRidge, Self.floors)
                    let gRing: [P2] = [
                        polar(rIn - 0.22, wa0 + 0.18),
                        polar(rIn - 0.02, wa0 + 0.18),
                        polar(rIn - 0.02, wa1 - 0.18),
                        polar(rIn - 0.22, wa1 - 0.18),
                    ]
                    wallBand(gRing, 4.92, gRing, 6.30, glass, Self.curtain)
                }
                // Portal corner haunches / brackets at the top corners of each doorway (z = 3.80 .. 4.50 m)
                for (ha0, ha1): (Float, Float) in [(a0 + 0.06 * (a1 - a0), a0 + 0.20 * (a1 - a0)),
                                                   (a1 - 0.20 * (a1 - a0), a1 - 0.06 * (a1 - a0))] {
                    let hRing: [P2] = [
                        polar(rIn - 0.18, ha0),
                        polar(rIn + 0.35, ha0),
                        polar(rIn + 0.35, ha1),
                        polar(rIn - 0.18, ha1),
                    ]
                    wallBand(hRing, 3.80, hRing, 4.50, stone, Self.floors)
                }
                // Stall number plate centered over doorway lintel (z = 4.52 .. 4.78 m)
                let npRing: [P2] = [
                    polar(rIn - 0.28, aMid - 0.55),
                    polar(rIn - 0.05, aMid - 0.55),
                    polar(rIn - 0.05, aMid + 0.55),
                    polar(rIn - 0.28, aMid + 0.55),
                ]
                wallBand(npRing, 4.52, npRing, 4.78, ornament, floodlit)
            } else {
                let wa0 = a0 + 0.18 * (a1 - a0), wa1 = a0 + 0.82 * (a1 - a0)
                let gRing: [P2] = [
                    polar(rIn - 0.18, wa0),
                    polar(rIn + 0.02, wa0),
                    polar(rIn + 0.02, wa1),
                    polar(rIn - 0.18, wa1),
                ]
                wallBand(gRing, 4.90, gRing, 6.30, glass, Self.curtain)
            }

            // Stepped rear outer wall concrete tie-beams & multi-pane industrial windows
            if full {
                let rearBeam: [P2] = [
                    polar(rOut - 0.22, a0),
                    polar(rOut - 0.02, a0),
                    polar(rOut - 0.02, a1),
                    polar(rOut - 0.22, a1),
                ]
                wallBand(rearBeam, 1.72, rearBeam, 1.88, podium, Self.floors)
                wallBand(rearBeam, 3.92, rearBeam, 4.08, podium, Self.floors)
                wallBand(rearBeam, 6.45, rearBeam, 6.80, podium, Self.floors)
                for (rwt0, rwt1): (Float, Float) in [(0.16, 0.45), (0.55, 0.84)] {
                    let rwa0 = a0 + rwt0 * (a1 - a0), rwa1 = a0 + rwt1 * (a1 - a0)
                    let rwRing: [P2] = [
                        polar(rOut - 0.18, rwa0),
                        polar(rOut - 0.01, rwa0),
                        polar(rOut - 0.01, rwa1),
                        polar(rOut - 0.18, rwa1),
                    ]
                    wallBand(rwRing, 2.00, rwRing, 5.80, glass, Self.curtain)
                }
            }

            // Raised Clerestory Monitor Roof (r = 37.80 .. 42.60 m, z = 7.65 .. 8.85 m)
            let monRing: [P2] = [
                polar(37.80, a0),
                polar(42.60, a0),
                polar(42.60, a1),
                polar(37.80, a1),
            ]
            wallBand(monRing, 7.65, monRing, 8.85, crownRoof, Self.floors)
            cap(monRing, 8.85, crownRoof, Self.tiles)
            if full {
                let ma0 = a0 + 0.12 * (a1 - a0), ma1 = a1 - 0.12 * (a1 - a0)
                let mfRing: [P2] = [
                    polar(37.68, ma0),
                    polar(37.90, ma0),
                    polar(37.90, ma1),
                    polar(37.68, ma1),
                ]
                let mbRing: [P2] = [
                    polar(42.50, ma0),
                    polar(42.72, ma0),
                    polar(42.72, ma1),
                    polar(42.50, ma1),
                ]
                wallBand(mfRing, 8.05, mfRing, 8.68, glass, Self.curtain)
                wallBand(mbRing, 8.05, mbRing, 8.68, glass, Self.curtain)
            }

            // Cylindrical Smokejack / Chimney on each stall roof (r = 34.20 m, z = 7.45 .. 10.28 m)
            let (cx, cy) = polar(34.20, aMid)
            if full {
                let cBase = octRing(cx, cy, 0.54)
                let cShaft = octRing(cx, cy, 0.39)
                let cNeck = octRing(cx, cy, 0.46)
                let cCap = octRing(cx, cy, 0.74)
                wallBand(cBase, 7.45, cBase, 8.20, podium, floodlit)
                cap(cBase, 8.20, podium, floodlit)
                wallBand(cShaft, 8.20, cShaft, 9.92, column, floodlit)
                wallBand(cNeck, 9.92, cCap, 10.12, slate, floodlit)
                wallBand(cCap, 10.12, cCap, 10.28, doorway, floodlit)
                cap(cCap, 10.28, doorway, floodlit)
            } else {
                let cBox: [P2] = [(cx - 0.45, cy - 0.45), (cx + 0.45, cy - 0.45), (cx + 0.45, cy + 0.45), (cx - 0.45, cy + 0.45)]
                wallBand(cBox, 7.50, cBox, 10.28, column, floodlit)
                cap(cBox, 10.28, doorway, floodlit)
            }
        }

        // 2. 13 Front Concrete Portal Piers between stalls (j = 0..12)
        for (j, pDeg) in stallBounds.enumerated() {
            let rInP = stallRIn[min(j, 11)]
            let pRing: [P2] = [
                polar(rInP - 0.34, pDeg - 0.52),
                polar(rInP + 0.45, pDeg - 0.52),
                polar(rInP + 0.45, pDeg + 0.52),
                polar(rInP - 0.34, pDeg + 0.52),
            ]
            wallBand(pRing, 0.00, pRing, 7.06, stone, floodlit)
            cap(pRing, 7.06, trim, floodlit)
            if full {
                let rOutP = max(stallROut[max(0, j - 1)], stallROut[min(11, j)])
                let ribRing: [P2] = [
                    polar(rInP, pDeg - 0.16),
                    polar(rOutP - 0.12, pDeg - 0.16),
                    polar(rOutP - 0.12, pDeg + 0.16),
                    polar(rInP, pDeg + 0.16),
                ]
                wallBand(ribRing, 6.80, ribRing, 8.06, slate, Self.tiles)
                cap(ribRing, 8.06, slate, Self.tiles)
            }
        }

        // 3. East Service Annex Wing (OSM way 220285047 vertices v17..v21, reaching x = +42.515 m)
        let eastRing: [P2] = [
            polar(26.18, 54.55),
            polar(27.32, 41.31),
            (42.515, 8.84),
            polar(54.22, 55.65),
            polar(28.60, 55.65),
        ]
        wallBand(eastRing, 0.00, eastRing, 0.46, gateStone, Self.plain)
        wallBand(eastRing, 0.46, eastRing, 5.80, brick, Self.floors)
        wallBand(eastRing, 5.80, eastRing, 6.20, podium, Self.floors)
        cap(eastRing, 6.20, flatRoof, Self.tiles)
        if full {
            let p19 = polar(27.32, 41.31), p18: P2 = (42.515, 8.84)
            for (t0, t1): (Float, Float) in [(0.15, 0.36), (0.44, 0.65), (0.72, 0.88)] {
                let wa: P2 = (p19.x + t0 * (p18.x - p19.x), p19.y + t0 * (p18.y - p19.y))
                let wb: P2 = (p19.x + t1 * (p18.x - p19.x), p19.y + t1 * (p18.y - p19.y))
                let wRing = orientedRect(wa, wb, 0.14)
                wallBand(wRing, 1.90, wRing, 4.90, glass, Self.curtain)
            }
        }

        // 4. West Workshop Annex Wing (OSM way 220285047 vertices v00, v38..v41, reaching x = -42.515 m, y = -24.895 m)
        let westRing: [P2] = [
            polar(30.35, 157.50),
            (-42.515, -12.54),
            polar(41.14, 159.26),
            polar(41.46, 163.62),
            (-23.84, -24.895),
        ]
        wallBand(westRing, 0.00, westRing, 0.46, gateStone, Self.plain)
        wallBand(westRing, 0.46, westRing, 5.60, brick, Self.floors)
        wallBand(westRing, 5.60, westRing, 6.00, podium, Self.floors)
        cap(westRing, 6.00, flatRoof, Self.tiles)
        if full {
            let p38 = polar(30.35, 157.50), p00: P2 = (-42.515, -12.54)
            for (t0, t1): (Float, Float) in [(0.18, 0.44), (0.54, 0.78)] {
                let wa: P2 = (p38.x + t0 * (p00.x - p38.x), p38.y + t0 * (p00.y - p38.y))
                let wb: P2 = (p38.x + t1 * (p00.x - p38.x), p38.y + t1 * (p00.y - p38.y))
                let wRing = orientedRect(wa, wb, 0.14)
                wallBand(wRing, 1.90, wRing, 4.80, glass, Self.curtain)
            }
        }

        // 5. 12 Radial Stall & Approach Tracks (ways 307329549..307329565 & 966441326,
        //    connecting Decision 441's turntable rim r = 13.05 m around (3.47, -19.53)
        //    through each stall doorway to the back of the stall):
        for i in 0..<12 {
            let a0 = stallBounds[i], a1 = stallBounds[i + 1]
            let aMid = 0.5 * (a0 + a1)
            let rIn = stallRIn[i], rOut = stallROut[i]

            let doorPt = polar(rIn, aMid)
            let backPt = polar(rOut - 2.00, aMid)
            let dxT = doorPt.x - ttx, dyT = doorPt.y - tty
            let lenT = max(0.001, (dxT * dxT + dyT * dyT).squareRoot())
            let rimPt: P2 = (ttx + dxT / lenT * 13.05, tty + dyT / lenT * 13.05)

            for (segA, segB) in [(rimPt, doorPt), (doorPt, backPt)] {
                let bedRing = orientedRect(segA, segB, 0.96)
                wallBand(bedRing, 0.00, bedRing, 0.08, gateStone, Self.plain)
                cap(bedRing, 0.08, gateStone, Self.plain)
            }

            if full {
                // Sunken inspection pit between the rails inside each stall
                let pitA = polar(rIn + 0.40, aMid), pitB = polar(rOut - 3.20, aMid)
                let pitRing = orientedRect(pitA, pitB, 0.38)
                wallBand(pitRing, 0.00, pitRing, 0.11, doorway, Self.plain)
                cap(pitRing, 0.11, doorway, Self.plain)

                // Two steel rails (1.067 m narrow gauge -> ±0.5335 m offset)
                for (segA, segB) in [(rimPt, doorPt), (doorPt, backPt)] {
                    let sdx = segB.x - segA.x, sdy = segB.y - segA.y
                    let slen = max(0.001, (sdx * sdx + sdy * sdy).squareRoot())
                    let snx = -sdy / slen, sny = sdx / slen
                    for side: Float in [-0.5335, 0.5335] {
                        let rp0: P2 = (segA.x + snx * side, segA.y + sny * side)
                        let rp1: P2 = (segB.x + snx * side, segB.y + sny * side)
                        let rRing = orientedRect(rp0, rp1, 0.055)
                        wallBand(rRing, 0.08, rRing, 0.19, spire, Self.plain)
                        cap(rRing, 0.19, spire, Self.plain)
                    }
                }

                // Wooden cross-sleepers along the open courtyard approach
                for st: Float in [0.18, 0.38, 0.58, 0.88] {
                    let sx = rimPt.x + st * (doorPt.x - rimPt.x)
                    let sy = rimPt.y + st * (doorPt.y - rimPt.y)
                    let ux = dxT / lenT * 0.13, uy = dyT / lenT * 0.13
                    let sRing = orientedRect((sx - ux, sy - uy), (sx + ux, sy + uy), 0.88)
                    wallBand(sRing, 0.08, sRing, 0.13, brick, Self.plain)
                    cap(sRing, 0.13, brick, Self.plain)
                }
            }
        }

        // 6. Curved Wooden Pedestrian Boardwalk across the 12 approach tracks
        for k in 0..<12 {
            let ba0 = stallBounds[k], ba1 = stallBounds[k + 1]
            let rBw0 = stallRIn[k] - 2.30, rBw1 = stallRIn[k] - 1.05
            let bwRing: [P2] = [
                polar(rBw0, ba0),
                polar(rBw1, ba0),
                polar(rBw1, ba1),
                polar(rBw0, ba1),
            ]
            wallBand(bwRing, 0.00, bwRing, 0.15, brick, Self.plain)
            cap(bwRing, 0.15, brick, Self.plain)
            if full {
                let curbRing: [P2] = [
                    polar(rBw0 - 0.12, ba0),
                    polar(rBw0 + 0.08, ba0),
                    polar(rBw0 + 0.08, ba1),
                    polar(rBw0 - 0.12, ba1),
                ]
                wallBand(curbRing, 0.00, curbRing, 0.18, ornament, floodlit)
                cap(curbRing, 0.18, ornament, floodlit)
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
