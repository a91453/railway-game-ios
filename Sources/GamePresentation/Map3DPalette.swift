import GameCore

// MARK: - Colours

/// The 3D map's colours (F 台灣版＋): soft, bright and a little warm; the
/// player's buildings the warm yellow of the 2D map (decision 205).
public enum Map3DPalette {
    /// Decision 241: the ground and parks of the game's 2D map
    /// (`BaseMapStyle`'s light look: land #ECEEF6, park #D2E8C4), a little
    /// deeper and cooler so they read under the warm sun; the water a
    /// clearer blue than the 2D map's #C3CEEA, so a river never reads as
    /// one of the navy roads, and the farms a softer green.
    /// Decision 370 ((e), ``Map3DLook``): the ground the icon's pale
    /// #ECEEF6; the water, parks, farms and plazas the reference's
    /// `mapbox-palette.js` watercolor and atlas colours.
    public static let ground = Map3DColor.rgb(0xECEEF6)
    /// Decision 720: the ground under the city's lots. Low houses stand
    /// on a pale green (their yards and fields), denser blocks and every
    /// shop, office and works on a warm pale paving; the rest, and where
    /// the player's track runs, stays ``ground``. Both stay within a few
    /// L* of the ground, so the track and the trains stand off them as
    /// they do off it (the decision's table).
    public static let yard = Map3DColor.rgb(0xDEEACF)
    public static let paved = Map3DColor.rgb(0xE4E3DF)
    /// Decision 720: the city's flat roofs a step deeper than the pale
    /// version ``Map3DLook`` gave them (#D9DBE2), which ran into the ground.
    public static let cityRoof = Map3DColor.rgb(0xBABDC8)

    /// Decision 811: the land cover's ground outside the city's lots is
    /// the palette's own (``cover(_:)``, as OpenStreetMap's, so the two
    /// read as one; bare ground the lots' ``paved``), within 5 L* of
    /// ``ground`` as decision 720's lots are, so the track and the trains
    /// stand off it. The forest's alone is new: the woods' green (#B6DDCA)
    /// is 9 L* deeper than that, and the palette's paler greens are the
    /// yards' and fields', so the forest floor is a paler green of the
    /// woods' and the trees on it give the forest its colour.
    public static let forestFloor = Map3DColor.rgb(0xD4E8DA)

    /// Decision 720: what a 64 m square of ground is drawn as. Decision
    /// 811: and the land cover's, where no lot is.
    public enum GroundKind: CaseIterable, Sendable {
        case plain, yard, paved
        case forest, field, meadow, bareGround, marsh

        /// A lot's ground: none for open ground, which draws its own park
        /// or field.
        init?(_ lot: CitySkyline.Lot) {
            guard !lot.isOpenGround else { return nil }
            self = lot.use == .residential && lot.density <= 2 ? .yard : .paved
        }

        /// Decision 811: the land cover's ground: none for the built-up
        /// land, water (the base map's lies on it) and what is not known.
        init?(_ cover: LandCoverGrid.Cover) {
            switch cover {
            case .forest: self = .forest
            case .cropland: self = .field
            case .shrubland, .grassland: self = .meadow
            case .bare: self = .bareGround
            case .wetland: self = .marsh
            case .unknown, .builtUp, .water: return nil
            }
        }

        var colour: UInt32 {
            switch self {
            case .plain: Map3DPalette.ground
            case .yard: Map3DPalette.yard
            case .paved: Map3DPalette.paved
            case .forest: Map3DPalette.forestFloor
            case .field: Map3DPalette.cover(.farmland)
            case .meadow: Map3DPalette.cover(.grass)
            case .bareGround: Map3DPalette.paved
            case .marsh: Map3DPalette.cover(.wetland)
            }
        }
    }

    /// Decision 720: a corner's colour where four squares of `kinds` meet:
    /// their colours' mean, one of ``groundMixes``.
    public static func ground(mixing kinds: [GroundKind]) -> UInt32 {
        guard !kinds.isEmpty else { return ground }
        var sum: (UInt32, UInt32, UInt32) = (0, 0, 0)
        for kind in kinds {
            let c = kind.colour
            sum = (sum.0 + (c & 0xFF), sum.1 + ((c >> 8) & 0xFF), sum.2 + ((c >> 16) & 0xFF))
        }
        let n = UInt32(kinds.count), half = n / 2
        return ((sum.0 + half) / n) | ((sum.1 + half) / n) << 8 | ((sum.2 + half) / n) << 16 | 0xFF00_0000
    }

    /// Every colour ``ground(mixing:)`` gives four squares, which
    /// ``Map3DLook`` leaves as they are.
    public static let groundMixes: Set<UInt32> = {
        var mixes = Set<UInt32>()
        let all = GroundKind.allCases
        for a in all { for b in all { for c in all { for d in all { mixes.insert(ground(mixing: [a, b, c, d])) } } } }
        return mixes
    }()
    public static let water = Map3DColor.rgb(0x86D3E3)
    /// Decision 272: the parks' green and the trees' livelier, nearer the
    /// owner's sunny target picture; the ground and roads as decision 241.
    public static let park = Map3DColor.rgb(0xC8DFC0)
    public static let farm = Map3DColor.rgb(0xE2EBCF)
    public static let plaza = Map3DColor.rgb(0xEAD9BF)
    /// Decision 370: a step deeper, so the track stands off the pale ground
    /// and the trains off their bed.
    public static let ballast = Map3DColor.rgb(0x7E786D)
    public static let embankment = Map3DColor.rgb(0x9DB07E)
    public static let rail = Map3DColor.rgb(0x6E7379)
    public static let railTop = Map3DColor.rgb(0xC9CED4)
    public static let concrete = Map3DColor.rgb(0xCFCBC2)
    /// Decision 941: the yellow of a level crossing's hatching, the
    /// reference's own (`level-crossing.js`, `PAINT_Y` [205, 160, 25]).
    /// Its posts' yellow and black (`YEL`, `BLK`) are the studio's gate's
    /// (decision 929, ``Map3DCrossingGate/meshPalette``), and the rubber
    /// over the rails ``Map3DScene/Builder/crossingDeck``.
    public static let crossingHatch = Map3DColor.rgb(0xCDA019)
    public static let bridge = Map3DColor.rgb(0x8E9CA8)
    public static let portal = Map3DColor.rgb(0x8B9096)
    /// Decision 359 (續): a tunnel's walls the ground's cool grey a step
    /// deeper, its roof and floor deeper still (the bore's shade), and its
    /// lamps the icon's warm yellow, lighter.
    public static let tunnelWall = Map3DColor.rgb(0xA9AFBE)
    public static let tunnelLining = Map3DColor.rgb(0x6E7487)
    public static let tunnelLamp = Map3DColor.rgb(0xFFE2A6)
    public static let platform = Map3DColor.rgb(0xDCD6C8)
    public static let platformEdge = Map3DColor.rgb(0xF2C94C)
    /// Taiwanese station signs' blue, on the canopies.
    public static let canopy = Map3DColor.rgb(0x2F6DB5)
    /// A train's red body (the owner's old car e752e7a2,
    /// ``Map3DRedCommuter``): near its flat texture's #711604 but redder
    /// and a shade lighter, which under the map's light read as brown.
    public static let trainRed = Map3DColor.rgb(0x8C1C1C)
    public static let roof = Map3DColor.rgb(0xC4C8D6)
    /// The five colours of the local studio's t001 palette that the owner's
    /// old textures use and the lists here did not have
    /// (`tools/texture-palette/t003/`, sorted from the old textures on
    /// 2026-11-15): steel (bare steelwork, piers, underframes; 271 of the
    /// old building textures), dark (dark windows and glass, coal, signal
    /// housings; 24), a red brick paler than the old plants' ``brick``
    /// (32), timber (25) and terrazzo, Taiwan's washed granite plaster
    /// (11). Named so a model and a studio brief can use them by name.
    public static let steel = Map3DColor.rgb(0x8A9099)
    public static let dark = Map3DColor.rgb(0x2B2F36)
    public static let redBrick = Map3DColor.rgb(0xB07A62)
    public static let timber = Map3DColor.rgb(0x9A7657)
    public static let terrazzo = Map3DColor.rgb(0xE3DCCB)
    public static let arcade = Map3DColor.rgb(0x6F6A64)
    /// Decision 891: the gold of the landmarks' ornaments (Central Plaza's
    /// band, the Sun Moon Lake temple's ridge ornaments), which the Hong
    /// Kong landmarks' brief added (decision 854) and the palette had not
    /// listed.
    public static let gold = Map3DColor.rgb(0xC8A24E)
    /// Decision 897: the Ngong Ping cable car's gold slats, the six bands
    /// on a standard cabin's lower half (the studio's sample of the real
    /// cabin's sunlit slats #A58548, #9C7F3E; agreed 2026-11-20), deeper
    /// than ``gold`` so they read apart from the steel corner posts.
    public static let slatGold = Map3DColor.rgb(0xA8904A)
    public static let tankBlue = Map3DColor.rgb(0x3B7DD8)
    public static let tankSteel = Map3DColor.rgb(0xC8CDD2)
    public static let trunk = Map3DColor.rgb(0x8A6A4F)
    public static let crown = Map3DColor.rgb(0x8DC27A)
    /// The player's buildings (decision 205) and the navy rim that marks
    /// them apart from the city's offices in grey (the art direction's
    /// note).
    public static let player = Map3DColor.rgb(0xFFC86B)
    public static let playerRoof = Map3DColor.rgb(0xFFE2A6)
    public static let playerRim = Map3DColor.rgb(0x26385C)

    /// Decision 234: the base map's land cover, a little deeper than the
    /// 2D map's (its `landcover` and `park`) so it reads on the lit
    /// ground. Decision 241: the 2D map's own colours, deepened alike.
    static func cover(_ cover: Map3DBaseMap.Cover) -> UInt32 {
        switch cover {
        // Decision 393: decision 370's farm, as the game's own fields.
        case .farmland: farm
        case .grass: rgb(0xE2EBCF)
        case .sand: rgb(0xF2E2BD)
        case .wetland: rgb(0xD7E4EA)
        case .wood: rgb(0xB6DDCA)
        case .park: park
        case .water: water
        }
    }

    /// Decision 241: the roads drawn as a city map draws them (the
    /// reference's `city_map_reference_clean` ink look, deepest for the
    /// biggest), in the game's navy rather than its black: the motorways
    /// the navy of the app's text, the main roads its map shadow, lanes
    /// its accent. Plain (untextured) so they read from afar.
    /// Decision 370 ((e)): a mid grey darker than the ground (CIE L* 62,
    /// 64, 66, 69, the smaller roads a step lighter), with the hue of the
    /// icon's navy #262C57 (CIE LCh h −67°) at chroma 6, so it still reads
    /// as asphalt; lit by its street lights after dark (``Map3DLook``).
    static func road(_ kind: Map3DBaseMap.RoadKind) -> UInt32 {
        switch kind {
        case .motorway, .trunk: rgb(0x9595A0)
        case .primary, .secondary: rgb(0x9B9AA5)
        case .tertiary: rgb(0xA09FAA)
        case .minor, .service: rgb(0xA8A7B2)
        }
    }

    /// Decision 241: the sidewalks, paved. Decision 370: a white kerb that
    /// outlines the grey road.
    public static let sidewalk = Map3DColor.rgb(0xF7F7F4)
    /// Decision 370: the centre line in the icon's warm yellow #FFC86B; the
    /// platform edge keeps the safety yellow #F2C94C.
    public static let centreLine = Map3DColor.rgb(0xFFC86B)

    /// Row house walls: `city_world_reference`'s shophouse palette (white
    /// 4, #F2E2D6 2, #E0D0C8 1, #D6C2B0 1) and four tile colours common in
    /// Taiwan.
    static let houseWalls: [(color: UInt32, weight: Float)] = [
        (rgb(0xFFFFFF), 4), (rgb(0xF2E2D6), 2), (rgb(0xE0D0C8), 1), (rgb(0xD6C2B0), 1),
        (rgb(0xE8D8B8), 1), (rgb(0xC9D3D6), 1), (rgb(0xD9B9A2), 1), (rgb(0xBFC8B4), 1),
    ]
    static let officeWalls: [UInt32] = [rgb(0xAEBFCC), rgb(0xC2CCD4), rgb(0x9FB3C2)]
    /// Decision 242: fair-faced concrete, in the cool light greys of the
    /// map's ground and roofs (decision 241) rather than a photograph's.
    static let concreteWalls: [UInt32] = [rgb(0xC9CCD5), rgb(0xBFC3CE), rgb(0xD3D4DA)]

    /// Decision 764: the city's own buildings drawn in more colours than
    /// the kits' (which keep ``officeWalls`` and ``concreteWalls`` as they
    /// are). The added colours are the local studio's restyle set
    /// (SwiftRailMac `tools/restyle/own.mjs`, 2026-11-13: walls, flat and
    /// sloped roofs, accents) and a few seen on Taiwan's streets; the look
    /// (``Map3DLook``) draws them pale as it does every city colour.
    ///
    /// Flat roofs, by weight: the grey concrete of decision 720 (which the
    /// look keeps as ``cityRoof``), dark grey sheet steel, a warm grey
    /// waterproofing, the green waterproof paint, a blue sheet-steel room
    /// over the whole roof and, on low houses only, red tiles.
    static let cityRoofs: [(color: UInt32, weight: Float, low: Bool)] = [
        (roof, 4, false), (rgb(0x6C7279), 2, false), (rgb(0x5A4E4A), 1, false),
        (rgb(0x3C8A5A), 1, false), (rgb(0x2D68AC), 1, false), (rgb(0xB85A42), 1, true),
    ]
    /// Offices: ``officeWalls`` and a beige stone, a pale blue grey and a
    /// dark grey aluminium cladding.
    static let cityOfficeWalls: [UInt32] = officeWalls + [rgb(0xD9D4C8), rgb(0xDAE2E6), rgb(0x8A949E)]
    /// Fair-faced concrete: ``concreteWalls`` and a warm grey, a white
    /// grey and a darker weathered grey.
    static let cityConcreteWalls: [UInt32] = concreteWalls + [rgb(0xBBB2A9), rgb(0xDADCDD), rgb(0xA9B0B8)]
    /// Big halls (arenas, gyms, markets, a hall of 3,000 m² or more under
    /// six storeys): white, warm grey, silver grey or brick walls...
    static let hallWalls: [UInt32] = [rgb(0xDADCDD), rgb(0xBBB2A9), rgb(0xA9B0B8), rgb(0xB0624A), rgb(0xEBD099)]
    /// ...under a blue, green, silver or grey sheet-steel roof.
    static let hallRoofs: [UInt32] = [rgb(0x2D68AC), rgb(0x3C8A5A), rgb(0x8A949E), rgb(0x4F7FB0), roof]

    private static func rgb(_ hex: UInt32) -> UInt32 { Map3DColor.rgb(hex) }
}
