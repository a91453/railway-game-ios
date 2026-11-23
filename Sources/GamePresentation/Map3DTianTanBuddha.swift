/// Decision 938: the Tian Tan Buddha (天壇大佛) at Ngong Ping, Lantau,
/// where the Ngong Ping cable car ends: the seated bronze Buddha, his
/// right hand raised, on his lotus over three round terraces, facing
/// north-east down his stairs. Modelled by the local studio from
/// photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/hk-tiantan-buddha-2026-11/revision-4`;
/// lessons in `docs/studio/lessons/hk-tiantan-buddha.md`) and written here
/// by `tools/landmarks/glb_to_swift.py` (``encoded``), turned to
/// OpenStreetMap's stairs and without the long flight of stairs, which
/// falls 60 m where the game's ground falls 24 m.
enum Map3DTianTanBuddha {
    static let registration = Map3DLandmarkRegistration(
        id: "hk-tiantan-buddha", map: "hongkong",
        // The middle of OpenStreetMap's outline of the terraces (way
        // 45659816), which is the statue's (way 396857659) too.
        latitude: 22.253960, longitude: 113.905012,
        // bronze (the body and the lotus), bronzeDark (the hair), stone
        // (the terraces' walls and the short steps), concrete (the
        // terraces' walks), tileWhite (the balustrades), dark (the
        // terraces' doorways).
        palette: [Map3DPalette.counters[1], Map3DPalette.arcade, Map3DPalette.stone, Map3DPalette.concrete,
                  Map3DPalette.tileWhite, Map3DPalette.dark],
        encoded: encoded,
        // The lowest terrace 42.2 m across (a sixteen-sided ring, turned),
        // the top of his head 34 m over its foot, the short steps' foot
        // 0.35 m under it.
        size: (42.46, 42.46, 34.35))
}
