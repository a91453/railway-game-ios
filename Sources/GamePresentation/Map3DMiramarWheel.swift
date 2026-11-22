/// Decision 926: the Miramar Ferris wheel (美麗華摩天輪) at Dazhi, on the
/// roof of its shopping centre: a 70 m wheel of red and white cabins on
/// two A-frames. Modelled by the local studio from photographs
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-landmark-miramar-wheel-2026-11/revision-1`,
/// #273), turned 45° clockwise so its wheel runs east and west, along the
/// long side of the shopping centre's OpenStreetMap outline (way
/// 155816458), and written here by `tools/landmarks/glb_to_swift.py`
/// (``encoded``).
enum Map3DMiramarWheel {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-miramar-wheel", map: "taiwan",
        // OpenStreetMap's node of the wheel (5121602758).
        latitude: 25.0828070, longitude: 121.5577156,
        // On the shopping centre's roof: its top 100 m above the ground
        // (the node's `height`), 83.3 m above its platform's foot, over
        // the map's ground there (16.7 m).
        baseHeight: 33.4,
        // frame, frameShade, cable, hub, cabinRed, cabinWhite, deck, warm_lit.
        palette: [Map3DPalette.tileWhite, Map3DPalette.mtrRoofSilver, Map3DPalette.mastSteel, Map3DPalette.steel,
                  Map3DPalette.mtrRed, Map3DPalette.tankWhite, Map3DPalette.concrete, Map3DPalette.tunnelLamp],
        encoded: encoded,
        size: (79.89, 14.0, 83.34))
}
