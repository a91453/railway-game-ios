/// Decision 1033: JR Kyushu's Ōmura depot (大村車両基地) of the Nishi
/// Kyushu Shinkansen, between Ureshino-Onsen and Shin-Ōmura, the local
/// studio's models (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/omura-depot-2026-11/revision-3`; lessons in
/// `docs/studio/lessons/omura-depot.md`), written here by
/// `tools/landmarks/glb_to_swift.py` (``encoded``). Only its buildings:
/// the three maintenance sheds on OpenStreetMap's outlines (ways
/// 951579151, 951579150 and 951579149), their eleven doors on the real
/// stabling tracks, and the office building on the clear ground east of
/// them. The game lays no depot here (decision 998 §3: the line's three
/// sets stable at Nagasaki), so the sheds stand as a landmark does, where
/// the player's track does not run, and change nothing a train does.
/// Decision 895: registered landmarks.
enum Map3DOmuraDepotSheds {
    static let registration = Map3DLandmarkRegistration(
        id: "omura-depot-sheds", map: "fukuoka",
        // The middle of the three sheds' footprint: the studio's origin
        // (32.9562369, 129.9453345, the middle of the west and east sheds'
        // OpenStreetMap centroids) moved 0.32 m east and 33.64 m north;
        // its +X towards 158.1°, along the tracks (glb_to_swift.py
        // --turn -68.1 --centre).
        latitude: 32.9565411, longitude: 129.9453379,
        palette: Map3DOmuraDepotOffice.palette,
        glass: [5],
        encoded: encoded,
        // The model's own rectangle (X −193.11…137.48 m, Y −42.22…46.68 m)
        // turned: the main line runs 6 m clear of it, inside its box east
        // and north.
        body: [(-111.52, 129.79), (11.79, -176.95), (94.27, -143.79), (-29.04, 162.95)],
        // The three sheds together, 330.59 × 88.90 m and 12.5 m at the
        // east shed's ridge, turned to east and north.
        size: (188.54, 312.55, 12.5))
}

enum Map3DOmuraDepotOffice {
    /// tileWhite, tankSteel, steel, concrete, dark (the doorways, not lit)
    /// and glass (the windows: the office's bands, the sheds' clerestory).
    static let palette: [UInt32] = [
        Map3DPalette.tileWhite, Map3DPalette.tankSteel, Map3DPalette.steel, Map3DPalette.concrete, Map3DPalette.dark,
        Map3DTEMU2000.glass,
    ]

    static let registration = Map3DLandmarkRegistration(
        id: "omura-depot-office", map: "fukuoka",
        // The studio's place for it on the clear ground east of the sheds
        // (README §1.1: OpenStreetMap's way 951579141 stands over a
        // stabling track), its long side towards 168.3°
        // (glb_to_swift.py --turn -78.3).
        latitude: 32.9542318, longitude: 129.9465771,
        palette: palette,
        glass: [5],
        encoded: encoded,
        // Its own rectangle with the canopies, turned.
        body: [(-14.18, 22.85), (-3.94, -26.6), (14.47, -22.79), (4.23, 26.66)],
        // 50.5 × 18.8 m with its canopies, 11.8 m to its plant room,
        // turned to east and north.
        size: (25.84, 52.68, 11.8))
}
