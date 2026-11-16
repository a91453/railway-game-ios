import GameCore

// Decision 802: Finland's buildings (``Map3DRegionLook/Buildings/nordic``),
// from the parts and the atlas the city already has: no texture is new.
// What tells a Finnish town from a Taiwanese one from above is its roofs
// and its colours: wooden houses of one or two floors under a pitched
// roof, painted red ochre (punamulta), yellow ochre (keltamulta), white or
// grey, each standing alone in its yard; blocks of flats in pale plaster
// or brick under a flat roof with nothing on it.

/// Decision 802: the colours of Finland's buildings.
enum Map3DNordic {
    /// A wooden house's boards: yellow ochre and white the commonest on
    /// the houses rebuilt after 1944, then red ochre and greys, now and
    /// then a pale green or a blue grey.
    static let houseWalls: [UInt32] = [
        0xD9A94E, 0xD9A94E, 0xE4C27A, 0xEDEAE0, 0xEDEAE0, 0xA5402F, 0xA5402F, 0x8E3A2C, 0xC9CCCF, 0xB5BABF, 0xB9C4AE, 0x9FB0BD,
    ].map(Map3DColor.rgb)
    /// A block of flats: white and grey plaster, pale yellow and red brick.
    static let blockWalls: [UInt32] = [0xEDEAE0, 0xE2E0D8, 0xD3D5D6, 0xC9CCCF, 0xE2CC96, 0xB0624A, 0xC8B49A].map(Map3DColor.rgb)
    /// A pitched roof's sheet steel or felt, before the snow on it: dark
    /// grey, black, brick red and green.
    static let pitchedRoofs: [UInt32] = [0x4A4E55, 0x4A4E55, 0x2F3237, 0x8E3A2C, 0x7A4A3C, 0x4F6B58].map(Map3DColor.rgb)
    /// A house's windows' white frames, and its plinth.
    static let trim = Map3DColor.rgb(0xF4F2EC)

    /// A storey of a wooden house, metres.
    static let storey: Float = 3
    /// A pitched roof's rise over half its span: some 27°.
    static let pitch: Float = 0.5
    /// The widest house a pitched roof spans, metres; a wider hall's roof
    /// is flat.
    static let widestPitched: Float = 14
    /// The share of its box an outline fills to stand under one pitched
    /// roof over the box (a porch or a bay window cut from a corner).
    static let pitchedFill: Float = 0.8
}

/// Decision 802: the snow lying on a northern map's roofs.
extension Map3DSnowGround {
    /// How much of a roof's colour the snow on it hides.
    static let roofShare: Float = 0.62
    /// The snow on a roof: the ground's blue-white, a step deeper than
    /// the open snow so a roof still stands off it.
    static let roofSnow = Map3DColor.rgb(0xE6EAF2)

    /// `roof` under snow: ``roofShare`` of the way to ``roofSnow``.
    static func roof(_ roof: UInt32) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let from = Float((roof >> shift) & 0xFF), to = Float((roofSnow >> shift) & 0xFF)
            return UInt32((from + (to - from) * roofShare).rounded()) << shift
        }
        return channel(0) | channel(8) | channel(16) | (roof & 0xFF00_0000)
    }
}

extension Map3DScene.Builder {
    /// Decision 802: whether the real building of `kind` and `storeys`,
    /// one `outline` of `area` m² in the oriented `box`, stands under a
    /// pitched roof on a Finnish map: a house of one or two floors whose
    /// outline nearly fills a box no wider than ``Map3DNordic/widestPitched``.
    static func isPitched(_ kind: RealKind, storeys: Int, area: Float, single: Bool,
                          box: (centre: Map3DPoint, along: Map3DPoint, length: Float, width: Float)) -> Bool {
        guard kind == .house || kind == .shophouse, storeys <= 2, single, box.width >= 3, box.width <= Map3DNordic.widestPitched else { return false }
        return area >= Map3DNordic.pitchedFill * box.length * box.width
    }

    /// Decision 802: one of the houses the game lays along a road
    /// (``addTownHouse``) on a Finnish map: a wooden house of one or two
    /// floors standing alone under a pitched roof, its ridge along the
    /// road, or with `flats` a plastered block of three to five under a
    /// flat roof. No arcade, shutter, sign, tank or rooftop room; the
    /// same afar but for the plinth. 16 triangles a house near (a
    /// Taiwanese one is 60 and more), 12 a block.
    static func addNordicHouse(_ mesh: inout Map3DMesh, middle: Map3DPoint, front: Map3DPoint, width: Float, depth: Float, flats: Bool,
                               far: Bool, snow: Bool, tallest: Int?, r: (Int32) -> Float) {
        func snowed(_ roof: UInt32) -> UInt32 { snow ? Map3DSnowGround.roof(roof) : roof }
        if flats {
            let floors = min(3 + Int(r(2) * 3), max(tallest ?? 5, 2))
            let wall = varied(pick(Map3DNordic.blockWalls, r(1043)), r(1041))
            let windows = Map3DPaint.bays(pick(Map3DSurface.flats, r(10)), bay: 3.2, floors: floors)
            mesh.addBox(base: middle, forward: front, length: depth, width: width - 1.5, height: Float(floors) * Map3DNordic.storey + 0.4,
                        top: snowed(Map3DPalette.roof), side: wall, topPaint: roofing, frontPaint: windows, flankPaint: windows)
            return
        }
        let floors = min(r(2) < 0.6 ? 1 : 2, max(tallest ?? 2, 1))
        // Alone in its yard: narrower than its lot, and no deeper than a
        // house is.
        let wide = min(max(width * 0.72, 6), 12, width - 0.6), deep = min(depth, 7 + r(3) * 2)
        guard wide >= 3 else { return }
        let wall = varied(pick(Map3DNordic.houseWalls, r(1043)), r(1041)), roof = snowed(pick(Map3DNordic.pitchedRoofs, r(1040)))
        let across = Map3DPoint(-front.z, 0, front.x)
        let plinth: Float = far ? 0 : 0.4
        if !far {
            mesh.addBox(base: middle, forward: front, length: deep, width: wide, height: plinth, top: Map3DNordic.trim, side: Map3DNordic.trim,
                        capped: false)
        }
        let height = Float(floors) * Map3DNordic.storey + (far ? 0.4 : 0)
        let windows = Map3DPaint.bays(.flatWindows, bay: 3.4, floors: floors)
        mesh.addBox(base: middle + Map3DPoint(0, plinth, 0), forward: front, length: deep, width: wide, height: height, top: roof, side: wall,
                    frontPaint: windows, flankPaint: windows, capped: false)
        mesh.addGableRoof(base: middle + Map3DPoint(0, plinth + height, 0), forward: across, length: wide, width: deep,
                          rise: deep / 2 * Map3DNordic.pitch, overhang: 0.5, color: roof, gable: wall)
    }
}
