import Foundation

// Decision 457: central Taipei's palace-style landmarks and its old city
// gates in the model look, where they stand. Plans from OpenStreetMap (ODbL;
// the ways in decision 457's table), heights from OSM where it has them and
// otherwise from the owner's reference models (`blender-buildings-v1`) and
// the official figures they cite. The way the roofs are built (eaves out,
// concave slopes, corners turned up, a double eave's skirt, the hip-and-gable)
// follows the owner's `Taipei_Central_3D_Clean/js/landmarks.js` (slop-taipei,
// MIT, Copyright (c) 2026 Mr.doob), rebuilt here with the game's own parts
// and colours; the roof itself is `Map3DChineseRoof.swift`.

extension LandmarkMesh {
    /// Square columns `size` thick every `step` round a rectangle of half
    /// sides `hx`, `hy`, from `z0` to `z1`; close by only.
    mutating func colonnade(_ hx: Float, _ hy: Float, _ z0: Float, _ z1: Float, step: Float, size: Float, _ color: UInt32) {
        guard full else { return }
        let corners: [P2] = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
        let w = size / 2
        for c in 0..<4 {
            let a = corners[c], b = corners[(c + 1) % 4]
            let n = max(1, Int((Self.distance(a, b) / step).rounded()))
            for s in 0..<n {
                let t = Float(s) / Float(n)
                let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
                let ring: [P2] = [(x - w, y - w), (x + w, y - w), (x + w, y + w), (x - w, y + w)]
                wallBand(ring, z0, ring, z1, color, Self.plain)
            }
        }
    }

    /// A block from `x0` to `x1` and `y0` to `y1`, from `zSpring` to `zTop`,
    /// with a round arch cut from its foot (a gate's passage over its
    /// piers): its two faces, the arch's underside and its top.
    mutating func archBlock(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, spring zs: Float, top zt: Float, _ color: UInt32) {
        let r = (x1 - x0) / 2, xm = (x0 + x1) / 2
        let n = full ? 8 : 4
        let arch: [P2] = (0...n).map { k in
            let a = Float.pi * (1 - Float(k) / Float(n))
            return (xm + r * cos(a), zs + r * sin(a))
        }
        for k in 0..<n {
            let a = arch[k], b = arch[k + 1]
            // The front face (y0), the back face (y1) and the underside.
            quad((a.x, y0, a.y), (b.x, y0, b.y), (b.x, y0, zt), (a.x, y0, zt), color, Self.plain)
            quad((b.x, y1, b.y), (a.x, y1, a.y), (a.x, y1, zt), (b.x, y1, zt), color, Self.plain)
            quad((a.x, y1, a.y), (b.x, y1, b.y), (b.x, y0, b.y), (a.x, y0, a.y), color, Self.plain)
        }
        cap([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], zt, color, Self.plain)
    }

    /// A gate's base: a stone block of half sides `hx`, `hy`, `height` high,
    /// a passage `width` wide through it along y, its arch springing at
    /// `spring`.
    mutating func gateBase(_ hx: Float, _ hy: Float, height: Float, passage width: Float, spring: Float, _ color: UInt32) {
        let w = width / 2
        box(-hx, -hy, 0, -w, hy, height, color, Self.plain)
        box(w, -hy, 0, hx, hy, height, color, Self.plain)
        archBlock(-w, w, -hy, hy, spring: spring, top: height, color)
    }

    /// Steps up the front (-y) of a platform: `width` wide, from the ground
    /// at `y0` up to `height` at `y1`; close by in stairs, from afar a slope.
    mutating func stairs(width: Float, from y0: Float, to y1: Float, height: Float, _ color: UInt32) {
        let w = width / 2
        if full {
            let n = 10
            for k in 0..<n {
                let ya = y0 + (y1 - y0) * Float(k) / Float(n)
                box(-w, ya, 0, w, y1, height * Float(k + 1) / Float(n), color, Self.plain)
            }
        } else {
            quad((-w, y0, 0), (w, y0, 0), (w, y1, height), (-w, y1, height), color, Self.plain)
            tri((w, y0, 0), (w, y1, 0), (w, y1, height), color, Self.plain)
            tri((-w, y1, 0), (-w, y0, 0), (-w, y1, height), color, Self.plain)
        }
    }

    /// A regular `sides`-gon of circumradius `r` round (`cx`, `cy`),
    /// counter-clockwise, its first corner at `phase`.
    static func polygon(_ sides: Int, _ r: Float, _ cx: Float = 0, _ cy: Float = 0, phase: Float = 0) -> [P2] {
        (0..<sides).map { k in
            let a = phase + 2 * .pi * Float(k) / Float(sides)
            return (cx + r * cos(a), cy + r * sin(a))
        }
    }

    /// A pyramid roof over the ring `ring` from `z0` to an apex at `z1`
    /// over (`cx`, `cy`), in `steps` concave rings.
    mutating func pyramidRoof(_ ring: [P2], _ cx: Float, _ cy: Float, from z0: Float, to z1: Float, steps: Int, _ color: UInt32) {
        var previous = ring, zPrevious = z0
        for s in 1...steps {
            let t = Float(s) / Float(steps)
            let k = 1 - t * 0.97
            let next = ring.map { (x: cx + ($0.x - cx) * k, y: cy + ($0.y - cy) * k) }
            let z = z0 + (z1 - z0) * powf(t, 1.5)
            wallBand(previous, zPrevious, next, z, color, Self.tiles)
            previous = next
            zPrevious = z
        }
        cap(previous, zPrevious, color, Self.plain)
    }

    // MARK: Liberty Square

    /// Chiang Kai-shek Memorial Hall (OSM way 1052759757, its lowest
    /// terrace and the stairway in front): three white terraces to the
    /// hall's floor at 14.5 m and the white hall to 38.5 m (OSM's parts,
    /// ways 1052759756 and 1052759759), the great arched door, an
    /// octagonal double roof of blue tile, a short gold finial to 70 m (the
    /// memorial hall's own figure); the stairway down the front (-y)
    /// toward Liberty Square's gate.
    mutating func chiangKaiShekMemorialHall() {
        let stone = colour("stone"), hall = colour("hallWhite"), blue = colour("blueTile"), ridge = colour("blueRidge")
        let cy: Float = 11.9
        // Terraces: OSM's 124.4 m by 123.6 m, then two inset.
        for (half, z0, z1) in [(Float(61.9), Float(0), Float(4)), (47, 4, 9.5), (36, 9.5, 14.5)] {
            box(-min(half, 62.2), cy - half, z0, min(half, 62.2), cy + half, z1, stone, Self.plain, top: colour("plinth"))
        }
        // The stairway (OSM: 40 m wide, 23.7 m out from the terrace), up to
        // the hall's floor.
        stairs(width: 40, from: -73.7, to: cy - 36, height: 14.5, stone)
        // The hall: white walls, the arched doorway, a blue band.
        let h: Float = 25
        box(-h, cy - h, 14.5, h, cy + h, 38.5, hall, Self.plain)
        let door = colour("doorway"), face = cy - h - 0.15
        box(-7, face, 14.5, 7, cy - h, 28, door, Self.plain)
        let arch = full ? 6 : 2
        for k in 0..<arch {
            let a0 = Float.pi * Float(k) / Float(arch), a1 = Float.pi * Float(k + 1) / Float(arch)
            tri((0, face, 28), (7 * cos(a0), face, 28 + 7 * sin(a0)), (7 * cos(a1), face, 28 + 7 * sin(a1)), door, Self.plain)
        }
        if full {
            box(-h - 0.4, cy - h - 0.4, 35.5, h + 0.4, cy + h + 0.4, 38.5, colour("blueRidge"), Self.plain)
        }
        // The octagonal roofs: a lower eave out over the hall's walls, a
        // white drum, the upper roof to its peak, the finial.
        let sides = 8
        let phase = Float.pi / 8
        let lowOut = Self.polygon(sides, 38, 0, cy, phase: phase), lowIn = Self.polygon(sides, 27.5, 0, cy, phase: phase)
        wallBand(lowOut, 37.9, lowOut, 38.5, ridge, Self.plain)
        band(lowOut, [Float](repeating: 38.5, count: sides), lowIn, [Float](repeating: 43.5, count: sides), blue, Self.tiles)
        cap(lowOut.reversed(), 37.9, colour("blueRidge"), Self.plain)
        let drum = Self.polygon(sides, 25.5, 0, cy, phase: phase)
        wallBand(drum, 43.5, drum, 48.5, hall, Self.plain)
        cap(lowIn, 43.5, blue, Self.plain)
        let upOut = Self.polygon(sides, 31, 0, cy, phase: phase)
        wallBand(upOut, 48, upOut, 48.5, ridge, Self.plain)
        cap(upOut.reversed(), 48, ridge, Self.plain)
        pyramidRoof(upOut, 0, cy, from: 48.5, to: 66, steps: full ? 5 : 3, blue)
        // The finial: a short gold spire to 70 m.
        let foot = Self.polygon(full ? 8 : 4, 1.6, 0, cy, phase: phase), tip = Self.polygon(full ? 8 : 4, 0.25, 0, cy, phase: phase)
        wallBand(foot, 65.9, tip, 70, colour("finial"), Self.plain)
        cap(tip, 70, colour("finial"), Self.plain)
        if full {
            for (r, z) in [(Float(31), Float(48.5)), (38, 38.5)] {
                for p in Self.polygon(8, r, 0, cy, phase: phase) {
                    box(p.x - 0.6, p.y - 0.6, z, p.x + 0.6, p.y + 0.6, z + 1.4, ridge, Self.plain)
                }
            }
        }
    }

    /// Liberty Square's gate (OSM way 1052759782, 74.7 m by 17 m): a white
    /// wall pierced by five arches, the middle one highest, each under a
    /// blue roof, the middle's ridge 30 m high (the owner's reference
    /// model's height).
    mutating func libertySquareGate() {
        let stone = colour("stone"), blue = colour("blueTile"), ridge = colour("blueRidge")
        let hy: Float = 8.5, pier: Float = 3
        let bays: [Float] = [10.1, 11.5, 13.5, 11.5, 10.1]
        let springs: [Float] = [6, 7.5, 10, 7.5, 6]
        let walls: [Float] = [14.5, 18.5, 24, 18.5, 14.5]
        let rises: [Float] = [3.8, 4.5, 6, 4.5, 3.8]
        var x: Float = -37.35
        var bayStart: [Float] = []
        for k in 0..<5 {
            let left = k == 0 ? walls[0] : max(walls[k - 1], walls[k])
            box(x, -hy, 0, x + pier, hy, left, stone, Self.plain)
            x += pier
            bayStart.append(x)
            x += bays[k]
        }
        box(x, -hy, 0, x + pier, hy, walls[4], stone, Self.plain)
        for k in 0..<5 {
            let x0 = bayStart[k], x1 = x0 + bays[k]
            archBlock(x0, x1, -hy, hy, spring: springs[k], top: walls[k], stone)
            // The roof over the bay and its piers, its eaves out 1.6 m.
            let start = vertices.count
            palaceRoof(bays[k] / 2 + pier, hy, eaves: walls[k], over: 1.6, rise: rises[k], sweep: 1.0,
                       tile: blue, ridge: ridge, underside: stone)
            shift(from: start, by: ((x0 + x1) / 2, 0))
            if full {
                // A blue band under each roof.
                box(x0 - pier, -hy - 0.2, walls[k] - 1.4, x1 + pier, hy + 0.2, walls[k] - 0.6, ridge, Self.plain)
            }
        }
    }

    /// The National Theater (OSM way 1052759776) and Concert Hall (way
    /// 1052759775): on a two-step white podium 6 m high, a deep gallery of
    /// red columns round red walls, painted brackets under a double eave of
    /// gold tile to OSM's 37 m (the gallery and podium as the Blender
    /// models'), the theater's top roof hipped (廡殿), the hall's a
    /// hip-and-gable (歇山); broad steps up the front (-y), toward the
    /// square.
    mutating func performingArtsHall(_ hx: Float, _ hy: Float, kind: RoofKind) {
        let stone = colour("stone"), red = colour("vermilion"), gold = colour("goldTile"), goldRidge = colour("goldRidge")
        box(-hx, -hy, 0, hx, hy, 3, stone, Self.plain, top: colour("plinth"))
        box(-hx + 4, -hy + 4, 3, hx - 4, hy - 4, 6, stone, Self.plain, top: colour("plinth"))
        stairs(width: 34, from: -hy - 6, to: -hy + 4, height: 6, stone)
        // The hall behind a gallery 4 m deep, 14 m to the lower eave.
        let wx = hx - 15, wy = hy - 15
        box(-wx, -wy, 6, wx, wy, 20, colour("hallRed"), Self.floors)
        colonnade(hx - 11, hy - 11, 6, 20, step: 6, size: 1.6, red)
        let deck: [P2] = [(-(hx - 10), -(hy - 10)), (hx - 10, -(hy - 10)), (hx - 10, hy - 10), (-(hx - 10), hy - 10)]
        wallBand(deck, 19, deck, 20, colour("bracket"), Self.plain)
        // The double eave 9 m out past the columns, a red clerestory
        // between, the upper eave over the columns.
        chineseRoof(hx - 8.5, hy - 8.5, eaves: 20, over: 6.5, rise: 11, sweep: 2.4, kind: kind, tiers: 2, tierRise: 6, tierInset: 9,
                    colours: ChineseRoofColours(tile: gold, ridge: goldRidge, underside: colour("bracket"), gable: red, wall: red))
        // The plan with its steps, as OSM's, round the origin.
        shift(from: 0, by: (0, 3))
    }

    // MARK: The government district and Ximending

    /// The Presidential Office Building (OSM relation 206817: outer way
    /// 39239021, courts 39239022 and 39239025): five storeys of red brick
    /// with white bands round two courts, a round turret at each corner
    /// and a pavilion at each end, the central tower over the front (-y,
    /// east, toward Ketagalan Boulevard) to 60 m, floodlit at night.
    mutating func presidentialOffice() {
        let brick = colour("brick"), white = colour("brickTrim"), slate = colour("slate")
        let hx: Float = 61.7, hy: Float = 37.8, top: Float = 24
        // The wings round the two courts (x ±15.5 to ±49.5, y ±20.7).
        let blocks: [(Float, Float, Float, Float)] = [(-hx, -hy, hx, -20.7), (-hx, 20.7, hx, hy), (-hx, -20.7, -49.5, 20.7),
                                                     (49.5, -20.7, hx, 20.7), (-15.5, -20.7, 15.5, 20.7)]
        for (x0, y0, x1, y1) in blocks {
            box(x0, y0, 0, x1, y1, 1.6, white, Self.plain)
            box(x0, y0, 1.6, x1, y1, top, brick, Self.floors, top: slate)
        }
        // The porches front and back and the ends' pavilions, stepping
        // out (OSM's 2.6 m and 4.2 m).
        box(-12.7, -hy - 2.6, 0, 12.7, -hy, 11, white, Self.plain, top: white)
        box(-12.7, hy, 0, 12.7, hy + 2.6, 11, white, Self.plain, top: white)
        for sign in [Float(-1), 1] {
            box(sign > 0 ? 58 : -65.9, -30, 0, sign > 0 ? 65.9 : -58, 30, 26, brick, Self.floors, top: slate)
        }
        if full {
            for (x0, y0, x1, y1) in blocks {
                for z in [Float(9.4), 17.2] {
                    box(x0 - 0.15, y0 - 0.15, z, x1 + 0.15, y1 + 0.15, z + 0.9, white, Self.plain)
                }
                box(x0 - 0.3, y0 - 0.3, top - 0.6, x1 + 0.3, y1 + 0.3, top + 0.4, white, Self.plain, top: slate)
            }
        }
        // The corner turrets (OSM's round ends to 46.5 m out), under slate
        // domes.
        for (x, y) in [(Float(-55.3), Float(-41.9)), (55.3, -41.9), (55.3, 41.9), (-55.3, 41.9)] {
            let ring = Self.polygon(full ? 10 : 6, 4.6, x, y)
            wallBand(ring, 0, ring, 27, brick, Self.floors)
            pyramidRoof(ring, x, y, from: 27, to: 31, steps: full ? 2 : 1, slate)
        }
        // The tower: brick to 46 m, a white floodlit stage, a slate cap and
        // its mast to 60 m.
        let ty: Float = -32
        box(-7.5, ty - 7.5, top, 7.5, ty + 7.5, 46, brick, Self.floors)
        box(-6, ty - 6, 46, 6, ty + 6, 53, white, Map3DVertex.floodlit)
        if full {
            for z in [Float(31), 38.5] { box(-7.8, ty - 7.8, z, 7.8, ty + 7.8, z + 0.9, white, Self.plain) }
            box(-8, ty - 8, 45.4, 8, ty + 8, 46.4, white, Map3DVertex.floodlit)
        }
        pyramidRoof(Self.polygon(4, 8.5, 0, ty, phase: .pi / 4), 0, ty, from: 53, to: 58, steps: 2, slate)
        let foot = Self.polygon(4, 0.5, 0, ty, phase: .pi / 4), tip = Self.polygon(4, 0.15, 0, ty, phase: .pi / 4)
        wallBand(foot, 57.8, tip, 60, white, Self.plain)
        cap(tip, 60, white, Self.plain)
    }

    /// The Red House (OSM way 222080307): the octagonal brick market hall at
    /// the east end (-x) under a slate pyramid and a white lantern, the
    /// cross-shaped hall behind it under low slate roofs.
    mutating func ximenRedHouse() {
        let brick = colour("brick"), white = colour("brickTrim"), slate = colour("slate")
        let ox: Float = -34, oy: Float = -1
        let octagon = Self.polygon(8, 12.2, ox, oy, phase: .pi / 8)
        wallBand(octagon, 0, octagon, 10, brick, Self.floors)
        if full {
            for z in [Float(4.4), 9.2] {
                let band = Self.polygon(8, 12.45, ox, oy, phase: .pi / 8)
                wallBand(band, z, band, z + 0.8, white, Self.plain)
                cap(band, z + 0.8, white, Self.plain)
            }
        }
        let eave = Self.polygon(8, 13.2, ox, oy, phase: .pi / 8)
        band(eave, [Float](repeating: 9.8, count: 8), octagon, [Float](repeating: 10.4, count: 8), slate, Self.plain)
        pyramidRoof(Self.polygon(8, 12.2, ox, oy, phase: .pi / 8), ox, oy, from: 10.4, to: 14.8, steps: full ? 3 : 2, slate)
        let lantern = Self.polygon(8, 2.4, ox, oy, phase: .pi / 8)
        wallBand(lantern, 14.6, lantern, 16.4, white, Self.plain)
        pyramidRoof(Self.polygon(8, 2.8, ox, oy, phase: .pi / 8), ox, oy, from: 16.4, to: 17.5, steps: 1, slate)
        // The cross: OSM's bar along x and arm along y.
        let bars: [(Float, Float, Float, Float)] = [(-22.6, -4.3, 45.8, 3.9), (18.4, -23.9, 28.7, 23.9)]
        for (x0, y0, x1, y1) in bars {
            box(x0, y0, 0, x1, y1, 7.6, brick, Self.floors)
            let start = vertices.count
            let along = x1 - x0 > y1 - y0
            let hx = (along ? x1 - x0 : y1 - y0) / 2, hy = (along ? y1 - y0 : x1 - x0) / 2
            palaceRoof(hx, hy, eaves: 7.6, over: 0.6, rise: 3.4, sweep: 0, tile: slate, ridge: white, underside: white)
            if !along { turn(from: start) }
            shift(from: start, by: ((x0 + x1) / 2, (y0 + y1) / 2))
        }
        if full {
            for (x0, y0, x1, y1) in bars { box(x0 - 0.12, y0 - 0.12, 6.6, x1 + 0.12, y1 + 0.12, 7.4, white, Self.plain) }
        }
    }

    /// Turns the vertices from `start` on a quarter turn about the up axis.
    mutating func turn(from start: Int) {
        for k in start..<vertices.count {
            let v = vertices[k]
            vertices[k] = Map3DVertex(Map3DPoint(-v.y, v.x, v.z), normal: Map3DPoint(-v.ny, v.nx, v.nz),
                                      color: v.color, u: v.u, v: v.v, layer: v.layer)
        }
    }

    // MARK: Sun Yat-sen Memorial Hall and the Grand Hotel

    /// Sun Yat-sen Memorial Hall (OSM way 189788192, 30 m, its roof 10 m):
    /// on a low white platform, grey columns round a cream hall under a
    /// gold roof whose corners sweep high and whose front and back eaves
    /// rise in the middle.
    mutating func sunYatSenMemorialHall() {
        let stone = colour("stone"), gold = colour("goldTile"), goldRidge = colour("goldRidge")
        // OSM's 108.7 m by 112.5 m with the steps front and back.
        let hx: Float = 54.35, hy: Float = 51.25
        box(-hx, -hy, 0, hx, hy, 2, stone, Self.plain, top: colour("plinth"))
        for sign in [Float(-1), 1] {
            let y0 = sign < 0 ? -hy - 5 : hy + 5, y1 = sign < 0 ? -hy + 3 : hy - 3
            if sign < 0 { stairs(width: 40, from: y0, to: y1, height: 2, stone) } else {
                let start = vertices.count
                stairs(width: 40, from: -hy - 5, to: -hy + 3, height: 2, stone)
                turn(from: start)
                turn(from: start)
            }
        }
        let wx = hx - 12, wy = hy - 12
        box(-wx, -wy, 2, wx, wy, 19, colour("cream"), Self.floors)
        colonnade(hx - 7, hy - 7, 2, 19, step: 6.5, size: 1.6, colour("column"))
        let deck: [P2] = [(-(hx - 6), -(hy - 6)), (hx - 6, -(hy - 6)), (hx - 6, hy - 6), (-(hx - 6), hy - 6)]
        wallBand(deck, 18.6, deck, 19.5, colour("bracket"), Self.plain)
        palaceRoof(hx - 6, hy - 6, eaves: 20, over: 6, rise: 10, sweep: 4.5, arch: 4.5, tile: gold, ridge: goldRidge,
                   underside: colour("bracket"))
    }

    /// The Grand Hotel's main building (OSM way 25202548, 14 storeys; the
    /// hotel's 87 m): on its podium, cream floors between red columns
    /// under a double eave of gold tile, its top a hip-and-gable; the
    /// porte-cochère out from the front (-y), toward the river.
    mutating func grandHotel() {
        let red = colour("vermilion"), gold = colour("goldTile"), goldRidge = colour("goldRidge")
        let cy: Float = 7.8, hx: Float = 55, hy: Float = 28.8
        box(-hx, cy - hy, 0, hx, cy + hy, 6, colour("stone"), Self.plain, top: colour("plinth"))
        box(-hx + 3, cy - hy + 5, 6, hx - 3, cy + hy - 5, 60, colour("cream"), Self.floors)
        if full {
            // Red columns up the front and back, and red end walls.
            for y in [cy - hy + 4.6, cy + hy - 5.6] {
                for k in 0...14 {
                    let x = -hx + 4 + Float(k) * (2 * hx - 8) / 14
                    box(x - 0.8, y, 6, x + 0.8, y + 1, 60, red, Self.plain)
                }
            }
        }
        for sign in [Float(-1), 1] {
            let x0 = sign < 0 ? -hx + 2.6 : hx - 3.4, x1 = sign < 0 ? -hx + 3.4 : hx - 2.6
            box(x0, cy - hy + 5, 6, x1, cy + hy - 5, 60, red, Self.plain)
        }
        // The double roof.
        let start = vertices.count
        chineseRoof(hx - 3, hy - 5, eaves: 59.5, over: 5, rise: 20, sweep: 3.2, kind: .hipGable, tiers: 2, tierRise: 7.5, tierInset: 3,
                    colours: ChineseRoofColours(tile: gold, ridge: goldRidge, underside: red, gable: red, wall: red))
        shift(from: start, by: (0, cy))
        // The porte-cochère on the front, its own small gold roof.
        box(-20, -37.1, 0, 20, cy - hy, 9, colour("cream"), Self.floors)
        let porch = vertices.count
        palaceRoof(20, (37.1 + cy - hy) / 2, eaves: 9, over: 1.4, rise: 4, sweep: 1, tile: gold, ridge: goldRidge, underside: red)
        shift(from: porch, by: (0, (-37.1 + cy - hy) / 2))
    }

    // MARK: The city gates

    /// An old city gate on its stone base (北門 closed under a single
    /// slate roof; 東門, 南門, 小南門 an open pavilion of red columns under
    /// gold tile, the first two with a double eave), to `top`.
    mutating func cityGate(_ hx: Float, _ hy: Float, base: Float, top: Float, closed: Bool, double: Bool) {
        let gateStone = colour("gateStone"), red = colour("vermilion"), gold = colour("goldTile"), green = colour("greenRidge")
        let passage = min(5.2, hx * 0.5)
        gateBase(hx, hy, height: base, passage: passage, spring: base * 0.55, gateStone)
        if full {
            box(-hx - 0.25, -hy - 0.25, base - 0.6, hx + 0.25, hy + 0.25, base, colour("plinth"), Self.plain)
        }
        if closed {
            // 北門: a closed house of stone, small dark windows, a slate
            // hip-and-gable.
            let wx = hx - 1.2, wy = hy - 1.2
            box(-wx, -wy, base, wx, wy, top - 4, gateStone, Self.plain)
            if full {
                for x in [-wx * 0.5, 0, wx * 0.5] {
                    box(x - 0.7, -wy - 0.08, base + 1.6, x + 0.7, -wy, base + 3.2, colour("opening"), Self.plain)
                    box(x - 0.7, wy, base + 1.6, x + 0.7, wy + 0.08, base + 3.2, colour("opening"), Self.plain)
                }
            }
            palaceRoof(wx, wy, eaves: top - 4, over: 0.9, rise: 4, sweep: 0.5, kind: .hipGable, tile: colour("slate"),
                       ridge: colour("brickTrim"), gable: gateStone, underside: gateStone)
            return
        }
        let wx = hx - 2.4, wy = hy - 2.4
        let body: Float = double ? 4.6 : 4.2
        box(-(wx - 1.2), -(wy - 1.2), base, wx - 1.2, wy - 1.2, base + body, colour("hallWall"), Self.plain)
        colonnade(wx, wy, base, base + body, step: 2.6, size: 0.6, red)
        let deck: [P2] = [(-wx, -wy), (wx, -wy), (wx, wy), (-wx, wy)]
        wallBand(deck, base + body - 0.6, deck, base + body, colour("bracket"), Self.plain)
        let eave = base + body, step: Float = 2.6
        chineseRoof(wx, wy, eaves: eave, over: 1.8, rise: top - eave - (double ? step : 0), sweep: 1.0, kind: .hipGable,
                    tiers: double ? 2 : 1, tierRise: step, tierInset: 1.4,
                    colours: ChineseRoofColours(tile: gold, ridge: green, underside: colour("bracket"), gable: red, wall: red))
    }
}
