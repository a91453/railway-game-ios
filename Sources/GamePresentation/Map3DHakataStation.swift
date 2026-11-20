/// FUKUOKA-LANDMARKS (decision 854's later note): Hakata Station, the
/// local studio's model (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/fukuoka-landmarks-2026-11/revision-4`):
/// the main building, the platform roofs east of it and the Hakata exit's
/// canopy, written here by `tools/landmarks/glb_to_swift.py`
/// (``encoded``). Decision 895: a registered landmark.
enum Map3DHakataStation {
    static let registration = Map3DLandmarkRegistration(
        id: "hakata-station", map: "fukuoka",
        // The middle of the model's footprint (main building, platform
        // roofs and the canopy at the Hakata exit): the main building's
        // centroid (OpenStreetMap way 72653571) moved 25.37 m east and
        // 40.09 m south.
        latitude: 33.5895973, longitude: 130.4203736,
        // bandDark (not lit), roofSlate, wallPale, glassBlueGrey (lit at
        // night), roofGreen, steel.
        palette: [Map3DPalette.dark, Map3DPalette.cityRoofs[1].color, Map3DPalette.cityConcreteWalls[4],
                  Map3DPalette.cityOfficeWalls[5], Map3DPalette.cityRoofs[3].color, Map3DPalette.steel],
        glass: [3],
        encoded: encoded,
        // OpenStreetMap's outlines of the main building and the platform
        // roofs, and the Hakata exit's canopy to the west.
        size: (196.7, 400.7, 63.05))
}
