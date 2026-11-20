/// FUKUOKA-LANDMARKS (decision 854's later note): Fukuoka Tower at
/// Momochihama, the owner's own model from the earlier version
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/fukuoka-landmarks-2026-11/old-version`),
/// its mast stretched to the real 234 m and turned as OpenStreetMap's
/// outline, written here by `tools/fukuoka-map/fukuoka_tower.py`
/// (``encoded``). Decision 895: a registered landmark.
enum Map3DFukuokaTower {
    static let registration = Map3DLandmarkRegistration(
        id: "fukuoka-tower", map: "fukuoka",
        // The middle of the model's footprint (fukuoka_tower.py prints it).
        latitude: 33.5933022, longitude: 130.3514745,
        // FUKUOKA-TOWER-COLOUR: mirror glass, the sky's blue in it by day
        // (lit at night), and the mast's steel.
        palette: [Map3DPalette.officeWalls[2], Map3DPalette.steel],
        glass: [0],
        encoded: encoded,
        // The earlier version's model, its mast to the real 234 m.
        size: (19.8, 21.4, 234.0))
}
