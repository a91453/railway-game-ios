// Decision 1018: Kumamoto Castle (熊本城) on the Fukuoka map's south end:
// the great and small keeps on their curving stone walls (musha-gaeshi),
// and the Uto turret (宇土櫓), the three-storey turret that has stood
// since the castle was built. Modelled by the local studio from
// photographs (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/kumamoto-castle-2026-11/revision-2`; lessons
// in `docs/studio/lessons/kumamoto-castle.md`), turned 90° clockwise (the
// studio's +x is south) and written here by
// `tools/landmarks/glb_to_swift.py --centre --turn -90` (``encoded``).

extension Map3DPalette {
    /// Decision 1018: grey roof tiles (the castle's, Chi Lin Nunnery's),
    /// the studio's `slate`, the tourist train's roof grey.
    static let roofSlate = Map3DColor.rgb(0x5A5F65)
}

/// The great keep with the small keep to its north, on their stone walls.
enum Map3DKumamotoCastleKeep {
    /// dark, tileWhite, slate, portal: the black weatherboards, the white
    /// plaster and eaves, the grey tile roofs, the grey stone walls.
    static let palette: [UInt32] = [Map3DPalette.dark, Map3DPalette.tileWhite, Map3DPalette.roofSlate, Map3DPalette.portal]

    static let registration = Map3DLandmarkRegistration(
        id: "kumamoto-castle-keep", map: "fukuoka",
        // The model's footprint middle, 11.25 m north of the great keep's
        // middle, which is the south part of OpenStreetMap's outline (way
        // 331477851, 31.4 m by 53.5 m over both keeps; the model 31.1 m
        // by 58.1 m with the walls' foot).
        latitude: 32.8061532, longitude: 130.7058624,
        palette: palette,
        encoded: encoded,
        size: (31.12, 58.12, 38.00))
}

/// The Uto turret on its stone wall.
enum Map3DKumamotoCastleUto {
    static let registration = Map3DLandmarkRegistration(
        id: "kumamoto-castle-uto-yagura", map: "fukuoka",
        // The square north part of OpenStreetMap's L-shaped outline (way
        // 331477852; the long arm south of it is the turret's single-storey
        // wing, not modelled).
        latitude: 32.8065090, longitude: 130.7048139,
        palette: Map3DKumamotoCastleKeep.palette,
        encoded: encoded,
        size: (22.66, 24.66, 26.00))
}
