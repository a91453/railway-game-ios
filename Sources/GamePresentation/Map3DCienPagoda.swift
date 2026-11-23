/// Decision 928: Ci'en Pagoda (慈恩塔) on Shabalan Mountain above Sun Moon
/// Lake: nine octagonal storeys of brick with a dark eave and a white
/// balcony each, on its stepped terrace. Modelled by the local studio from
/// photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-landmark-cien-pagoda-2026-11/revision-2`,
/// #286; lessons in `docs/studio/lessons/tw-cien-pagoda.md`) and written
/// here by `tools/landmarks/glb_to_swift.py` (``encoded``). Its door is
/// taken to face north, toward the lake (not verified).
enum Map3DCienPagoda {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-cien-pagoda", map: "taiwan",
        // The tower's middle is OpenStreetMap's (way 1198896246,
        // 23.8419725, 120.9208010); the terrace reaches further south than
        // north, so the footprint's middle is 2.2 m south of it.
        latitude: 23.8419524, longitude: 120.9208010,
        // brickOrange, eave, eaveEdge, bracket, tileWhite (the balconies),
        // granite (the terrace), opening, gold (the finial).
        palette: [Map3DPalette.redBrick, Map3DPalette.dark, Map3DPalette.templeRidge, Map3DPalette.gymGreen,
                  Map3DPalette.tileWhite, Map3DPalette.granite, Map3DPalette.dark, Map3DPalette.gold],
        encoded: encoded,
        // The terrace 40 m by 28.55 m, the finial 47.5 m over it.
        size: (40.0, 28.55, 47.5))
}
