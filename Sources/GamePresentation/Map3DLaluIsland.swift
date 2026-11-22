/// Decision 928: Lalu Island (拉魯島) in the middle of Sun Moon Lake: a low
/// mound of grass and trees with a stone rim, and the floating reed rafts
/// either side of it. Modelled by the local studio from photographs
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-landmark-cien-pagoda-2026-11/revision-2`,
/// #286; lessons in `docs/studio/lessons/tw-cien-pagoda.md`) and written
/// here by `tools/landmarks/glb_to_swift.py --raise 0.5` (``encoded``):
/// its rim reaches half a metre under the water, so it is sunk that far.
/// Which way the rafts lie is the studio's reading of one photograph (not
/// verified).
enum Map3DLaluIsland {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-lalu-island", map: "taiwan",
        // The island's middle is OpenStreetMap's (way 558290837,
        // 23.8556785, 120.9112909); with its rafts the footprint's middle
        // is 2.5 m west and 2.7 m south of it.
        latitude: 23.8556540, longitude: 120.9112660,
        sink: 0.5,
        // grass, stone, crown, trunk, reed (the rafts).
        palette: [Map3DPalette.embankment, Map3DPalette.stone, Map3DPalette.crown, Map3DPalette.trunk, Map3DPalette.arcade],
        encoded: encoded,
        // 78.9 m by 21.5 m with the rafts, the treetops 9.6 m over the
        // water.
        size: (78.88, 21.47, 10.1))
}
