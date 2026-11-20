/// FUKUOKA-LANDMARKS (decision 854's later note): Fukuoka Tower at
/// Momochihama, the owner's own model from the earlier version
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/fukuoka-landmarks-2026-11/old-version`),
/// its body stretched to about 150 m and its mast to the real 234 m,
/// turned as OpenStreetMap's outline (FUKUOKA-TOWER-GLASS), written here by `tools/fukuoka-map/fukuoka_tower.py`
/// (``encoded``). Decision 895: a registered landmark.
enum Map3DFukuokaTower {
    static let registration = Map3DLandmarkRegistration(
        id: "fukuoka-tower", map: "fukuoka",
        // The middle of the model's footprint (fukuoka_tower.py prints it).
        latitude: 33.5933022, longitude: 130.3514745,
        // glassSky (FUKUOKA-TOWER-COLOUR: mirror glass, the sky's blue in
        // it by day), steelGrey (the mast), mullionWhite (the lift shaft's
        // column and the southern faces' slits), bandDark (the slits'
        // notches, not lit).
        palette: [Map3DPalette.officeWalls[2], Map3DPalette.steel, Map3DPalette.cityOfficeWalls[4], Map3DPalette.dark],
        // FUKUOKA-TOWER-GLASS: its glass banded by its floors rather than
        // its mullions (``Map3DVertex/floorLines``), as its bands of
        // mirror panes; lit at night as the rest.
        bandedGlass: [0],
        encoded: encoded,
        // The earlier version's model, its mast to the real 234 m.
        size: (19.8, 21.4, 234.0))
}
