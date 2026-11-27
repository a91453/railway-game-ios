// Decision 1018: Suizenji Jojuen (水前寺成趣園), Kumamoto's stroll garden on
// the Fukuoka map: its small Mount Fuji of lawn, the thatched Kokin-denju
// teahouse (古今伝授の間) and Izumi Shrine (出水神社). Modelled by the local
// studio from photographs and OpenStreetMap's outlines
// (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/suizenji-garden-2026-11/revision-3`; lessons
// in `docs/studio/lessons/suizenji-garden.md`), already turned as each
// stands, and written here by `tools/landmarks/glb_to_swift.py --centre`
// (``encoded``). The Noh stage and the two stone bridges came later, with
// the far models the studio added in `revision-4` (decision 1018,
// continued 3).
//
// Each stands where the studio's garden overview put it: metres east and
// north of the mound's peak (OpenStreetMap node 6393522205, 32.7913322,
// 130.735541), at the middle of its OpenStreetMap outline.

/// The lawn mound shaped as Mount Fuji, 8 m tall, 36 m across, with three
/// round shrubs beside it. Its foot reaches 0.3 m below the ground, so it
/// is sunk that far (`--raise 0.3`).
enum Map3DSuizenjiFujiMound {
    static let registration = Map3DLandmarkRegistration(
        id: "suizenji-fuji-mound", map: "fukuoka",
        latitude: 32.7913322, longitude: 130.7355410,
        sink: 0.3,
        // lawn, shrub.
        palette: [Map3DPalette.embankment, Map3DPalette.crown],
        encoded: encoded,
        size: (36.00, 36.00, 8.30))
}

/// The Kokin-denju teahouse with its silver-grey thatch, turned 10.2°
/// clockwise as its outline (way 277383480) lies.
enum Map3DSuizenjiTeahouse {
    static let registration = Map3DLandmarkRegistration(
        id: "suizenji-teahouse", map: "fukuoka",
        // 159.1 m west and 55.0 m south of the mound's peak.
        latitude: 32.7908363, longitude: 130.7338427,
        // stone, timberSiding, dark, roofTile, thatch.
        palette: [Map3DPalette.concrete, Map3DPalette.timberSiding, Map3DPalette.dark, Map3DPalette.arcade, Map3DPalette.plant],
        encoded: encoded,
        size: (13.96, 16.22, 9.00))
}

/// Izumi Shrine's halls round their court, dark red-brown wood under grey
/// tile, the gold ornament in the front gable (way 277383478).
enum Map3DSuizenjiShrine {
    static let registration = Map3DLandmarkRegistration(
        id: "suizenji-shrine", map: "fukuoka",
        // 113.3 m west and 62.2 m north of the mound's peak.
        latitude: 32.7918927, longitude: 130.7343311,
        // stone, dark, shrineRed, roofTile, gold.
        palette: [Map3DPalette.concrete, Map3DPalette.dark, Map3DPalette.cityRoofs[2].color, Map3DPalette.arcade, Map3DPalette.gold],
        encoded: encoded,
        size: (49.36, 46.44, 11.24))
}

/// The Noh stage (能楽殿) by the pond's south shore: the open square stage
/// under its hipped-and-gabled grey tile roof, the bridgeway (橋掛り) and the
/// mirror room (鏡の間) to its east, plain wood (way 1558522737).
enum Map3DSuizenjiNohStage {
    static let registration = Map3DLandmarkRegistration(
        id: "suizenji-noh-stage", map: "fukuoka",
        // 90.0 m west and 169.3 m south of the mound's peak: the stage's
        // outline middle, the model's middle 5.52 m east of it, as the
        // bridgeway and the mirror room reach east.
        latitude: 32.7898054, longitude: 130.7345803,
        // roofTile, wood, dark, stone.
        palette: [Map3DPalette.arcade, Map3DPalette.timber, Map3DPalette.dark, Map3DPalette.concrete],
        encoded: encoded,
        size: (20.24, 6.30, 7.43))
}

/// The two low stone bridges across the pond's north-west arm, one model
/// turned as each lies (the studio's garden overview, its west bridge 3°
/// and its east one 170° anticlockwise), their feet at the water, 0.1 m
/// below the garden's ground (`sink`). Each turn is written as a model of
/// its own (``encoded`` of each enum) because the converter turns the mesh.
enum Map3DSuizenjiWestBridge {
    static let registration = Map3DLandmarkRegistration(
        id: "suizenji-stone-bridge-west", map: "fukuoka",
        // 143.0 m west and 4.0 m south of the mound's peak.
        latitude: 32.7912961, longitude: 130.7340144,
        sink: 0.1,
        // stone.
        palette: [Map3DPalette.concrete],
        encoded: encoded,
        size: (9.24, 2.92, 1.80))
}

enum Map3DSuizenjiEastBridge {
    static let registration = Map3DLandmarkRegistration(
        id: "suizenji-stone-bridge-east", map: "fukuoka",
        // 130.5 m west and 8.0 m north of the mound's peak.
        latitude: 32.7914043, longitude: 130.7341478,
        sink: 0.1,
        // stone.
        palette: [Map3DPalette.concrete],
        encoded: encoded,
        size: (9.40, 3.98, 1.80))
}
