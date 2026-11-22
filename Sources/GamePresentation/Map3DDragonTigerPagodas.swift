/// Decision 927: the Dragon and Tiger Pagodas (龍虎塔) on Lotus Pond,
/// Zuoying, Kaohsiung: two seven-storey octagonal towers on one platform
/// over the water, the dragon before the north one and the tiger before
/// the south, a zigzag bridge west toward the shore. Modelled by the local
/// studio from photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-landmark-dragon-tiger-pagodas-2026-11/revision-2`,
/// #277; lessons in `docs/studio/lessons/tw-dragon-tiger-pagodas.md`),
/// turned 19.3° clockwise as OpenStreetMap's two towers stand (ways
/// 81161400 and 81161399, the dragon's 7 m east of the tiger's), and
/// written here by `tools/landmarks/glb_to_swift.py` (``encoded``). Its z
/// 0 is the pond's surface, which is the ground the map draws there.
enum Map3DDragonTigerPagodas {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-dragon-tiger-pagodas", map: "taiwan",
        // The towers' middle (OpenStreetMap's outlines, 22.6804762,
        // 120.2924792); the model's footprint reaches 36 m west over the
        // bridge, so its middle is 20.3 m west of it.
        latitude: 22.6804755, longitude: 120.2922813,
        // wall and gold (the same yellow), roofTile (the eaves), roofTrim
        // (the dragon), column, rail, opening, warm_lit (the lamps under
        // the eaves).
        palette: [Map3DPalette.gold, Map3DPalette.timber, Map3DPalette.mtrTeal, Map3DPalette.mtrRed,
                  Map3DPalette.stone, Map3DPalette.gold, Map3DPalette.dark, Map3DPalette.tunnelLamp],
        encoded: encoded,
        // 65.9 m by 39 m (bridge, platform, towers) turned 19.3°, the
        // spires 27.9 m over the water.
        size: (71.47, 42.92, 27.9))
}
