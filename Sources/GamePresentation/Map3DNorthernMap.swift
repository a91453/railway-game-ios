import GameCore

// Decision 799: what the 3D map draws differently on a map of the far
// north (Rovaniemi's, decision 789): the ground under snow, and the track
// at Finland's gauge. Only what is drawn changes, and both come from where
// the map is (its anchor), so no save records either and every other map
// is drawn as before.

/// Decision 799: the gauge the 3D map lays its rails at.
public enum Map3DTrackGauge {
    /// Taiwan's 1,067 mm, which every map was drawn at.
    public static let cape: Float = 1.067
    /// Finland's 1,524 mm.
    public static let finnish: Float = 1.524

    /// The gauge of `world`'s map, metres: Finland's on a map anchored in
    /// Finland, else Taiwan's (a map with no anchor, the generated ones,
    /// too).
    public static func metres(world: GameWorld) -> Float {
        world.geoAnchor.map(metres(anchor:)) ?? cape
    }

    /// Finland within 59.5–70.2° N and 19.0–31.6° E.
    static func metres(anchor: GeoAnchor) -> Float {
        595_000_000...702_000_000 ~= anchor.latitude && 190_000_000...316_000_000 ~= anchor.longitude ? finnish : cape
    }
}

/// Decision 799: the ground of a northern map under snow. The plain ground
/// is already the palette's pale blue-white; the greens that say "grass",
/// "field" and "wood" on Taiwan's map are what makes a map of Lapland look
/// like summer. So, once the scene's colours are made, the fields, grass,
/// parks and sand take the palette's own whites, the yards under the low
/// houses the plain ground, the grass banks of the track's bed the lots'
/// pale paving, and the woods a wood under snow (the one new colour). Frozen bog keeps its blue-grey, the water its blue (the rivers
/// freezing is the snow scene's, later), and the trees, roads, track and
/// buildings their own colours. The same all year: the game has no seasons.
public enum Map3DSnowGround {
    /// Whether `world`'s map is drawn under snow: one anchored north of
    /// 60° N (Rovaniemi is at 66.5°; Taiwan and Hong Kong are south of
    /// 26°).
    public static func covers(_ world: GameWorld) -> Bool {
        world.geoAnchor.map { $0.latitude >= 600_000_000 } ?? false
    }

    /// Open snow, the brightest ground: the palette's pavement white.
    public static let field = Map3DPalette.sidewalk
    /// A wood under snow: halfway from the palette's wood to its ground
    /// (#D1E6E0). New with decision 799.
    public static let wood = Map3DColor.rgb(0xD1E6E0)

    /// What each of the ground's colours is drawn as under snow.
    static let colours: [UInt32: UInt32] = {
        // The fields and the grass are one colour today.
        var map: [UInt32: UInt32] = [:]
        for green in [Map3DPalette.farm, Map3DPalette.cover(.grass), Map3DPalette.park] { map[green] = field }
        map[Map3DPalette.cover(.sand)] = Map3DPalette.ground
        map[Map3DPalette.cover(.wood)] = wood
        // The grass banks of the track's bed: the lots' pale paving, so
        // the bed still stands off the snow beside it.
        map[Map3DPalette.embankment] = Map3DPalette.paved
        // The corners where the lots' grounds meet (decision 720), the
        // yards as plain ground. Two mixes of one colour give the first's.
        let all = Map3DPalette.GroundKind.allCases
        func snowed(_ kind: Map3DPalette.GroundKind) -> Map3DPalette.GroundKind { kind == .yard ? .plain : kind }
        for a in all { for b in all { for c in all { for d in all {
            let from = Map3DPalette.ground(mixing: [a, b, c, d]), to = Map3DPalette.ground(mixing: [a, b, c, d].map(snowed))
            if from != to, map[from] == nil { map[from] = to }
        } } } }
        return map
    }()

    /// `mesh`'s ground under snow.
    static func cover(_ mesh: inout Map3DMesh) {
        var last: (from: UInt32, to: UInt32)?
        mesh.restyleVertices { vertex in
            let from = vertex.color
            if let last, last.from == from {
                vertex.color = last.to
            } else {
                let to = colours[from | 0xFF00_0000].map { ($0 & 0x00FF_FFFF) | (from & 0xFF00_0000) } ?? from
                vertex.color = to
                last = (from, to)
            }
        }
    }
}
