// Decision 1018 (continued 5): 碧潭吊橋, the footbridge over the Xindian
// River at Bitan (1937): its two white portal towers with their X
// bracing, the four main cables hung between them over the 193 m of
// timber deck, the red handrails over the white railings, the wind cables
// spread under it. Modelled by the local studio from photographs and
// OpenStreetMap (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/tw-bitan-bridge-2026-11/revision-2`, #651;
// lessons in `docs/studio/lessons/tw-bitan-bridge.md`), its +x toward the
// east bank, and written here by `tools/landmarks/glb_to_swift.py
// --centre --turn 4.7 --raise 7` (``encoded``): turned onto
// OpenStreetMap's way, and raised by the 7 m its abutments reach down
// the banks.

/// The deck 7 m over the model's foot is set level with the drawn ground
/// at its two ends (``Map3DLandmarkRegistration/deck``), where the paths
/// come onto it from the banks, and the abutments reach down the banks
/// under it; the map draws no road of its own over it to leave out.
enum Map3DBitanBridge {
    /// tileWhite (the towers, the railings), concrete (the abutments and
    /// anchorages), dark (the main and wind cables), steel (the saddles,
    /// hangers and the steel under the deck), timber (the deck), mtrRed
    /// (the handrails and the railings' posts).
    static let palette: [UInt32] = [Map3DPalette.tileWhite, Map3DPalette.concrete, Map3DPalette.dark, Map3DPalette.steel,
                                    Map3DPalette.timber, Map3DPalette.mtrRed]

    static let registration = Map3DLandmarkRegistration(
        id: "tw-bitan-bridge", map: "taiwan",
        // The middle of OpenStreetMap's way 1004055340 (the deck, its
        // line 85.3° east of north), the studio's origin.
        latitude: 24.9563720, longitude: 121.5360047,
        deck: 7.0,
        palette: palette,
        encoded: encoded,
        // 198 m by 5.2 m turned 4.7°; the towers' saddles 20.5 m over
        // the deck, the abutments' foot 7 m under it.
        size: (197.76, 21.40, 27.50))
}
