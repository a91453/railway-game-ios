import Foundation

// Decision 457: the Chinese roof as a part. A hip (廡殿) or a hip-and-gable
// (歇山), one eave or several (重簷), concave slopes and corners swept up,
// over any rectangle, in the colours its caller gives. The landmarks of
// `Map3DTaipeiPalaces.swift` are its first users; the way it is built
// (rings from the eaves in to the ridge, the slope's `t^1.6`, the corner
// lift, the hip-and-gable's turn at 0.45, the skirt of a double eave)
// follows `hipRoof` and `skirtRoof` in the owner's
// `Taipei_Central_3D_Clean/js/landmarks.js` (slop-taipei, MIT, Copyright
// (c) 2026 Mr.doob), rebuilt with `LandmarkMesh`'s parts.

/// A Chinese roof's colours: the tiles, the ridges and the eaves' edge, the
/// eaves' underside, a hip-and-gable's gables (the tiles' when nil), and the
/// walls between the eaves of a roof with more than one.
struct ChineseRoofColours: Sendable {
    var tile: UInt32
    var ridge: UInt32
    var underside: UInt32
    var gable: UInt32?
    var wall: UInt32
}

extension LandmarkMesh {
    /// How a palace roof ends: a hip at each end (廡殿), or a hip that turns
    /// into a gable near the top (歇山).
    enum RoofKind { case hipped, hipGable }

    /// A Chinese roof over walls of half sides `hx`, `hy` whose eaves stand
    /// `over` beyond them at `z0`, rising `rise` to the ridge's top: the
    /// slopes concave, the corners swept up `sweep`, the middles of the front
    /// and back eaves `arch` higher (as on the Sun Yat-sen Memorial Hall); with a
    /// fascia, an underside back to the walls, the hip ridges and a ridge
    /// with end ornaments.
    mutating func palaceRoof(_ hx: Float, _ hy: Float, eaves z0: Float, over: Float, rise: Float, sweep: Float,
                             kind: RoofKind = .hipped, arch: Float = 0, tile: UInt32, ridge: UInt32, gable: UInt32? = nil,
                             underside: UInt32) {
        let ex = hx + over, ey = hy + over
        // A small roof (a gate's) in fewer pieces than a large one.
        let large = ex > 20
        let steps = full ? (large ? 8 : 5) : (large ? 4 : 3), perSide = full ? (large ? 10 : 6) : (large ? 6 : 4)
        let (unit, near) = Self.rectRing(1, 1, perSide: perSide)
        // The ridge's half length: a hip's slopes meet it at 0.8 of the
        // eave's half width in; a hip-and-gable's hips stop 0.45 of the way.
        let ridgeHalf = kind == .hipped ? max(1, ex - ey * 0.8) : ex - ey * 0.45
        let top = z0 + rise - 0.6
        var rings: [(points: [P2], heights: [Float])] = []
        for s in 0...steps {
            let t = Float(s) / Float(steps)
            let sy = ey * (1 - t)
            let sx = kind == .hipped ? ex - (ex - ridgeHalf) * t : max(ridgeHalf, ex - (ey - sy))
            let lift = sweep * (1 - t) * (1 - t) * (1 - t)
            let heights = zip(unit, near).map { p, n -> Float in
                let corner = 1 - min(n, 0.3) / 0.3
                // The front and back eaves' middles, raised in a smooth bow.
                let bow = abs(p.y) > 0.99 && abs(p.x) < 0.999 ? arch * (1 - t) * (1 - t) * (0.5 + 0.5 * cos(.pi * p.x)) : 0
                return z0 + (top - z0) * powf(t, 1.6) + lift * corner * corner + bow
            }
            rings.append((unit.map { (x: $0.x * sx, y: $0.y * sy) }, heights))
        }
        for s in 0..<steps { band(rings[s].points, rings[s].heights, rings[s + 1].points, rings[s + 1].heights, tile, Self.tiles) }
        // The eave's edge and its underside back to the walls.
        let eave = rings[0]
        band(eave.points, eave.heights.map { $0 - 0.5 }, eave.points, eave.heights, ridge, Self.plain)
        band(unit.map { (x: $0.x * hx, y: $0.y * hy) }, eave.heights.map { _ in z0 - 0.5 }, eave.points,
             eave.heights.map { $0 - 0.5 }, underside, Self.plain)
        // A hip-and-gable's gables, a little proud of the roof.
        if kind == .hipGable, let gable {
            let gy = ey * 0.45, gz = rings[0].heights[perSide / 2] + (top - z0) * powf(0.45, 1.6)
            for sign in [Float(-1), 1] {
                let x = sign * (ridgeHalf + 0.05)
                let a: P3 = (x, -sign * (ey - gy), gz), b: P3 = (x, sign * (ey - gy), gz), c: P3 = (x, 0, top - 0.2)
                tri(a, b, c, gable, Self.plain)
            }
        }
        // The ridge, its top the roof's, an ornament at each end; the hip
        // ridges close by.
        box(-ridgeHalf - 0.4, -0.45, top - 0.3, ridgeHalf + 0.4, 0.45, top + 0.6, ridge, Self.plain)
        for sign in [Float(-1), 1] {
            let x = sign * (ridgeHalf + 0.4)
            box(min(x, x - sign * 1.2), -0.35, top + 0.6 - 0.01, max(x, x - sign * 1.2), 0.35, z0 + rise, ridge, Self.plain)
        }
        if full {
            for k in [0, perSide, 2 * perSide, 3 * perSide] {
                for s in 0..<(kind == .hipped ? steps : steps * 45 / 100) {
                    let a = rings[s].points[k], b = rings[s + 1].points[k]
                    let za = rings[s].heights[k], zb = rings[s + 1].heights[k]
                    let d = Self.distance(a, b)
                    guard d > 0.01 else { continue }
                    let nx = -(b.y - a.y) / d * 0.35, ny = (b.x - a.x) / d * 0.35
                    quad((a.x - nx, a.y - ny, za + 0.35), (a.x + nx, a.y + ny, za + 0.35),
                         (b.x + nx, b.y + ny, zb + 0.35), (b.x - nx, b.y - ny, zb + 0.35), ridge, Self.plain)
                }
            }
        }
    }

    /// A double eave's lower roof (重簷): from walls of half sides `hx`,
    /// `hy` at `z1` out `over` and down to its eaves at `z0`, corners swept
    /// up `sweep`; its edge and underside.
    mutating func skirtRoof(_ hx: Float, _ hy: Float, eaves z0: Float, wall z1: Float, over: Float, sweep: Float,
                            tile: UInt32, edge: UInt32, underside: UInt32) {
        let perSide = full ? (hx + over > 20 ? 10 : 6) : 4
        let (ringIn, nearIn) = Self.rectRing(hx, hy, perSide: perSide)
        let ringOut = ringIn.map { (x: $0.x * (hx + over) / hx, y: $0.y * (hy + over) / hy) }
        let up = nearIn.map { n -> Float in let t = 1 - min(n, 0.3) / 0.3; return sweep * t * t }
        band(ringOut, up.map { z0 + $0 }, ringIn, up.map { _ in z1 }, tile, Self.tiles)
        band(ringOut, up.map { z0 - 0.45 + $0 }, ringOut, up.map { z0 + $0 }, edge, Self.plain)
        band(ringIn, up.map { _ in z0 - 0.45 }, ringOut, up.map { z0 - 0.45 + $0 }, underside, Self.plain)
    }

    /// A Chinese roof of `tiers` eaves over walls of half sides `hx`, `hy`:
    /// the lowest eave at `z0`, `over` beyond the walls; each eave above
    /// `tierRise` higher over walls `tierInset` in on every side, a skirt
    /// (重簷) under each but the top, the walls between in `colours.wall`;
    /// the top roof rising `rise` from its eave, so the whole is
    /// `z0 + (tiers - 1) * tierRise + rise` high. Corners swept up `sweep`
    /// (the skirts 0.8 of it), the front and back eaves' middles `arch`
    /// higher. Nothing in it belongs to one building: sizes and colours are
    /// the caller's.
    mutating func chineseRoof(_ hx: Float, _ hy: Float, eaves z0: Float, over: Float, rise: Float, sweep: Float,
                              kind: RoofKind = .hipped, arch: Float = 0, tiers: Int = 1, tierRise: Float = 0, tierInset: Float = 0,
                              colours: ChineseRoofColours) {
        precondition(tiers >= 1 && hx - Float(tiers - 1) * tierInset > 0 && hy - Float(tiers - 1) * tierInset > 0)
        for k in 0..<(tiers - 1) {
            let ix = hx - Float(k) * tierInset, iy = hy - Float(k) * tierInset, z = z0 + Float(k) * tierRise
            skirtRoof(ix, iy, eaves: z, wall: z + tierRise * 0.7, over: over, sweep: sweep * 0.8, tile: colours.tile,
                      edge: colours.ridge, underside: colours.underside)
            let jx = ix - tierInset, jy = iy - tierInset
            box(-jx, -jy, z + 0.5, jx, jy, z + tierRise, colours.wall, Self.plain)
        }
        let inset = Float(tiers - 1) * tierInset
        palaceRoof(hx - inset, hy - inset, eaves: z0 + Float(tiers - 1) * tierRise, over: over, rise: rise, sweep: sweep, kind: kind,
                   arch: arch, tile: colours.tile, ridge: colours.ridge, gable: colours.gable ?? colours.tile,
                   underside: colours.underside)
    }
}
