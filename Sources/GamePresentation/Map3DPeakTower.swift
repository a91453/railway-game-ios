/// Decision 913: the Peak Tower (凌霄閣) at the Peak Tram's upper end: the
/// silver "wok" on two white piers over its plinth. Modelled by the local
/// studio from photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/hk-peak-tower-2026-11/revision-1`, #245),
/// turned 5.5° clockwise as OpenStreetMap's outline (way 143716612), its
/// plaza front to the south, and written here by
/// `tools/landmarks/glb_to_swift.py` (``encoded``, raised 8 m so the
/// plinth's foot down the hillside is its 0).
enum Map3DPeakTower {
    static let registration = Map3DLandmarkRegistration(
        id: "hk-peak-tower", map: "hongkong",
        // OpenStreetMap's outline (the wok) has its middle 2.93 m north of
        // the model's footprint's, which reaches further over the plaza.
        latitude: 22.2712286, longitude: 114.1499858,
        // Its plaza floor (14.5 m above its foot: 8 m of plinth down the
        // hillside and 6.5 m of wall under the plaza) on the ground.
        sink: 14.5,
        // wokSilver, wokUnder, windowDark, glassBlueGrey, white (the
        // piers and plinth), tileWhite (the roof's parapet), concrete.
        palette: [Map3DPalette.mtrRoofSilver, Map3DPalette.steel, Map3DPalette.dark, Map3DPalette.cityOfficeWalls[5],
                  Map3DPalette.cityConcreteWalls[4], Map3DPalette.tileWhite, Map3DPalette.concrete],
        glass: [3],
        encoded: encoded,
        size: (71.02, 40.89, 43.0))
}
