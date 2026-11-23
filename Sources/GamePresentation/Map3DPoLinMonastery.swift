/// Decision 938: Po Lin Monastery (寶蓮禪寺) at Ngong Ping, Lantau, below
/// the Tian Tan Buddha: the Grand Hall of Ten Thousand Buddhas (萬佛寶殿)
/// under its four orange eaves and, before it to the west, the Hall of
/// the Great Hero (大雄寶殿). Modelled by the local studio from a
/// photograph (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/hk-tiantan-buddha-2026-11/revision-4`;
/// lessons in `docs/studio/lessons/hk-tiantan-buddha.md`) and written here
/// by `tools/landmarks/glb_to_swift.py` (``encoded``), turned to
/// OpenStreetMap's two halls.
enum Map3DPoLinMonastery {
    static let registration = Map3DLandmarkRegistration(
        id: "hk-po-lin-hall", map: "hongkong",
        // The middle of OpenStreetMap's outlines of the two halls taken
        // together (ways 486775882 and 46486825), on the line of their
        // steps (ways 1515769010 and 1515769014).
        latitude: 22.2555104, longitude: 113.9080928,
        // roofOrange, ridge (the ridges, the eaves' edges, the columns,
        // walls and gallery rails), stone (the terraces), tileWhite (the
        // terraces' balustrades), dark (the window bands and doors),
        // concrete (the path between the halls).
        palette: [Map3DPalette.templeRoof, Map3DPalette.templeRidge, Map3DPalette.stone, Map3DPalette.tileWhite,
                  Map3DPalette.dark, Map3DPalette.concrete],
        encoded: encoded,
        // The two halls 75.2 m from back to front and 51 m across, turned
        // 2.7 degrees off east to west; the great hall's ridge 35 m up.
        size: (76.53, 52.4, 35.0))
}
