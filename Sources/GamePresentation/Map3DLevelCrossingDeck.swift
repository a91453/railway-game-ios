/// Decision 941: a level crossing's road surface, from the reference's
/// procedural landscape (`a91453/railway-reference-private`
/// `Railway/rail-reference/regions/taiwan/source/landscape-engine/engine/integration/level-crossing.js`,
/// `levelCrossingGeometry`), on the crossings decision 263 finds
/// (``Map3DLevelCrossing``): the road's own surface over the rails, a
/// rubber panel over each track, and Taiwan's yellow cross-hatching
/// (網狀線) from barrier to barrier, which keeps clear of the rails.
///
/// The reference's street frame: `s` along the street from the
/// crossing's middle, `t` across it to the street's left (the game's
/// `across`, ``Map3DLevelCrossing/along`` turned a quarter).
enum Map3DLevelCrossingDeck {
    /// `FLAT`, metres: how far the deck stays level past the outermost
    /// track, along the street (``Map3DLevelCrossing/deckHalf``).
    static let flat: Float = 3.2
    /// `RAMP` and `RAISE`, metres: the reference's ramp, 5 m down from a
    /// deck 0.15 m over its road. Not the game's: the game's rails stand
    /// ``Map3DScene/railLift`` on their bed, so its deck is about 0.75 m
    /// over the road and its ramp stays decision 263's gentle 9.4 m
    /// (``Map3DLevelCrossing/ramp``), not a 1 in 7 kerb.
    static let referenceRamp: Float = 5
    static let referenceRaise: Float = 0.15
    /// `LIFT`, metres: the reference's road over its ground, the game's
    /// own for its tertiary roads and up (``Map3DScene/Builder/lift(of:)``).
    static let referenceLift: Float = 0.32

    /// The hatching's lines, metres: `G` apart along the street, `W2`
    /// wide, laid in lengths of 0.5 across it so they follow the ramps,
    /// 0.2 in from the carriageway's edges, 0.4 short of the barriers'
    /// line, none nearer a track than 1.8 along it.
    static let hatchPitch: Float = 2.5
    static let hatchWidth: Float = 0.1
    static let hatchStep: Float = 0.5
    static let hatchEdge: Float = 0.2
    static let hatchEnd: Float = 0.4
    static let railClear: Float = 1.8
    /// How far the paint and the panels stand over the deck, metres, so
    /// they never flicker into it.
    static let paintLift: Float = 0.02
    static let panelLift: Float = 0.01
    /// Half a rubber panel across its track, metres: the rails' gauge and
    /// their flangeways.
    static let panelHalf: Float = 1.1

    /// Where the tracks cross the street, metres along it from the middle
    /// (the reference's `ts`): the outermost two, or the one.
    static func tracks(of crossing: Map3DLevelCrossing) -> [Float] {
        crossing.spread > 0 ? [-crossing.spread / 2, crossing.spread / 2] : [0]
    }

    /// The track's way in the street's frame: along the street (`ws`) and
    /// across it (`wt`, at least 0.3, so a sharply slanting crossing does
    /// not run off).
    static func slant(of crossing: Map3DLevelCrossing) -> (ws: Float, wt: Float) {
        var ws = crossing.trackWay.dot(crossing.along), wt = crossing.trackWay.dot(crossing.across)
        if wt < 0 { ws = -ws; wt = -wt }
        return (ws, max(wt, 0.3))
    }

    /// How far the point `s` along the street and `t` across it is from
    /// the line through the tracks' middle, square to the track, on the
    /// way the street goes (the reference's `s`, for a crossing square on).
    static func fromTracks(_ crossing: Map3DLevelCrossing, s: Float, t: Float) -> Float {
        let (ws, wt) = slant(of: crossing)
        return s * wt - t * ws
    }

    /// How far from the tracks' middle, square to the track, the hatching
    /// reaches (the reference's `half`, its barriers' line): here the
    /// ramps' foot, the whole raised crossing, as Taiwan's hatched box
    /// runs from stop line to stop line. The game's barriers stand only
    /// ``Map3DLevelCrossing/barrier`` from the track, on the deck, and a
    /// box to them left a band 1.6 m wide that read as a comb.
    static func hatchReach(of crossing: Map3DLevelCrossing) -> Float {
        crossing.rampEnd * slant(of: crossing).wt
    }

    /// The scene point `s` along the street and `t` across it, level.
    static func point(_ crossing: Map3DLevelCrossing, s: Float, t: Float) -> Map3DPoint {
        Map3DPoint(crossing.point.x, 0, crossing.point.z) + crossing.along * s + crossing.across * t
    }

    /// The hatching's pieces, each four level corners (the reference's
    /// two diagonals, `dir` 1 and −1, at 45° to the street): the loop of
    /// `levelCrossingGeometry`'s `type === 0`, its limits (the barriers'
    /// line and the rails) measured square to the track, so a slanting
    /// crossing's hatching runs along its track as a square one's does.
    static func hatch(_ crossing: Map3DLevelCrossing) -> [[Map3DPoint]] {
        let hw = crossing.kind.width(ramp: false) / 2, reach = hatchReach(of: crossing) - hatchEnd
        let nx = hatchWidth / Float(2).squareRoot(), (ws, wt) = slant(of: crossing)
        let rails = tracks(of: crossing).map { $0 * wt }
        guard reach > railClear, hw > hatchEdge else { return [] }
        let span = 2 * (reach / wt + hw * abs(ws / wt)) + 2 * hw
        var pieces: [[Map3DPoint]] = []
        for dir: Float in [1, -1] {
            var o = -span
            while o <= span {
                var t = -hw + hatchEdge
                while t < hw - hatchEdge {
                    let t1 = min(hw - hatchEdge, t + hatchStep), a = o + dir * t, b = o + dir * t1
                    defer { t += hatchStep }
                    let na = fromTracks(crossing, s: a, t: t), nb = fromTracks(crossing, s: b, t: t1), middle = (na + nb) / 2
                    if max(abs(na), abs(nb)) > reach || max(abs(a), abs(b)) > crossing.rampEnd - hatchEnd || rails.contains(where: { abs(middle - $0) < railClear }) { continue }
                    pieces.append([(a - nx, t), (b - nx, t1), (b + nx, t1), (a + nx, t)].map { point(crossing, s: $0.0, t: $0.1) })
                }
                o += hatchPitch
            }
        }
        return pieces
    }

    /// The rubber panels over the tracks, each four level corners across
    /// the deck's width, their edges along their track.
    static func panels(_ crossing: Map3DLevelCrossing) -> [[Map3DPoint]] {
        let half = crossing.halfWidth, (ws, wt) = slant(of: crossing), reach = panelHalf / wt, lean = ws / wt
        return tracks(of: crossing).map { s in
            [point(crossing, s: s - reach + lean * half, t: half), point(crossing, s: s - reach - lean * half, t: -half),
             point(crossing, s: s + reach - lean * half, t: -half), point(crossing, s: s + reach + lean * half, t: half)]
        }
    }

    /// `corners` at `height`'s surface plus `lift`, facing up.
    static func raised(_ corners: [Map3DPoint], lift: Float, height: (Float, Float) -> Float) -> [Map3DPoint] {
        let lifted = corners.map { Map3DPoint($0.x, height($0.x, $0.z) + lift, $0.z) }
        let up = (lifted[1] - lifted[0]).cross(lifted[3] - lifted[0]).y > 0
        return up ? lifted : lifted.reversed()
    }
}
