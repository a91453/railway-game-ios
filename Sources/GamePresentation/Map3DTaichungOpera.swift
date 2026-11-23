/// Decision 928: the National Taichung Theater (臺中國家歌劇院): a white
/// box cut by curved openings, its glass walls behind them and the plaza
/// before it. Modelled by the local studio from photographs
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-landmark-taichung-opera-2026-11/revision-2`,
/// #293; lessons in `docs/studio/lessons/tw-taichung-opera.md`), already
/// turned as OpenStreetMap's outline stands (its long side bearing 32°,
/// the plaza to the south-east), and written here by
/// `tools/landmarks/glb_to_swift.py` (``encoded``).
enum Map3DTaichungOpera {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-taichung-opera", map: "taiwan",
        // The building's middle is OpenStreetMap's (way 222636759,
        // 24.1629259, 120.6405173); the footprint's is 0.7 m west and
        // north of it.
        latitude: 24.1629319, longitude: 120.6405109,
        // wall, glass, paving, hole (the openings' shade), foyer_lit.
        palette: [Map3DPalette.tankWhite, Map3DPalette.glazing, Map3DPalette.granite, Map3DPalette.mtrCharcoal,
                  Map3DPalette.tunnelLamp],
        encoded: encoded,
        // The turned building and its plaza, 127 m by 143 m; the roof
        // 36.5 m.
        size: (126.99, 142.96, 36.5))
}
