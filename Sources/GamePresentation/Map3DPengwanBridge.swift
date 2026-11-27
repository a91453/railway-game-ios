// Decision 1018 (continued 6): 鵬灣跨海大橋 over the mouth of Dapeng Bay
// (2011), the bridge that opens: its 72 m white sail-shaped tower with
// the one plane of gold stays fanned along the median, and the 20 m
// leaf at its north-west end raised 75° over the open channel, as it
// stands for the boats. Modelled by the local studio from photographs,
// the highway bureau's figures and OpenStreetMap (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/tw-pengwan-bridge-2026-11/revision-3`, #653;
// lessons in `docs/studio/lessons/tw-pengwan-bridge.md`), the 232 m
// straight of the bridge only (not its curved approaches), its +x toward
// the opening end, and written here by `tools/landmarks/glb_to_swift.py
// --centre --turn 134.7 --raise 5.5` (``encoded``): turned onto
// OpenStreetMap's ways, and raised by the 5.5 m its piers reach under the
// water, which ``registration``'s `sink` lowers again, so the water at
// its middle is the bay's.

/// The base map's own bridges (the two carriageways with their curved
/// approaches, some 455 m each) are kept and lifted onto its deck
/// (``deck``, as decision 944 lifts the road onto 關渡大橋's), so the
/// cars cross on it and come down the approaches to the banks at their
/// grade, and no pier of the roads' own stands under it.
enum Map3DPengwanBridge {
    /// tileWhite (the tower, the white railings), concrete (piers, the
    /// box girder, the median, the opening's piers), portal (the piers
    /// at the waterline), gold (the stays, the leaf's railings), mtrCharcoal
    /// (the road and the leaf), steel (the leaf's ribs, the outer
    /// railings), terrazzo (the cycle paths), dark (the machinery's pits).
    static let palette: [UInt32] = [Map3DPalette.tileWhite, Map3DPalette.concrete, Map3DPalette.portal, Map3DPalette.gold,
                                    Map3DPalette.mtrCharcoal, Map3DPalette.steel, Map3DPalette.terrazzo, Map3DPalette.dark]

    static let registration = Map3DLandmarkRegistration(
        id: "tw-pengwan-bridge", map: "taiwan",
        // The middle of OpenStreetMap's straight (ways 224228578 and
        // 224228579, along 315.3°), the studio's origin.
        latitude: 22.4493010, longitude: 120.4545770,
        sink: 5.5,
        palette: palette,
        encoded: encoded,
        // 232 m by 29.6 m turned 134.7°: its footprint's box east and
        // north; the tower 72 m over the water, the piers' feet 5.5 m
        // under it.
        size: (181.10, 182.64, 77.50))

    /// The deck the model carries the road on.
    static let deck = Map3DArchBridgeDeck(
        latitude: registration.latitude, longitude: registration.longitude, bearing: 315.3,
        // The model's straight: 116 m either side of its middle, 14.8 m
        // either side of its line.
        half: 116, width: 14.8,
        // Its road's top over the water at its middle.
        top: 17.5)
}
