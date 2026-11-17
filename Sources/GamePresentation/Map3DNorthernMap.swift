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
        Map3DRegionLook(world: world).gauge
    }

    /// Finland within 59.5–70.2° N and 19.0–31.6° E (decision 802:
    /// ``Map3DRegionLook/init(anchor:)``).
    static func metres(anchor: GeoAnchor) -> Float {
        Map3DRegionLook(anchor: anchor).gauge
    }
}

/// Decision 799: the ground of a northern map under snow. The plain ground
/// is already the palette's pale blue-white; the greens that say "grass",
/// "field" and "wood" on Taiwan's map are what makes a map of Lapland look
/// like summer. So, once the scene's colours are made, the fields, grass,
/// parks and sand take the palette's own whites, the yards under the low
/// houses the plain ground, the grass banks of the track's bed the lots'
/// pale paving, and the woods a wood under snow (the one new colour). Frozen bog keeps its blue-grey, and the roads, track and
/// buildings their own colours. Decision 833: the water frozen
/// (``ice``) and the trees under snow (``Map3DSnowTrees``). The same all
/// year: the game has no seasons.
public enum Map3DSnowGround {
    /// Whether `world`'s map is drawn under snow: one anchored north of
    /// 60° N (Rovaniemi is at 66.5°; Taiwan and Hong Kong are south of
    /// 26°).
    public static func covers(_ world: GameWorld) -> Bool {
        Map3DRegionLook(world: world).snow
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

    /// Decision 833: the rivers and lakes frozen over: the palette's
    /// wetland blue-grey (``Map3DPalette/cover(_:)``'s `.wetland`), the
    /// frozen bog's, a step darker than the snow beside it, so the ice
    /// still reads as water under snow. Matte: it takes no ripples and
    /// mirrors no sky (``Map3DVertex/ice``).
    public static let ice = Map3DPalette.cover(.wetland)

    /// `mesh`'s ground under snow. Decision 833: and its water frozen
    /// (``ice``).
    static func cover(_ mesh: inout Map3DMesh) {
        var last: (from: UInt32, to: UInt32)?
        mesh.restyleVertices { vertex in
            if vertex.layer == Map3DVertex.water {
                vertex.color = (ice & 0x00FF_FFFF) | (vertex.color & 0xFF00_0000)
                vertex.layer = Map3DVertex.ice
                return
            }
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

/// Decision 833: the trees of a northern map under snow. A tree's leaves
/// take its instance's colour (``Map3DSceneryProp/leaves``), so, as the
/// ground is restyled once the scene is made, each tree's, bush's and
/// conifer's green is taken part of the way to the snow's white
/// (``Map3DSnowGround/field``): the conifers least, so a wood of spruce
/// stays dark green flecked with white, as Lapland's do; the broadleaf
/// trees (birch, bare in winter, its crown frosted) and the street trees
/// further; the bushes, low and buried, most. The trunks and every other
/// prop keep their colours.
public enum Map3DSnowTrees {
    /// How far toward the snow's white each kind of tree's green goes.
    public static let coniferShare: Float = 0.45
    public static let broadleafShare: Float = 0.62
    public static let bushShare: Float = 0.75

    /// The share for each model of ``Map3DModelCatalog/standard`` that is
    /// a tree: the street tree's (also the woods' broadleaf), the
    /// conifers' and the bushes'.
    static let shares: [Int: Float] = {
        var shares: [Int: Float] = [:]
        let catalog = Map3DModelCatalog.standard
        if let tree = catalog.index(of: Map3DProp.tree.modelName) { shares[tree] = broadleafShare }
        for conifer in Map3DSceneryProp.conifers {
            if let index = catalog.index(of: conifer.modelName) { shares[index] = coniferShare }
        }
        for bush in [Map3DSceneryProp.bushes, .bushesLarge] {
            if let index = catalog.index(of: bush.modelName) { shares[index] = bushShare }
        }
        return shares
    }()

    /// `props` with their trees under snow.
    static func cover(_ props: [Map3DInstance]) -> [Map3DInstance] {
        props.map { prop in
            guard let share = shares[prop.model] else { return prop }
            let white = Map3DSnowGround.field
            func channel(_ value: Float, _ shift: UInt32) -> Float {
                let snow = Float((white >> shift) & 0xFF) / 255
                return value + (snow - value) * share
            }
            var snowed = Map3DInstance(model: prop.model, transform: prop.transform,
                                       stripe: (channel(prop.stripe.0, 0), channel(prop.stripe.1, 8), channel(prop.stripe.2, 16)))
            snowed.group = prop.group
            snowed.lit = prop.lit
            snowed.christmas = prop.christmas
            return snowed
        }
    }
}
